# Orange Kuma Platform - Automated Deployment

Fully automated greenfield deployment of the Orange Kuma platform on a 3-node Proxmox cluster running k3s (Kubernetes).

## Architecture

```
Proxmox Cluster (3 nodes)
├── CE01 (10.24.36.2) → k3s-server VM (10.24.36.10) - Control plane
├── CE02 (10.24.36.3) → k3s-agent-1 VM (10.24.36.11) - Worker
└── CE3  (10.24.36.4) → k3s-agent-2 VM (10.24.36.12) - Worker

k3s Cluster Services:
├── Gitea             - Git repos + container registry → :30080 (SSH :30022)
├── Drone CI          - Continuous integration         → :80 (LoadBalancer)
├── Argo CD           - Continuous deployment (GitOps) → :30082
├── Argo CD Image Updater - Auto-rolls new image tags  (in argocd ns)
├── Grafana           - Monitoring dashboards          → :30083
├── Semaphore         - Ansible UI for provisioning    → :30084
├── Alertmanager      - Alert routing                  → :30085
├── Headlamp          - Kubernetes web UI              → :30086
├── Management Tool   - Read-only customer dashboard    → :30087
├── Prometheus        - Metrics collection             → :30090
└── Orange Kuma       - Customer instances (per customer-<slug> namespace)
```

## How customer provisioning works (GitOps)

Provisioning is fully GitOps-driven and usable by non-ops staff:

```
Semaphore template ─► provision-customer.yml ─► commit manifest to Gitea
   (sales/ops UI)        (renders Jinja)          (customer-instances /
                                                    test-customers repo)
                                                          │
                                          Argo CD watches both repos
                                                          ▼
                              reconciles customer-<slug> namespace into k3s
```

1. A sales rep opens **Semaphore** (`:30084`), runs **"Nieuwe klant aanmaken"**,
   and fills in name / email / admin password / optional domain.
2. The shared `provision-customer.yml` playbook renders a manifest from
   `ansible/templates/customer-instance.yml.j2` and commits it to a Gitea
   repo — `customer-instances` (sales) or `test-customers` (ops).
3. **Argo CD** watches both repos and reconciles the new
   `customer-<slug>` namespace (Deployment, Service, PVC, Secret,
   NetworkPolicy) into the cluster within ~60s.
4. The Orange Kuma container boots, **self-creates its admin user** from
   the provisioned password and **auto-creates an HTTPS monitor** for the
   supplied domain — no manual setup wizard needed.

The **Management Tool** (`:30087`) is a read-only dashboard over the
result, and **Argo CD Image Updater** keeps every customer on the latest
image automatically. See [`DOCUMENTATION.md`](DOCUMENTATION.md) and
[`docs/auto-update-strategy.md`](docs/auto-update-strategy.md) for detail.

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

# Or resume from a specific phase (1=VMs, 2=k3s, 3=platform, 4=CI/CD)
./deploy.sh --phase 2   # Skip VM creation, start at k3s install
./deploy.sh --phase 3   # Skip VMs + k3s, just bootstrap platform services
./deploy.sh --phase 4   # Only (re)run the CI/CD + GitOps + Semaphore wiring
```

## Playbooks

| Playbook | Phase | Description |
|---|---|---|
| `site.yml` | all | Full deployment (all phases) |
| `playbooks/create-vms.yml` | 1 | Create k3s VMs on Proxmox |
| `playbooks/destroy-vms.yml` | — | Destroy all k3s VMs (for `--destroy-first`) |
| `playbooks/install-k3s.yml` | 2 | Install k3s cluster |
| `playbooks/bootstrap-platform.yml` | 3 | Install platform services (Gitea, Drone, Argo CD, Image Updater, Prometheus/Grafana, Semaphore + templates, Headlamp) |
| `playbooks/setup-cicd-pipeline.yml` | 4 | Wire CI/CD + GitOps: Gitea org/repos, Drone pipelines, Argo CD AppProject + Applications, Image Updater config, Management Tool |
| `playbooks/provision-customer.yml` | — | Shared backend for both Semaphore templates; commits a customer manifest to a Gitea repo (GitOps). Run by Semaphore, or manually with `-e`. |
| `playbooks/remove-customer.yml` | — | Remove a customer instance |

> **Note:** `provision-customer-management.yml` is a legacy playbook from
> the pre-GitOps era. Current provisioning flows through Semaphore →
> `provision-customer.yml` → Argo CD.

## Default Credentials

| Service | Username | Password |
|---|---|---|
| Gitea | gitea_admin | OrangeKuma2025! |
| Grafana | admin | OrangeKuma2025! |
| Semaphore | admin | OrangeKuma2025! |
| Argo CD | admin | (auto-generated, shown at end of deploy) |
| Headlamp | (token auth) | (saved to /tmp/headlamp-token.txt) |
| Management Tool | — | (no auth; read-only dashboard on :30087) |

Per-customer Orange Kuma admin credentials are set at provision time
(`admin` / the password entered in the Semaphore form) and bootstrapped
into the instance automatically on first boot.

## VM Specs

Each k3s VM: 2 vCPU, 16 GB RAM, 25 GB disk, Debian 12

## Security - Namespace Isolation

Each customer gets their own Kubernetes namespace (`customer-<slug>`,
labelled `app=orange-kuma`, `customer=<slug>`, `provisioned-by=<lane>`).
The rendered manifest ships a `deny-cross-customer` NetworkPolicy that:

- **Blocks cross-customer ingress** — a pod in one `customer-*` namespace
  cannot reach another customer's pods (namespaces carrying a *different*
  `customer` label are denied).
- **Allows platform/monitoring ingress** — namespaces without a
  `customer` label (e.g. `monitoring`, ingress controllers) and the
  customer's own namespace can still reach the instance, so Prometheus
  scraping and external access keep working.

The Management Tool's RBAC is **read-only** (get/list/watch on
namespaces, pods, services, deployments) — it can render status but
never mutate the cluster. Provisioning writes happen only through the
GitOps path (Semaphore → Gitea → Argo CD).

In production, this would be combined with dedicated node pools
(taints/tolerations) and default-deny egress for full workload
separation. At this scale (6 vCPU total), namespace isolation plus the
read-only control plane is the practical choice.

## Network

All VMs are bridged on `vmbr0` (10.24.36.0/24), gateway 10.24.36.1.
Services are exposed via NodePorts on the k3s-server IP (10.24.36.10).
