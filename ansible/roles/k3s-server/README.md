# k3s-server

Installeert k3s als Kubernetes-servernode (control plane + etcd). Haalt daarna het node-token en de kubeconfig op zodat agents kunnen joinen en je lokaal met `kubectl` kunt werken.

**Gebruikt door:** `install-k3s.yml` (play 2: `hosts: k3s_server`)

## Wat doet deze rol?

1. Controleert of `get.k3s.io` bereikbaar is (max. 10 minuten wachten).
2. Controleert of k3s al geïnstalleerd is — sla installatie over als dat zo is.
3. Installeert k3s server met:
   - Specifieke versie (`k3s_version`) zodat re-runs niet upgraden.
   - Traefik uitgeschakeld (`--disable=traefik`) — wij gebruiken ingress-nginx.
   - TLS-SAN op `k3s_server_ip` zodat de kubeconfig extern werkt.
   - `--write-kubeconfig-mode=644` zodat Ansible als `debian`-gebruiker `kubectl` kan aanroepen.
4. Wacht tot de node `Ready` is.
5. Leest het node-token uit `/var/lib/rancher/k3s/server/node-token` en slaat het op als een Ansible-fact (`k3s_node_token`) die de agent-rol gebruikt.
6. Haalt de kubeconfig op, vervangt `127.0.0.1` door het echte server-IP, en kopieert hem lokaal naar `k3s_kubeconfig_local_path`.

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `k3s_kubeconfig_local_path` | `"/tmp/kubeconfig-orange-kuma.yaml"` | Lokaal pad voor de kubeconfig |
| `k3s_version` | — | k3s-versie (uit group_vars, bv. `v1.31.0+k3s1`) |
| `k3s_server_ip` | — | Extern IP van de server (uit inventory) |
| `k3s_cluster_cidr` | — | Pod-netwerk CIDR (bv. `10.42.0.0/16`) |
| `k3s_service_cidr` | — | Service-netwerk CIDR (bv. `10.43.0.0/16`) |

## Afhankelijkheden

- `node-prepare` is uitgevoerd op deze node.
- Internetverbinding naar `get.k3s.io`.

## Opmerkingen

- **Traefik is uitgeschakeld** (`--disable=traefik`). k3s installeert Traefik standaard als ingress-controller. Wij gebruiken ingress-nginx (geïnstalleerd in Phase 3) voor consistentie met de rest van het ecosysteem.
- De `failed_when`-conditie negeert de fout `D-Bus connection terminated` — dit is een bekend k3s-installatielogbericht dat geen echte fout is.
- Het node-token wordt als Ansible-fact doorgegeven aan de `k3s-agent`-rol via `hostvars`.
