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
12. [Customer Provisioning (GitOps)](#12-customer-provisioning-gitops)
13. [Orange Kuma Image Customizations](#13-orange-kuma-image-customizations)
14. [Management Tool Dashboard](#14-management-tool-dashboard)
15. [Auto-Update Strategy](#15-auto-update-strategy)
16. [File Structure](#16-file-structure)

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

### Why Longhorn instead of Ceph?

The platform uses **Longhorn** for distributed storage. Longhorn replicates PersistentVolumes across nodes so a pod can restart on a different node after a node failure without losing data. It is installed via Helm in Phase 3 and requires `open-iscsi` on every node, which is available in the standard Debian 12 repository.

Ceph was considered but removed — it consumes ~7 GB RAM per node, which exceeds the available headroom on the school hardware (23 GB per node, already partially used by k3s services).

### Why namespace isolation instead of node separation?

Best practice in production is to separate customer-facing workloads from internal tools on different node pools. With only 3 nodes at 2 vCPUs each, we don't have enough resources for that. Instead, we use a Kubernetes NetworkPolicy to isolate customer namespaces from each other and keep the only customer-facing write path (Argo CD reconciliation) and a read-only control plane. This is documented in the security section and is a defensible architectural decision at this scale.

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

### Longhorn (namespace: `longhorn-system`)

Distributed block storage. Installed via the official Longhorn Helm chart before all other services. Replaces the k3s default `local-path` provisioner as the default StorageClass. Provides:

- **Replication** — each PersistentVolume is replicated across nodes (default: 3 replicas), so a pod survives a node failure with its data intact.
- **Volume expansion** — PVCs can be resized without recreating the pod.
- **Web UI** — accessible via `kubectl port-forward` in the `longhorn-system` namespace.

Requires `open-iscsi` installed and `iscsid` running on every node (handled by `install-k3s.yml`).

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

The CI/CD wiring (Phase 4, `setup-cicd-pipeline.yml`) configures Argo CD for customer provisioning:

- **AppProject `customer-provisioning`** — scopes what the customer Applications may deploy. `sourceRepos` lists the two Gitea provisioning repos; `clusterResourceWhitelist` permits `Namespace`; `namespaceResourceWhitelist` permits `Deployment`, `Service`, `PersistentVolumeClaim`, `NetworkPolicy`, `Secret`.
- **Two Applications** — `customer-instances` (sales lane) and `test-customers` (ops lane), each watching the matching Gitea repo with `directory.recurse: true`, `syncPolicy.automated` (prune + selfHeal), and `CreateNamespace=true`. Every `customers/<slug>.yaml` file committed to a repo becomes a reconciled `customer-<slug>` namespace.
- **Repo credential Secrets** — one per repo in the `argocd` namespace (labelled `argocd.argoproj.io/secret-type: repository`), authenticating Argo CD to Gitea over the in-cluster HTTP service `gitea-http.gitea.svc:3000`.

See [Section 12](#12-customer-provisioning-gitops) for the full provisioning flow.

### Argo CD Image Updater (namespace: `argocd`)

Automatically rolls customer instances onto new image builds. Installed via the official `argocd-image-updater` Helm chart, configured with the Gitea registry (`10.24.36.10:30080`, insecure) using the same read-only PAT minted for Argo CD repo access. The two customer Applications carry Image Updater annotations: when Drone publishes a new `orange-uptime-kuma` image tag, the updater rewrites the `image:` field in every `customers/*.yaml`, commits the change back to the Gitea repo (`write-back-method: git`), and Argo CD reconciles the new image into each customer's Deployment. See [Section 15](#15-auto-update-strategy).

### Prometheus + Grafana + Alertmanager (namespace: `monitoring`)

Full monitoring stack installed via the `kube-prometheus-stack` Helm chart. This single chart deploys:

- **Prometheus** — scrapes metrics from all k8s nodes, pods, and services. 7-day retention, 5 GB persistent storage.
- **Grafana** — dashboards. Comes pre-configured with Kubernetes dashboards. 2 GB persistent storage.
- **Alertmanager** — alert routing. 2 GB persistent storage.
- **Node Exporter** — runs on every node, exports hardware/OS metrics.
- **kube-state-metrics** — exports Kubernetes object metrics.

This covers the "monitoring plus alerting" requirement for "Zeer goed."

### Semaphore (namespace: `semaphore`)

Ansible UI for provisioning. This is the rubric-named tool through which the "verkoper" (and ops staff) create new customer instances — no CLI required. Deployed as a raw Kubernetes manifest with BoltDB (file-based database, no external DB needed). 1 GB persistent storage.

Phase 4 bootstraps Semaphore via its REST API: a project `Orange Kuma Provisioning`, a repository pointing at the project-cloud Gitea repo, a `localhost` inventory, and **two templates** that share the single `provision-customer.yml` playbook:

- **"Nieuwe klant aanmaken"** (sales) — commits the rendered manifest to the `customer-instances` repo.
- **"Testklant aanmaken"** (ops) — commits to the `test-customers` repo.

Both templates expose a survey form (customer name, email, admin password, optional domain) so non-technical staff fill in a form and hit Run. See [Section 12](#12-customer-provisioning-gitops).

Important: the Kubernetes Service is named `semaphore-ui` (not `semaphore`). A Service named `semaphore` would make Kubernetes inject `SEMAPHORE_PORT=tcp://<clusterIP>:3000` into the container; Semaphore reads `SEMAPHORE_PORT` as its own listen port and expects a bare number (`3000`), so the `tcp://` value makes it fail to bind and crash-loop. Renaming the Service avoids the collision entirely. The Deployment also has a readiness probe on `/api/ping` so a misconfigured pod fails the `rollout status` step with a clear signal instead of passing silently and breaking a later task.

The encryption key for Semaphore's BoltDB credential store is persisted in a Kubernetes Secret (`semaphore-secrets`) so it survives re-runs — see [Section 11](#11-known-issues--workarounds).

### Headlamp (namespace: `kube-system`)

Kubernetes web UI. Installed via Helm. Provides a visual dashboard for the cluster, useful for demos and troubleshooting. Authentication is via a ServiceAccount token (stored at `/tmp/headlamp-token.txt` on the Ansible control node).

### Management Tool (namespace: `orange-kuma`)

A branded, **read-only customer health dashboard** (NodePort `30087`), deployed in Phase 4. It lists every provisioned customer and surfaces pod status, Argo CD sync/health, the latest Gitea commit for the customer's manifest, and a deep-link button into the Semaphore sales template. It performs no writes — its ServiceAccount only has `get/list/watch` on a handful of resources. See [Section 14](#14-management-tool-dashboard).

---

## 8. Service Access & Credentials

All services are accessible via NodePort on the k3s-server IP. You must be connected to the Hanze VPN (AnyConnect) to reach these.

| Service | URL | Username | Password |
|---------|-----|----------|----------|
| **Gitea** | http://10.24.36.10:30080 | `gitea_admin` | `OrangeKuma2025!` |
| **Gitea SSH** | `ssh://git@10.24.36.10:30022` | — | (SSH key auth) |
| **Drone CI** | http://10.24.36.10 | (Gitea OAuth) | (login via Gitea) |
| **Argo CD** | http://10.24.36.10:30082 | `admin` | (auto-generated) |
| **Grafana** | http://10.24.36.10:30083 | `admin` | `OrangeKuma2025!` |
| **Semaphore** | http://10.24.36.10:30084 | `admin` | `OrangeKuma2025!` |
| **Alertmanager** | http://10.24.36.10:30085 | — | (no auth) |
| **Headlamp** | http://10.24.36.10:30086 | — | (token auth, see below) |
| **Management Tool** | http://10.24.36.10:30087 | — | (no auth; read-only dashboard) |
| **Prometheus** | http://10.24.36.10:30090 | — | (no auth) |

Drone is exposed via a `LoadBalancer` Service on port 80 (k3s ServiceLB binds it to the node IP) rather than a NodePort. Per-customer Orange Kuma admin credentials are set at provision time (`admin` / the password entered in the Semaphore form) and bootstrapped into the instance automatically on first boot.

**Headlamp token:** saved at `/tmp/headlamp-token.txt` on CE01. Copy-paste it into the Headlamp login page.

**Argo CD password:** auto-generated during installation and printed at the end of the deploy. If the cluster is redeployed, a new password is generated. You can retrieve it with:

```bash
ssh debian@10.24.36.10 "sudo kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
```

---

## 9. Network Policies & Security

### Namespace isolation

Each Orange Kuma customer instance gets its own namespace (`customer-<slug>`), labelled `app=orange-kuma`, `customer=<slug>`, and `provisioned-by=<sales|ops>`. The rendered manifest (`ansible/templates/customer-instance.yml.j2`) ships a single `deny-cross-customer` NetworkPolicy that:

- **Blocks cross-customer ingress** — a pod in one `customer-*` namespace cannot reach another customer's pods. Namespaces carrying a *different* `customer` label are denied.
- **Allows platform/monitoring ingress** — namespaces without a `customer` label (e.g. `monitoring`, ingress controllers) and the customer's own namespace can still reach the instance, so Prometheus scraping and external access keep working.

This means Customer A cannot access Customer B's pods or data, while monitoring and the platform still function.

### Read-only control plane

Provisioning writes happen **only** through the GitOps path (Semaphore → Gitea → Argo CD). The Management Tool dashboard's RBAC is strictly read-only (`get/list/watch` on namespaces, pods, services, deployments) — it can render status but never mutate the cluster. There is no component in the customer-facing path with write access to the cluster outside of Argo CD's reconciliation.

### Production hardening (out of scope at this scale)

In a production environment with more resources, this would be combined with dedicated node pools (taints/tolerations) and default-deny egress for full workload separation. At 6 vCPU total, namespace isolation plus the read-only control plane is the practical, defensible choice.

---

## 10. Automation & Greenfield Deployment

The entire platform can be deployed from scratch with a single command:

```bash
cd /root/project-cloud
export PROXMOX_PASSWORD="your-password"
./deploy.sh                              # Hanze cluster (default)
./deploy.sh --inventory inventories/test # Test cluster
```

The script auto-detects the SSH key from `~/.ssh/hanze_prox.pub`, `~/.ssh/id_ed25519.pub`, or `~/.ssh/id_rsa.pub` (in that order). To destroy everything and redeploy:

```bash
./deploy.sh --destroy-first
./deploy.sh --inventory inventories/test --destroy-first
```

The deploy script runs four phases:

1. **Phase 1** (`create-vms.yml`) — Create 3 VMs on Proxmox with cloud-init.
2. **Phase 2** (`install-k3s.yml`) — Install k3s server + join agents. Installs `open-iscsi` and `qemu-guest-agent` on all nodes.
3. **Phase 3** (`bootstrap-platform.yml`) — Deploy all platform services via Helm and kubectl (Longhorn, Gitea, Drone, Argo CD + Image Updater, Prometheus/Grafana, Semaphore + templates, Headlamp).
4. **Phase 4** (`setup-cicd-pipeline.yml`) — Wire CI/CD + GitOps: Gitea org/repos, Drone pipelines, Argo CD AppProject + Applications, Image Updater config, the Semaphore provisioning project, and the Management Tool dashboard.

You can also resume from a specific phase if an earlier phase already completed:

```bash
./deploy.sh --phase 2   # Skip VM creation
./deploy.sh --phase 3   # Skip VMs and k3s, just deploy services
./deploy.sh --phase 4   # Only (re)run the CI/CD + GitOps + Semaphore wiring
```

All playbooks are idempotent — running them again won't break anything.

---

## 11. Known Issues & Workarounds

### DNS resolution on VMs

The school gateway (`10.24.36.1`) does not provide DNS resolution for VMs on the `10.24.36.0/24` network. The Proxmox nodes themselves use `1.1.1.1`. We configured the VMs to use `8.8.8.8` via cloud-init and `systemd-resolved`. If DNS stops working after a reboot, check `/etc/resolv.conf` on the VMs.

### Semaphore service name conflict

Kubernetes auto-injects environment variables for Services in the same namespace. A Service named `semaphore` injects `SEMAPHORE_PORT=tcp://10.43.x.x:3000` into every pod in that namespace. Semaphore reads `SEMAPHORE_PORT` as its listen port and expects a bare number (`3000`) — the `tcp://` value makes it fail to bind and crash-loop, surfacing as `Connection refused` when polling `/api/ping`. The fix is naming the Service `semaphore-ui` instead of `semaphore`, which avoids the collision (the injected var becomes `SEMAPHORE_UI_PORT`, which Semaphore ignores). A readiness probe on `/api/ping` was also added so a broken pod fails at `rollout status` with a clear signal rather than passing silently and breaking a later task.

### Semaphore encryption-key drift

Semaphore encrypts its BoltDB credential store with `SEMAPHORE_ACCESS_KEY_ENCRYPTION`. An early version of the playbook generated this key fresh on every Ansible run, so a re-run produced a key that could not decrypt the existing (persisted) DB → CrashLoopBackOff. The fix: the key is generated once and persisted in the `semaphore-secrets` Kubernetes Secret; subsequent runs read the existing value back instead of regenerating it (same idempotent pattern used for the Drone admin token). Re-running Phase 3 no longer breaks Semaphore.

### Headlamp Helm repo URL

The Headlamp project moved from `https://headlamp-k8s.github.io/headlamp/` to `https://kubernetes-sigs.github.io/headlamp/`. The bootstrap playbook uses the correct URL.

### Host key conflicts on redeploy

When VMs are destroyed and recreated, the SSH host keys change. The `ansible.cfg` has `host_key_checking = False` to avoid failures during automated deployment. For manual SSH, you may need to clear old keys from `~/.ssh/known_hosts`:

```bash
ssh-keygen -f '/root/.ssh/known_hosts' -R '10.24.36.10'
```

---

## 12. Customer Provisioning (GitOps)

Provisioning is fully GitOps-driven and usable by non-ops staff. Nobody runs `kubectl` against the cluster — a form submission becomes a Git commit, and Argo CD does the rest.

### The flow

```
Semaphore template ─► provision-customer.yml ─► commit manifest to Gitea
   (sales/ops UI)        (renders Jinja)          (customer-instances /
                                                    test-customers repo)
                                                          │
                                          Argo CD watches both repos
                                                          ▼
                              reconciles customer-<slug> namespace into k3s
```

1. A staff member opens **Semaphore** (`:30084`), runs **"Nieuwe klant aanmaken"** (sales) or **"Testklant aanmaken"** (ops), and fills in name / email / admin password / optional domain.
2. The shared `provision-customer.yml` playbook renders `ansible/templates/customer-instance.yml.j2` and commits it as `customers/<slug>.yaml` to a Gitea repo — `customer-instances` (sales lane) or `test-customers` (ops lane).
3. **Argo CD** watches both repos (`directory.recurse`) and reconciles the new `customer-<slug>` namespace into the cluster within ~30–60s.
4. The Orange Kuma container boots, self-creates its admin user from the provisioned password, and auto-creates an HTTPS monitor for the supplied domain (if any) — no manual setup wizard. See [Section 13](#13-orange-kuma-image-customizations).

### Two lanes, one playbook

Both Semaphore templates call the same `provision-customer.yml`, parameterized by `target_repo`. This keeps the logic DRY while separating production (sales) customers from throwaway test (ops) customers into different repos and different Argo CD Applications. The `provisioned-by` label (`sales`/`ops`) is stamped onto each namespace so the dashboard and operators can tell the lanes apart.

### What the rendered manifest contains

For each `customer-<slug>` namespace, `customer-instance.yml.j2` produces:

- **Namespace** — labelled `app=orange-kuma`, `customer=<slug>`, `provisioned-by=<lane>`, annotated with `orange-kuma/customer-email`.
- **Secret `kuma-admin`** — holds `UPTIME_KUMA_ADMIN_PASSWORD` for the instance's admin bootstrap.
- **PersistentVolumeClaim `kuma-data`** — 1 Gi, `local-path` storage, mounted at `/app/data`.
- **Deployment `kuma`** — the Orange Kuma image from the Gitea registry, port 3001, with `CUSTOMER_NAME` / `CUSTOMER_EMAIL` / `CUSTOMER_DOMAIN` env and the admin password from the Secret.
- **Service `kuma`** — ClusterIP on 3001 (an Ingress/NodePort can be layered on later).
- **NetworkPolicy `deny-cross-customer`** — ingress isolation as described in [Section 9](#9-network-policies--security).

### Manual / CLI use

The same playbook can be driven directly for testing:

```bash
ansible-playbook playbooks/provision-customer.yml \
  -e customer_name=acme \
  -e customer_email=test@acme.io \
  -e admin_password=Test1234 \
  -e customer_domain=acme.example.com \
  -e target_repo=test-customers
```

`customer_name` is validated against `^[a-z0-9-]{3,32}$` and `customer_domain` (optional) against a hostname regex. The task commits to Gitea idempotently (POST for a new file, PUT with the existing `sha` for an update). To remove a customer, delete its `customers/<slug>.yaml` from the repo (or use `playbooks/remove-customer.yml`); Argo CD's `prune: true` then tears down the namespace.

> **Note:** `provision-customer-management.yml` is a legacy playbook from the pre-GitOps era. Current provisioning flows exclusively through Semaphore → `provision-customer.yml` → Argo CD.

---

## 13. Orange Kuma Image Customizations

The customer-facing container is a lightly customized fork of Uptime Kuma (repo `orange-uptime-kuma`, built and pushed to the Gitea registry by Drone). Two startup behaviours make the GitOps flow fully hands-off — no web setup wizard, no manual monitor entry.

Both run inside `server/server.js` as best-effort, idempotent steps (wrapped in try/catch so a failure never blocks the server from starting):

### Admin bootstrap

On startup, before the HTTP server begins listening, the image reads `UPTIME_KUMA_ADMIN_PASSWORD` (and optional `UPTIME_KUMA_ADMIN_USER`, default `admin`). If no user exists yet in the database, it creates the admin account from those values and flips Kuma's `needSetup` flag off. This is what lets a freshly provisioned instance be usable immediately with the password entered in the Semaphore form — the operator never sees the setup wizard.

### Auto-created HTTPS monitor

After monitors start, the image reads `CUSTOMER_DOMAIN`. If set (and a user exists to own the monitor), it ensures exactly one HTTP monitor for `https://<CUSTOMER_DOMAIN>`: it checks whether a monitor with that URL already exists, and if not, creates one (type `http`, 60s interval) and starts it on the live scheduler. Re-running on every boot is safe — the URL check keeps it idempotent. An empty `CUSTOMER_DOMAIN` (the default) creates no monitor, so the minimal provisioning path still works.

`CUSTOMER_DOMAIN` is threaded all the way through: the Semaphore survey form → `provision-customer.yml` → `customer-instance.yml.j2` env block → the running container.

---

## 14. Management Tool Dashboard

The Management Tool (namespace `orange-kuma`, NodePort `30087`, repo `orange-uptime-kuma-management-tool`) is a Node.js/Express app that originally *provisioned* customers via `kubectl`. It has been **pivoted to a strictly read-only customer health dashboard** — provisioning now belongs to Semaphore, and Git is the source of truth.

### What it shows

One branded Orange Kuma page listing every `customer-*` namespace (selected by the `app=orange-kuma` label), one row per customer, aggregating three sources:

- **Cluster state** (k8s API) — pod phase (Running/Pending/Failed), restart counts, deployment replica counts, namespace age, the `customer` and `provisioned-by` labels, and the contact email annotation.
- **Argo CD state** (Argo CD REST API) — the matching lane Application's sync status (Synced/OutOfSync) and health (Healthy/Progressing/Degraded). Because there are two umbrella Applications (one per lane), each customer maps to its lane's Application.
- **GitOps state** (Gitea API) — the latest commit (author, message, sha, timestamp) on the customer's `customers/<slug>.yaml` file.

A **"Nieuwe klant aanmaken"** button deep-links into the Semaphore sales template URL — the sales rep clicks from the dashboard and lands directly in the form. The page auto-refreshes every 15s. All three integrations are wrapped in try/catch so the dashboard still renders if any backend is briefly unreachable.

### Why read-only

The dashboard never mutates the cluster. Its ServiceAccount ClusterRole is shrunk to `get/list/watch` on `namespaces`, `pods`, `services` (core) and `deployments` (apps) — all write verbs and the old PVC/NetworkPolicy rules are gone. You can verify:

```bash
kubectl auth can-i create namespaces \
  --as=system:serviceaccount:orange-kuma:management-tool
# -> no
```

### Wiring

`k8s/management-tool/deployment.yml` carries the Deployment, Service, ServiceAccount, the read-only ClusterRole/Binding, and a ConfigMap with `GITEA_URL`, `GITEA_ORG`, `ARGOCD_API_URL` (`http://argocd-server.argocd.svc`, plaintext — the server runs insecure), and `SEMAPHORE_NEW_CUSTOMER_URL`. Phase 4 mints a read-only Argo CD API token (account `dashboard`, role `role:readonly`) and stores it in the `management-tool-argocd` Secret, which the pod mounts as `ARGOCD_TOKEN` (optional). The `better-sqlite3` dependency and the old local `customers` table were removed — nothing is tracked locally anymore.

---

## 15. Auto-Update Strategy

A tiered policy balances automation where it's safe against stability where it isn't. Full detail in [`docs/auto-update-strategy.md`](docs/auto-update-strategy.md).

| Tier | Scope | Update mechanism |
|------|-------|------------------|
| **A** | Customer Orange Kuma instances | **Automatic.** Argo CD Image Updater watches the Gitea registry; new image builds are committed back to the GitOps repo and reconciled by Argo CD. |
| **B** | Platform apps deployed from Git | Automatic via Argo CD sync (selfHeal), bounded by what's committed. |
| **C** | Helm-installed platform services | **Pinned.** Gitea, Argo CD, kube-prometheus-stack, Headlamp, Semaphore (and the Image Updater chart) install at explicit versions; bumping requires reading upstream release notes and a destroy-first test run. |
| **D** | k3s / node OS | **Manual.** Cluster and OS upgrades are deliberate, operator-driven actions. |

Tier A in practice: when Drone publishes a new `orange-uptime-kuma` image, the `customer-instances` and `test-customers` Applications (annotated with `argocd-image-updater.argoproj.io/...`, `write-back-method: git`) get every `customers/*.yaml` rewritten with the new image, committed by `argocd-image-updater`, and rolled out to each customer Deployment by Argo CD. The pinned versions (Tier C) are the reason a re-run of the playbooks can't silently pull a breaking upstream chart.

---

## 16. File Structure

```
project-cloud/
├── deploy.sh                              # One-command greenfield deployment (4 phases)
├── README.md                              # Quick-start guide
├── DOCUMENTATION.md                       # This file
├── CHANGELOG.md                           # Branch-level change log
├── docs/
│   ├── auto-update-strategy.md            # Tiered auto-update policy (A–D)
│   └── architecture.md                    # Infrastructure + flow diagrams
├── ansible/
│   ├── ansible.cfg                        # Ansible configuration
│   ├── group_vars/
│   │   └── all.yml                        # Gedeelde vars: poorten, Gitea-credentials
│   ├── inventories/
│   │   ├── hanze/
│   │   │   ├── inventory.yml              # Hanze cluster (10.24.36.x)
│   │   │   └── group_vars/all.yml         # Hanze-specifieke vars: IPs, semaphore branch
│   │   └── test/
│   │       ├── inventory.yml              # Test cluster (10.24.35.x)
│   │       └── group_vars/all.yml         # Test-specifieke vars: IPs, semaphore branch
│   ├── playbooks/
│   │   ├── create-vms.yml                 # Phase 1: Create VMs on Proxmox
│   │   ├── destroy-vms.yml                # Destroy all VMs (for redeploy)
│   │   ├── install-k3s.yml                # Phase 2: Install k3s cluster
│   │   ├── bootstrap-platform.yml         # Phase 3: Deploy platform services
│   │   ├── setup-cicd-pipeline.yml        # Phase 4: CI/CD + GitOps + Semaphore + MT
│   │   ├── provision-customer.yml         # Shared backend for both Semaphore templates
│   │   ├── provision-customer-management.yml  # Legacy (pre-GitOps), unused
│   │   └── remove-customer.yml            # Remove a customer instance
│   └── templates/
│       └── customer-instance.yml.j2       # Rendered per-customer GitOps manifest
└── k8s/
    └── management-tool/
        ├── deployment.yml.j2              # MT dashboard: Deployment/Service/RBAC/ConfigMap
        └── PIVOT-NOTES.md                 # Rationale for the read-only pivot
```
