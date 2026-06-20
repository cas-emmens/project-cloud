# drone

Installeert Drone CI, een container-gebaseerd CI/CD-systeem dat automatisch bouwt wanneer er code naar Gitea wordt gepusht. Drone bestaat uit een server (orkestratie) en een runner (uitvoering van builds in Docker-containers).

**Gebruikt door:** `bootstrap-platform.yml`

## Wat doet deze rol?

1. **OAuth-app aanmaken in Gitea** — Drone logt gebruikers in via Gitea OAuth. De client_id en client_secret worden opgeslagen zodat ze bij een re-run hergebruikt worden (niet overschreven).
2. **Admin-token beheren** — leest een bestaand `DRONE_ADMIN_TOKEN` uit het k8s-secret, of genereert een nieuw token als het secret er nog niet is. Dit token gebruik je om via de Drone API repositories te activeren.
3. **Kubernetes Secret aanmaken** (`drone-secrets`) met alle credentials.
4. **Drone Server deployen** via `kubectl apply`:
   - Deployment met PVC voor de SQLite-database.
   - LoadBalancer Service op poort 80 (Drone is bereikbaar op `http://<server-ip>`).
5. **Drone Runner deployen** met Docker-in-Docker (DinD) sidecar zodat builds Docker-commando's kunnen uitvoeren.

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `drone_namespace` | `"drone"` | Kubernetes namespace |
| `drone_server_image` | `"drone/drone:2.20.0"` | Drone Server image |
| `drone_runner_image` | `"drone/drone-runner-docker:1"` | Drone Runner image |
| `drone_dind_image` | `"docker:26-dind"` | Docker-in-Docker sidecar image |
| `drone_persistence_size` | `"2Gi"` | Opslag voor SQLite-database |
| `drone_port` | — | NodePort/LoadBalancer poort (uit group_vars, bv. `80`) |

## Afhankelijkheden

- `gitea` draait en is bereikbaar via HTTP.
- `namespaces` heeft de `drone`-namespace aangemaakt.

## Opmerkingen

- **OAuth-secret wordt niet overschreven bij re-run.** Als de OAuth-applicatie al bestaat in Gitea, wordt de bestaande `client_secret` hergebruikt. Een nieuwe secret aanmaken zou de verbinding verbreken.
- **Drone gebruikt een LoadBalancer Service op poort 80.** k3s (via ServiceLB/klipper) bindt dan host-poort 80 aan Drone. Dit betekent dat ingress-nginx poort 80 niet meer kan gebruiken — die gebruikt alleen HTTPS (443).
- **DinD (Docker-in-Docker)** draait als privileged sidecar. Dit is nodig omdat Drone builds Docker-images bouwen, en daarvoor is toegang tot de Docker-daemon vereist.
- **Ontwerpkeuze (Optie A):** de OAuth-app en alle Drone-credentials worden in déze rol aangemaakt, niet in de Gitea-rol. De afnemer (Drone) is verantwoordelijk voor zijn eigen configuratie in de aanbieder (Gitea).
