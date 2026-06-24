# Architectuur — Orange Kuma Platform

## Infrastructuur

```
┌─────────────────────────────────────────────────────────────────────┐
│  Proxmox Cluster                                                    │
│                                                                     │
│  ┌───────────────────┐  ┌───────────────────┐  ┌─────────────────┐ │
│  │  CE01 10.24.36.2  │  │  CE02 10.24.36.3  │  │ CE03 10.24.36.4 │ │
│  │                   │  │                   │  │                 │ │
│  │  ┌─────────────┐  │  │  ┌─────────────┐  │  │  ┌───────────┐ │ │
│  │  │  k3s-server │  │  │  │ k3s-agent-1 │  │  │  │k3s-agent-2│ │ │
│  │  │ 10.24.36.10 │  │  │  │ 10.24.36.11 │  │  │  │10.24.36.12│ │ │
│  │  └─────────────┘  │  │  └─────────────┘  │  │  └───────────┘ │ │
│  └───────────────────┘  └───────────────────┘  └─────────────────┘ │
│                                                                     │
│  Storage: local-path (per node, geen shared storage)               │
└─────────────────────────────────────────────────────────────────────┘
```

> Voor de test-omgeving: nodes pve2/pve3/pve4 op subnet 10.24.35.x,
> k3s VMs op 10.24.35.10/11/12. Zelfde structuur, andere IPs.

---

## Services op k3s

Alle NodePorts zijn bereikbaar via het IP van de k3s-server.

```
k3s-server (10.24.36.10)
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  ┌──────────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │      Gitea       │  │   Drone CI   │  │       Argo CD        │  │
│  │  :30080 (http)   │  │    :80       │  │       :30082         │  │
│  │  :30022 (ssh)    │  │              │  │                      │  │
│  │  + container     │  │              │  │  + Image Updater     │  │
│  │    registry      │  │              │  │                      │  │
│  └──────────────────┘  └──────────────┘  └──────────────────────┘  │
│                                                                     │
│  ┌──────────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │    Semaphore     │  │  Mgmt Tool   │  │      Headlamp        │  │
│  │     :30084       │  │   :30087     │  │       :30086         │  │
│  └──────────────────┘  └──────────────┘  └──────────────────────┘  │
│                                                                     │
│  ┌──────────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   Prometheus     │  │   Grafana    │  │    Alertmanager      │  │
│  │     :30090       │  │   :30083     │  │       :30085         │  │
│  └──────────────────┘  └──────────────┘  └──────────────────────┘  │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  ingress-nginx  —  *.10.24.36.10.nip.io  →  :443 / :80     │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────────┐   │
│  │  customer-abc   │  │  customer-xyz   │  │   customer-...   │   │
│  │   Uptime Kuma   │  │   Uptime Kuma   │  │   Uptime Kuma    │   │
│  └─────────────────┘  └─────────────────┘  └──────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Flow 1 — Klant aanmaken (GitOps)

Een nieuwe klant wordt aangemaakt via de Management Tool en uitgerold via Argo CD.

```
Gebruiker (browser)
   │
   ▼
Management Tool  :30087
   │  POST /api/trigger (naam, email, wachtwoord)
   ▼
Semaphore  :30084
   │  voert Ansible playbook uit: provision-customer.yml
   ▼
Ansible
   │  rendert customer-instance.yml.j2 naar manifest
   │  PUT/POST naar Gitea API  :30080
   ▼
Gitea  :30080
   │  repo: orange/customer-instances  (of test-customers)
   │  nieuw bestand: customers/<naam>.yaml
   ▼
Argo CD  :30082
   │  pollt Gitea elke ~3 minuten
   │  detecteert nieuw manifest
   │  kubectl apply  →  CreateNamespace=true
   ▼
Namespace: customer-<naam>
   │  Deployment: Uptime Kuma
   │  Service + Ingress
   ▼
https://<naam>.10.24.36.10.nip.io
```

---

## Flow 2 — Image bouwen en uitrollen (CI/CD)

Codewijzigingen in GitHub worden automatisch gebouwd en uitgerold naar alle klanten.

```
GitHub
   │  orange-uptime-kuma
   │  orange-uptime-kuma-management-tool
   │
   │  (Gitea pull mirror — synct periodiek)
   ▼
Gitea  :30080
   │  orange/orange-uptime-kuma
   │  orange/orange-uptime-kuma-management-tool
   │
   │  webhook bij nieuwe commit
   ▼
Drone CI  :80
   │  voert .drone.yml pipeline uit
   │  bouwt Docker image
   │  pusht naar Gitea container registry
   ▼
Gitea container registry  :30080
   │  orange-uptime-kuma:<sha>
   │  orange-uptime-kuma-management-tool:<sha>
   │
   │  (Argo CD Image Updater pollt registry)
   ▼
Argo CD Image Updater
   │  detecteert nieuw image-tag
   │  commit naar customer-instances / test-customers:
   │    .argocd-source-<app>.yaml  (image: ...:<nieuw-sha>)
   ▼
Argo CD  :30082
   │  detecteert nieuwe commit
   │  sync → rolling update
   ▼
Alle customer pods  →  draaien op nieuwe image
```

> De management tool zelf wordt niet beheerd door de Image Updater.
> Na een nieuwe build is een herrun van Phase 4 (`./deploy.sh --phase 4`)
> nodig om het nieuwe image te activeren.

---

## Deployment volgorde

```
Phase 1  create-vms.yml          →  VMs aanmaken op Proxmox
Phase 2  install-k3s.yml         →  k3s cluster installeren
Phase 3  bootstrap-platform.yml  →  Helm charts: Gitea, Drone, Argo CD,
                                     Semaphore, Prometheus stack, Headlamp
Phase 4  setup-cicd-pipeline.yml →  Gitea inrichten, Drone koppelen,
                                     repos importeren, builds triggeren,
                                     Management Tool deployen
```
