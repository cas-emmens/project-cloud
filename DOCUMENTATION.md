# Orange Kuma Platform — Setup Documentation

**Project:** Cloud S2 2526 — Orange Kuma  
**Date:** May 10, 2026  
**Author:** Cas Emmens  
**Cluster:** emmens-cluster (Proxmox 8, Hanze University)

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture Decisions](#2-architecture-decisions)
3. [Infrastructure Overview](#3-infrastructure-overview)
4. [Cleanup of Previous Environment](#4-cleanup-of-previous-environment)
5. [VM Provisioning](#5-vm-provisioning)
6. [k3s Cluster Installation](#6-k3s-cluster-installation)
7. [Platform Services](#7-platform-services)
8. [Service Access & Credentials](#8-service-access--credentials)
9. [Network Policies & Security](#9-network-policies--security)
10. [Automation & Greenfield Deployment](#10-automation--greenfield-deployment)
11. [Known Issues & Workarounds](#11-known-issues--workarounds)
12. [Customer Provisioning](#12-customer-provisioning)
13. [File Structure](#13-file-structure)

---

## 1. Project Overview

We are building a platform for a fictional ICT service provider that hosts "Orange Kuma" (a rebranded Uptime Kuma) for multiple customers. The assignment requires a fully automated DevSecOps pipeline including CI/CD, monitoring, and a provisioning interface usable by non-technical staff (a "verkoper").

We chose to run **everything on Kubernetes (k3s)** rather than mixing VMs, LXC containers, and k8s. This gives us one consistent deployment model, one monitoring approach, and a strong GitOps story through Argo CD.

---

## 2. Architecture Decisions

### Why k3s for the entire stack (not just Argo CD)?

The rubric awards bonus points for running Argo CD on Kubernetes. Since we need the k8s cluster anyway, running all services on it avoids the operational complexity of managing two different deployment models (VMs/LXC + k8s). Benefits:

- **Single deployment model** — everything is a container managed by k8s.
- **Consistent monitoring** — Prometheus with kube-state-metrics scrapes the entire cluster automatically.
- **GitOps** — Argo CD can manage all services, not just Orange Kuma.
- **Rubric alignment** — "Zeer goed" for Deployment requires "Applicatie in containers."

### Why local-path storage instead of Longhorn/Ceph?

We initially planned Longhorn for distributed storage, but the Debian 12 cloud image doesn't include `open-iscsi` (a Longhorn dependency) and the minimal repos on the school network don't provide it. k3s ships with the `local-path` provisioner by default, which stores persistent volumes on the node's local disk. This is sufficient for our use case — we're not running a production HA database. Ceph was removed because it consumed too many resources (~7 GB RAM per node) for our limited hardware.

### Why namespace isolation instead of node separation?

Best practice in production is to separate customer-facing workloads from internal tools on different node pools. With only 3 nodes at 2 vCPUs each, we don't have enough resources for that. Instead, we use Kubernetes NetworkPolicies to isolate customer namespaces from each other and from internal services. This is documented in the security section and is a defensible architectural decision at this scale.

---

## 3. Infrastructure Overview

### Proxmox Cluster

| Node | IP | Role |
|------|-----|------|
| CE01 | 10.24.36.2 | Proxmox host, Ansible control node |
| CE02 | 10.24.36.3 | Proxmox host |
| CE3 | 10.24.36.4 | Proxmox host |

Each node: 2x Intel Xeon E5-2690 v4 @ 2.60GHz, 23 GB RAM, ~33 GB disk.

### k3s Virtual Machines

| VM ID | Hostname | IP | Node | k3s Role |
|-------|----------|-----|------|----------|
| 300 | k3s-server | 10.24.36.10 | CE01 | Server (control plane) |
| 301 | k3s-agent-1 | 10.24.36.11 | CE02 | Agent (worker) |
| 302 | k3s-agent-2 | 10.24.36.12 | CE3 | Agent (worker) |

Each VM: 2 vCPU, 16 GB RAM, 25 GB disk, Debian 12 (Bookworm) cloud-init image.

### Networking

All VMs are bridged on `vmbr0` (subnet `10.24.36.0/24`, gateway `10.24.36.1`). The school gateway does NOT provide DNS resolution for VMs, so DNS is configured to use `8.8.8.8` directly. Services are exposed via Kubernetes NodePorts on the k3s-server IP (`10.24.36.10`).

---

## 4. Cleanup of Previous Environment

The Proxmox cluster previously ran a Docker Swarm setup from the Cloud S1 course. The following was removed:

1. **VMs 200, 201, 202** (docker-01 through docker-03) — stopped and destroyed with `qm destroy`.
2. **Ceph cluster** — pools deleted (`ceph-pool`, `.mgr`), OSDs purged (0, 1, 2), monitors and managers stopped and disabled on all three nodes, data directories removed (`/var/lib/ceph`, `/etc/ceph`, `/var/log/ceph`). OSD partitions had to be unmounted first (`umount /var/lib/ceph/osd/ceph-*`).
3. **Ceph storage entry** — removed from Proxmox with `pvesm remove ceph-pool`.
4. **Old ISOs and templates** — removed `debian-13.4.0-amd64-netinst.iso`, `ubuntu-24.04.2-live-server-amd64.iso`, and the `/var/lib/vz/template/golden` and `cache` directories to free disk space on CE01. Kept `debian-12-generic-amd64.qcow2` as the base image for k3s VMs.
5. **SDN zones** — checked and confirmed empty (no vnets configured).

The `debian-12-generic-amd64.qcow2` image was then copied from CE01 to CE02 and CE3 via SCP since there's no shared storage anymore.

---

## 5. VM Provisioning

VMs are created by the `playbooks/create-vms.yml` Ansible playbook. It runs against the Proxmox nodes and performs the following for each VM:

1. `qm create` — creates the VM with 2 vCPU, 16 GB RAM, virtio NIC on vmbr0.
2. `qm importdisk` — imports the Debian 12 qcow2 cloud image into local-lvm storage.
3. `qm set` — attaches the disk, adds a cloud-init drive.
4. Cloud-init configuration — sets static IP, gateway, DNS (`8.8.8.8`), SSH public key, and user (`debian`).
5. `qm resize` — expands disk to 25 GB.
6. `qm start` — boots the VM.
7. Waits for SSH to become available (timeout 180s).

The playbook is idempotent — if a VM already exists, it skips creation.

### SSH Access

Ansible runs from CE01 as root. The SSH key at `/root/.ssh/id_rsa.pub` is injected into VMs via cloud-init. All VMs use the `debian` user with sudo access.

---

## 6. k3s Cluster Installation

The `playbooks/install-k3s.yml` playbook installs k3s in three stages:

### Stage 1: Prepare all nodes

- Installs `curl` (the only prerequisite available in the minimal Debian cloud image).
- Loads kernel modules: `br_netfilter`, `overlay`, `ip_tables`.
- Sets sysctl params: IP forwarding, bridge-nf-call-iptables.

### Stage 2: Install k3s server (on k3s-server only)

Runs the k3s install script with:

- `--cluster-cidr=10.42.0.0/16` — pod network.
- `--service-cidr=10.43.0.0/16` — service network.
- `--tls-san=10.24.36.10` — allows external kubeconfig access.
- `--disable=traefik` — we don't need the default ingress (using NodePorts).
- `--write-kubeconfig-mode=644` — readable kubeconfig.

After installation, it retrieves the node token and exports the kubeconfig (with the external IP substituted for `127.0.0.1`).

### Stage 3: Join agents

The two agent nodes join using the token from the server. The install script runs with `K3S_URL` pointing to `https://10.24.36.10:6443`.

### Storage

k3s ships with the `local-path` provisioner as the default StorageClass. All PersistentVolumeClaims use this. Data is stored locally on whichever node the pod runs on.

---

## 7. Platform Services

All services are deployed by `playbooks/bootstrap-platform.yml`. It installs Helm on the k3s server, creates namespaces, then deploys each service.

### Gitea (namespace: `gitea`)

Repository manager. Installed via the official Gitea Helm chart. PostgreSQL is deployed as a sub-chart for the database. An admin account (`gitea_admin`) is created automatically. Webhooks are configured to allow all hosts (needed for Drone CI integration).

### Drone CI (namespace: `drone`)

Continuous integration. Deployed as raw Kubernetes manifests (not Helm, because the Drone Helm chart is unmaintained). Two components:

- **Drone Server** — the web UI and API. Connected to Gitea via OAuth2 (the OAuth app is created automatically via the Gitea API during deployment).
- **Drone Runner (Kube)** — executes pipelines as Kubernetes pods in the `drone` namespace. Has `cluster-admin` permissions to create pipeline pods.

Drone secrets (Gitea OAuth client ID/secret, RPC secret) are stored in a Kubernetes Secret.

### Argo CD (namespace: `argocd`)

Continuous deployment / GitOps. Installed via the official Argo Helm chart. Configured in insecure mode (no TLS) for simplicity on the internal network. The initial admin password is auto-generated and retrieved from the `argocd-initial-admin-secret` Secret.

This is the Kubernetes bonus points item — Argo CD running natively on k3s, watching Gitea repos for changes, and automatically syncing deployments.

### Prometheus + Grafana + Alertmanager (namespace: `monitoring`)

Full monitoring stack installed via the `kube-prometheus-stack` Helm chart. This single chart deploys:

- **Prometheus** — scrapes metrics from all k8s nodes, pods, and services. 7-day retention, 5 GB persistent storage.
- **Grafana** — dashboards. Comes pre-configured with Kubernetes dashboards. 2 GB persistent storage.
- **Alertmanager** — alert routing. 2 GB persistent storage.
- **Node Exporter** — runs on every node, exports hardware/OS metrics.
- **kube-state-metrics** — exports Kubernetes object metrics.

This covers the "monitoring plus alerting" requirement for "Zeer goed."

### Semaphore (namespace: `semaphore`)

Ansible UI for provisioning. This is how the "verkoper" creates new customer instances. Deployed as a raw Kubernetes manifest with BoltDB (file-based database, no external DB needed). 1 GB persistent storage.

Important: the Kubernetes service is named `semaphore-ui` (not `semaphore`) because Kubernetes injects environment variables based on service names, and `SEMAPHORE_PORT=tcp://...` conflicts with Semaphore's own `SEMAPHORE_PORT` config (which expects just a number like `3000`).

### Headlamp (namespace: `kube-system`)

Kubernetes web UI. Installed via Helm. Provides a visual dashboard for the cluster, useful for demos and troubleshooting. Authentication is via a ServiceAccount token (stored at `/tmp/headlamp-token.txt` on the Ansible control node).

---

## 8. Service Access & Credentials

All services are accessible via NodePort on the k3s-server IP. You must be connected to the Hanze VPN (AnyConnect) to reach these.

| Service | URL | Username | Password |
|---------|-----|----------|----------|
| **Gitea** | http://10.24.36.10:30080 | `gitea_admin` | `OrangeKuma2025!` |
| **Gitea SSH** | `ssh://git@10.24.36.10:30022` | — | (SSH key auth) |
| **Drone CI** | http://10.24.36.10:30081 | (Gitea OAuth) | (login via Gitea) |
| **Argo CD** | http://10.24.36.10:30082 | `admin` | `nglzMT1U1LTDANG2` |
| **Grafana** | http://10.24.36.10:30083 | `admin` | `OrangeKuma2025!` |
| **Semaphore** | http://10.24.36.10:30084 | `admin` | `OrangeKuma2025!` |
| **Alertmanager** | http://10.24.36.10:30085 | — | (no auth) |
| **Headlamp** | http://10.24.36.10:30086 | — | (token auth, see below) |
| **Prometheus** | http://10.24.36.10:30090 | — | (no auth) |

**Headlamp token:** saved at `/tmp/headlamp-token.txt` on CE01. Copy-paste it into the Headlamp login page.

**Argo CD password:** auto-generated during installation. The password shown above was generated on May 10, 2026. If the cluster is redeployed, a new password will be generated and shown in the Ansible output. You can also retrieve it with:

```bash
ssh debian@10.24.36.10 "sudo kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
```

---

## 9. Network Policies & Security

Each Orange Kuma customer instance gets its own namespace (`customer-<name>`) with the following NetworkPolicies:

1. **Default deny ingress** — nothing can reach pods unless explicitly allowed.
2. **Default deny egress** — pods can only resolve DNS by default.
3. **Allow Orange Kuma traffic** — the Orange Kuma pod can receive incoming traffic (NodePort) and make outbound HTTP/HTTPS to the internet (needed for uptime monitoring). It is explicitly blocked from reaching other namespaces (pod CIDR `10.42.0.0/16` and service CIDR `10.43.0.0/16` are excluded from allowed egress).
4. **Allow Prometheus scraping** — the monitoring namespace can reach port 3001 in customer namespaces for metrics collection.

This means:
- Customer A cannot access Customer B's pods or data.
- Customer pods cannot access internal services (Gitea, Drone, etc.).
- Monitoring still works across all namespaces.

In a production environment with more resources, we would additionally use node taints and tolerations to physically separate customer workloads from infrastructure services.

---

## 10. Automation & Greenfield Deployment

The entire platform can be deployed from scratch with a single command:

```bash
cd /root/k3s-platform
export PROXMOX_PASSWORD="your-password"
export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
./deploy.sh
```

Or to destroy everything and redeploy:

```bash
./deploy.sh --destroy-first
```

The deploy script runs three phases:

1. **Phase 1** (`create-vms.yml`) — Create 3 VMs on Proxmox with cloud-init.
2. **Phase 2** (`install-k3s.yml`) — Install k3s server + join agents.
3. **Phase 3** (`bootstrap-platform.yml`) — Deploy all platform services via Helm and kubectl.

You can also resume from a specific phase if an earlier phase already completed:

```bash
./deploy.sh --phase 2   # Skip VM creation
./deploy.sh --phase 3   # Skip VMs and k3s, just deploy services
```

All playbooks are idempotent — running them again won't break anything.

---

## 11. Known Issues & Workarounds

### DNS resolution on VMs

The school gateway (`10.24.36.1`) does not provide DNS resolution for VMs on the `10.24.36.0/24` network. The Proxmox nodes themselves use `1.1.1.1`. We configured the VMs to use `8.8.8.8` via cloud-init and `systemd-resolved`. If DNS stops working after a reboot, check `/etc/resolv.conf` on the VMs.

### Minimal Debian cloud image

The `debian-12-generic-amd64.qcow2` image has very limited package repos. Packages like `open-iscsi`, `nfs-common`, and `apt-transport-https` are not available. This is why we use `local-path` storage instead of Longhorn. Only `curl` is installed as a prerequisite for k3s.

### Semaphore service name conflict

Kubernetes auto-injects environment variables for services (e.g., `SEMAPHORE_PORT=tcp://10.43.x.x:3000`). This conflicts with Semaphore's own config which expects `SEMAPHORE_PORT=3000`. The fix is naming the Kubernetes Service `semaphore-ui` instead of `semaphore`.

### Headlamp Helm repo URL

The Headlamp project moved from `https://headlamp-k8s.github.io/headlamp/` to `https://kubernetes-sigs.github.io/headlamp/`. The bootstrap playbook uses the correct URL.

### Host key conflicts on redeploy

When VMs are destroyed and recreated, the SSH host keys change. The `ansible.cfg` has `host_key_checking = False` to avoid failures during automated deployment. For manual SSH, you may need to clear old keys from `~/.ssh/known_hosts`:

```bash
ssh-keygen -f '/root/.ssh/known_hosts' -R '10.24.36.10'
```

---

## 12. Customer Provisioning

New Orange Kuma instances are deployed per customer using:

```bash
ansible-playbook playbooks/provision-customer.yml -e customer_name=acme -e customer_admin_password=SecurePass123
```

Or via the Semaphore UI (intended for the verkoper — no CLI required).

This creates:
- A namespace `customer-acme`
- NetworkPolicies for isolation
- An Orange Kuma deployment with persistent storage
- A NodePort service (auto-assigned port)
- A ServiceMonitor for Prometheus auto-discovery
- An Argo CD Application for GitOps management

To remove a customer:

```bash
ansible-playbook playbooks/remove-customer.yml -e customer_name=acme
```

Requires typing a confirmation string to prevent accidental deletion.

---

## 13. File Structure

```
k3s-platform/
├── deploy.sh                              # One-command greenfield deployment
├── README.md                              # Quick-start guide
├── DOCUMENTATION.md                       # This file
├── ansible/
│   ├── ansible.cfg                        # Ansible configuration
│   ├── inventory.yml                      # All hosts and variables
│   ├── site.yml                           # Master playbook (all phases)
│   └── playbooks/
│       ├── create-vms.yml                 # Phase 1: Create VMs on Proxmox
│       ├── destroy-vms.yml                # Destroy all VMs (for redeploy)
│       ├── install-k3s.yml                # Phase 2: Install k3s cluster
│       ├── bootstrap-platform.yml         # Phase 3: Deploy all services
│       ├── provision-customer.yml         # Create new customer instance
│       └── remove-customer.yml            # Remove customer instance
└── k8s/
    └── orange-kuma/
        └── customer-template.yml          # Template for customer deployments
```
