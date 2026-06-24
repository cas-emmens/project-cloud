# node-prepare

Bereidt elke VM voor zodat k3s en Longhorn correct kunnen draaien. Wordt uitgevoerd op **alle** k3s-nodes (server + agents) vóór de k3s-installatie.

**Gebruikt door:** `install-k3s.yml` (play 1: `hosts: k3s_cluster`)

## Wat doet deze rol?

1. **DNS-check** — wacht tot `deb.debian.org` resolvet. Voorkomt dat apt mislukt na een verse cloud-init boot.
2. **apt update + upgrade** — zorgt voor recente packages.
3. **Packages installeren:**
   - `curl` — nodig voor k3s installatiescript.
   - `open-iscsi` / `iscsid` — vereist door Longhorn voor block-storage.
   - `qemu-guest-agent` — Proxmox kan zo de VM-status zien en snapshots consistent maken.
4. **Kernelmodules laden en persisteren:**
   - `br_netfilter` — bridge-netwerkfiltering voor Kubernetes networking.
   - `overlay` — container filesysteem-laag.
   - `ip_tables` — firewall/NAT voor services.
5. **sysctl-parameters:** schakelt IPv4-forwarding en bridge-netfilter in — vereist door de CNI (Flannel in k3s).

## Variabelen

Geen rolspecifieke variabelen. Alles is hard-coded op basis van Kubernetes-vereisten.

## Afhankelijkheden

- De VM is aangemaakt en bereikbaar via SSH (na `vm-create`).
- DNS werkt (1.1.1.1 is ingesteld via cloud-init).

## Opmerkingen

- De DNS-check heeft 12 pogingen met 10 seconden tussenpauze (2 minuten totaal). Dit is nodig omdat cloud-init na een eerste boot soms wat tijd nodig heeft om de netwerkconfiguratie door te voeren.
- **Longhorn vereist `open-iscsi`**. Als `iscsid` niet draait, kan Longhorn geen volumes aanmaken en gaat de pod in `CrashLoopBackOff`.
