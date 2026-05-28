# Orange Kuma Platform - Automated Deployment

Fully automated greenfield deployment of the Orange Kuma platform on a 3-node Proxmox cluster running k3s (Kubernetes).

## Architecture

```
Proxmox Cluster (3 nodes)
├── CE01 (10.24.36.2) → k3s-server VM (10.24.36.10) - Control plane
├── CE02 (10.24.36.3) → k3s-agent-1 VM (10.24.36.11) - Worker
└── CE3  (10.24.36.4) → k3s-agent-2 VM (10.24.36.12) - Worker

k3s Cluster Services:
├── Longhorn          - Distributed persistent storage
├── Gitea             - Git repository manager        → :30080
├── Drone CI          - Continuous integration         → :30081
├── Argo CD           - Continuous deployment (GitOps) → :30082
├── Grafana           - Monitoring dashboards          → :30083
├── Semaphore         - Ansible UI for provisioning    → :30084
├── Alertmanager      - Alert routing                  → :30085
├── Headlamp          - Kubernetes web UI              → :30086
├── Prometheus        - Metrics collection             → :30090
└── Orange Kuma       - Customer instances (per namespace)
```

## Prerequisites

- Ansible installed on your local machine
- SSH access to all 3 Proxmox nodes
- `debian-12-generic-amd64.qcow2` image on all Proxmox nodes at `/var/lib/vz/template/iso/`

## Quick Start

```bash
# Set required environment variables
export PROXMOX_PASSWORD="your-proxmox-root-password"
export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"

# Full greenfield deploy
./deploy.sh

# Or destroy and redeploy
./deploy.sh --destroy-first

# Or resume from a specific phase
./deploy.sh --phase 2   # Skip VM creation, start at k3s install
./deploy.sh --phase 3   # Skip VMs + k3s, just bootstrap services
```

## Playbooks

| Playbook | Description |
|---|---|
| `site.yml` | Full deployment (all phases) |
| `playbooks/create-vms.yml` | Create k3s VMs on Proxmox |
| `playbooks/destroy-vms.yml` | Destroy all k3s VMs |
| `playbooks/install-k3s.yml` | Install k3s cluster |
| `playbooks/bootstrap-platform.yml` | Install all platform services |
| `playbooks/provision-customer-management.yml` | Deploy het Orange Kuma Management Portaal |
| `playbooks/remove-customer.yml` | Remove a customer instance |

## Default Credentials

| Service | Username | Password |
|---|---|---|
| Gitea | gitea_admin | OrangeKuma2025! |
| Grafana | admin | OrangeKuma2025! |
| Semaphore | admin | OrangeKuma2025! |
| Argo CD | admin | (auto-generated, shown at end of deploy) |
| Headlamp | (token auth) | (saved to /tmp/headlamp-token.txt) |

## VM Specs

Each k3s VM: 2 vCPU, 16 GB RAM, 25 GB disk, Debian 12

## Security - Namespace Isolation

Each customer gets their own Kubernetes namespace with NetworkPolicies that enforce:

- **Default deny ingress** — no pod can receive traffic unless explicitly allowed
- **Default deny egress** — pods can only resolve DNS by default
- **Orange Kuma allowed outbound** — HTTP/HTTPS only, blocked from reaching other namespaces (pod/service CIDRs excluded)
- **Prometheus scraping allowed** — monitoring namespace can reach port 3001 for metrics
- **Cross-customer isolation** — customers cannot reach each other's pods or services

In production, this would be combined with dedicated node pools (taints/tolerations) for full workload separation. At this scale (6 vCPU total), namespace isolation is the practical choice.

## Network

All VMs are bridged on `vmbr0` (10.24.36.0/24), gateway 10.24.36.1.
Services are exposed via NodePorts on the k3s-server IP (10.24.36.10).
