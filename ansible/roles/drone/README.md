# drone

Installeert Drone CI, een container-gebaseerd CI/CD-systeem dat automatisch bouwt wanneer er code naar Gitea wordt gepusht. Drone bestaat uit een server (orkestratie) en een runner (uitvoering van builds in Docker-containers).

**Gebruikt door:** `bootstrap-platform.yml` (Phase 3)

## Wat doet deze rol?

1. **OAuth-app aanmaken in Gitea** — Drone logt gebruikers in via Gitea OAuth. De client_id en client_secret worden opgeslagen zodat ze bij een re-run hergebruikt worden (niet overschreven).
2. **Admin-token beheren** — leest een bestaand `DRONE_ADMIN_TOKEN` uit het k8s-secret, of genereert een nieuw token als het secret er nog niet is. Dit token gebruik je om via de Drone API repositories te activeren.
3. **Kubernetes Secret aanmaken** (`drone-secrets`) met alle credentials.
4. **Drone Server deployen** via `kubectl apply`:
   - Deployment met PVC voor de SQLite-database.
   - LoadBalancer Service op poort 80 (Drone is bereikbaar op `http://<server-ip>`).
5. **Drone Runner deployen** met Docker-in-Docker (DinD) sidecar zodat builds Docker-commando's kunnen uitvoeren.

## Componenten

Drone bestaat uit drie pods die samenwerken in de `drone` namespace:

```
┌─────────────────────────────────────────────────────┐
│  namespace: drone                                   │
│                                                     │
│  ┌──────────────┐    RPC     ┌───────────────────┐  │
│  │ drone-server │ ◄────────► │drone-runner-docker│  │
│  │  (SQLite DB) │            │                   │  │
│  │  :80         │            │  ┌─────────────┐  │  │
│  └──────────────┘            │  │ DinD sidecar│  │  │
│                              │  │ docker:26   │  │  │
│                              │  │ tcp://2375  │  │  │
│                              │  └─────────────┘  │  │
│                              └───────────────────┘  │
└─────────────────────────────────────────────────────┘
```

- **Drone Server** — orkestratie, OAuth login, REST API, bouwhistorie in SQLite (`/data/database.sqlite` op een Longhorn PVC)
- **Drone Runner** — voert `.drone.yml` pipelines uit, geeft Docker-commando's door aan DinD
- **DinD (Docker-in-Docker)** — privileged sidecar, biedt een Docker-daemon op `tcp://localhost:2375`; nodig omdat builds Docker images bouwen en pushen naar de Gitea registry

## Authenticatie met Gitea

### OAuth — gebruikerslogin

De rol maakt een OAuth-app aan in Gitea via de API:

```
POST /api/v1/user/applications/oauth2
  name:         "drone"
  redirect_uri: http://<k3s_server_ip>/login
```

De `client_id` en `client_secret` worden als omgevingsvariabelen meegegeven aan de Drone Server pod via het Kubernetes Secret `drone-secrets`:

```
DRONE_GITEA_SERVER        → http://<k3s_server_ip>:30080
DRONE_GITEA_CLIENT_ID     → <client_id>
DRONE_GITEA_CLIENT_SECRET → <client_secret>
DRONE_SERVER_HOST         → <k3s_server_ip>
DRONE_SERVER_PROTO        → http
```

Wanneer een gebruiker inlogt op Drone, stuurt Drone hem door naar Gitea voor OAuth-autorisatie. Na akkoord krijgt Drone een OAuth-token terug waarmee hij namens die gebruiker Gitea-repos kan benaderen.

### Kubernetes Secret: `drone-secrets`

| Key | Inhoud |
|---|---|
| `DRONE_GITEA_CLIENT_ID` | OAuth client ID |
| `DRONE_GITEA_CLIENT_SECRET` | OAuth client secret |
| `DRONE_RPC_SECRET` | Gedeeld geheim tussen server en runner |
| `DRONE_ADMIN_TOKEN` | API-token voor Ansible (repo activeren, secrets instellen) |

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `drone_namespace` | `"drone"` | Kubernetes namespace |
| `drone_server_image` | `"drone/drone:2.20.0"` | Drone Server image (gepind) |
| `drone_runner_image` | `"drone/drone-runner-docker:1"` | Drone Runner image (major pin) |
| `drone_dind_image` | `"docker:26-dind"` | Docker-in-Docker sidecar image (major pin) |
| `drone_persistence_size` | `"2Gi"` | Opslag voor SQLite-database |
| `drone_port` | — | LoadBalancer poort (uit group_vars, `80`) |

### Waarom major pins op Runner en DinD?

- `drone-runner-docker:1` — een specifiekere pin botst met de Drone server 2.x API; de major pin biedt compatibiliteit.
- `docker:26-dind` — `plugins/docker` in de pipelines vereist Docker API 1.44; `docker:24-dind` ondersteunt alleen API 1.43. Een floating tag zou dit stil breken bij een herdeployment.

## Netwerk — LoadBalancer op poort 80

Drone gebruikt een **LoadBalancer Service** op poort 80, niet NodePort. k3s bindt via ServiceLB host-poort 80 direct aan Drone. Gevolg: ingress-nginx kan poort 80 niet meer gebruiken en luistert alleen op 443.

De reden voor poort 80: Drone 2.x valideert `DRONE_SERVER_HOST` strict — een poort in die variabele (bijv. `10.24.36.10:30081`) werd in een latere 2.x release geweigerd. De oplossing was overstappen op een LoadBalancer op poort 80 zodat het host-adres zonder poortnummer werkt.

## Afhankelijkheden

- `gitea` draait en is bereikbaar via HTTP.
- `namespaces` heeft de `drone`-namespace aangemaakt.

## Opmerkingen

- **OAuth-secret wordt niet overschreven bij re-run.** Als de OAuth-applicatie al bestaat in Gitea, wordt de bestaande `client_secret` hergebruikt. Een nieuwe secret aanmaken zou de verbinding verbreken.
- **DinD draait privileged.** Dit is onvermijdelijk: builds bouwen Docker images, en daarvoor is toegang tot een Docker-daemon nodig.
- **Ontwerpkeuze (Optie A):** de OAuth-app en alle Drone-credentials worden in déze rol aangemaakt, niet in de Gitea-rol. De afnemer (Drone) is verantwoordelijk voor zijn eigen configuratie in de aanbieder (Gitea).
