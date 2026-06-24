# k3s-agent

Voegt een node toe aan het k3s-cluster als worker (agent). Wordt uitgevoerd op alle nodes in de `k3s_agents`-groep.

**Gebruikt door:** `install-k3s.yml` (play 3: `hosts: k3s_agents`)

## Wat doet deze rol?

1. Leest het node-token van de server via `hostvars[groups['k3s_server'][0]].k3s_node_token` (een fact die de `k3s-server`-rol heeft gezet).
2. Controleert of `get.k3s.io` bereikbaar is.
3. Controleert of k3s al geïnstalleerd is — sla over als dat zo is.
4. Installeert k3s als agent: verbindt met de server via `K3S_URL` en authenticeer met het token.
5. Wacht tot de agent-node als `Ready` zichtbaar is in `kubectl get nodes`.

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `k3s_version` | — | Moet overeenkomen met de serverversie |
| `k3s_server_ip` | — | IP van de k3s-servernode |

## Afhankelijkheden

- `node-prepare` is uitgevoerd op deze node.
- `k3s-server` is volledig klaar en heeft het fact `k3s_node_token` gezet.

## Opmerkingen

- Het node-token wordt **niet** opgeslagen in een variabele of bestand — het wordt direct uit `hostvars` van de servernode gelezen. Dit voorkomt dat het token in logs of variabele-dumps verschijnt.
- Alle drie nodes moeten dezelfde k3s-versie gebruiken; een versieverschil tussen server en agent wordt door k3s afgewezen.
