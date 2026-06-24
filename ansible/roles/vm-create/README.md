# vm-create

Maakt een Proxmox VM aan op basis van een Debian 12 cloud-image. Wordt uitgevoerd op de Proxmox-host zelf (via SSH). Per VM in de inventory wordt deze rol één keer aangeroepen met de juiste `vm_id`, `vm_name` en `vm_ip`.

**Gebruikt door:** `create-vms.yml`

## Wat doet deze rol?

1. Controleert of het Debian 12 cloud-image (`debian-12-generic-amd64.qcow2`) al aanwezig is; downloadt het anders.
2. Controleert of de VM (`vm_id`) al bestaat — sla over als dat zo is (idempotent).
3. Maakt de VM aan via `qm create` met VirtIO-schijf, CPU host-type, en QEMU guest-agent.
4. Importeert de qcow2-image als raw schijf en koppelt hem als `scsi0`.
5. Vergroot de schijf naar `vm_disk_size` (standaard 100 GB).
6. Configureert cloud-init: IP, gateway, DNS, SSH-publieke sleutel, gebruiker `debian`.
7. Start de VM en wacht tot poort 22 bereikbaar is.

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `vm_memory` | `16384` | RAM in MB |
| `vm_cores` | `2` | Aantal vCPU-cores |
| `vm_disk_size` | `"100G"` | Schijfgrootte na resize |
| `vm_storage` | `"local-lvm"` | Proxmox storage-pool |
| `vm_id` | — | Proxmox VM-ID (uit inventory) |
| `vm_name` | — | Hostnaam van de VM |
| `vm_ip` | — | Statisch IP-adres |
| `base_image` | — | Lokaal pad naar qcow2-image op Proxmox |
| `bridge` | — | Netwerk-bridge (bv. `vmbr0`) |
| `netmask` | — | Subnetmasker (bv. `24`) |
| `gateway` | — | Standaardgateway |
| `nameserver` | — | DNS-server (gebruik `1.1.1.1`) |
| `ssh_public_key` | — | SSH-publieke sleutel voor de `debian`-gebruiker |

## Afhankelijkheden

- Proxmox moet bereikbaar zijn via SSH.
- De Ansible-controllernode moet de SSH-publieke sleutel kennen.

## Opmerkingen

- **100 GB schijf is vereist** voor Longhorn. Met minder schijfruimte weigert Longhorn te starten.
- `--cpu cputype=host` geeft de VM volledige toegang tot de CPU-instructieset van de host — sneller en vereist voor sommige k3s-features.
- `iothread=1,discard=on` op de schijf zorgt voor betere I/O-prestaties en TRIM-ondersteuning.
