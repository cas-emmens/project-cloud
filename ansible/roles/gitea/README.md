# gitea

Installeert Gitea, een zelfgehoste Git-server met ingebouwde container registry. Gitea dient als centrale opslag voor broncode én als Docker-registry voor de gebouwde container-images.

**Gebruikt door:** `bootstrap-platform.yml`

## Wat doet deze rol?

1. Voegt de Gitea Helm-repo toe.
2. Installeert Gitea via Helm met:
   - SQLite als database (geen externe PostgreSQL nodig op deze schaal).
   - NodePort-services voor HTTP (Git/registry) en SSH (Git clone).
   - Persistente opslag via Longhorn.
   - Admin-gebruiker aangemaakt via Helm-values.
   - `ALLOWED_HOST_LIST=*` zodat Drone-webhooks vanuit het cluster werken.
   - `ROOT_URL` ingesteld op het externe server-IP zodat clone-URLs en OAuth-redirects kloppen.
3. Wacht tot de Gitea-deployment volledig uitgerold is.

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `gitea_chart_version` | `"10.4.1"` | Helm-chartversie |
| `gitea_namespace` | `"gitea"` | Kubernetes namespace |
| `gitea_persistence_size` | `"5Gi"` | Opslag voor Git-repositories en registry |
| `gitea_install_timeout` | `"10m"` | Timeout voor Helm install |
| `gitea_http_port` | — | NodePort voor HTTP/registry (uit group_vars, bv. `30080`) |
| `gitea_ssh_port` | — | NodePort voor SSH (uit group_vars, bv. `30022`) |
| `gitea_admin_user` | — | Gebruikersnaam van de admin (uit group_vars) |
| `gitea_admin_password` | — | Wachtwoord van de admin (uit group_vars) |
| `gitea_org` | — | Naam van de organisatie in Gitea (uit group_vars) |

## Afhankelijkheden

- `longhorn` is geïnstalleerd (voor PVC).
- `namespaces` heeft de `gitea`-namespace aangemaakt.

## Opmerkingen

- **PostgreSQL en Redis zijn uitgeschakeld.** De Bitnami subchart-images (postgresql-ha, redis-cluster) zijn niet meer beschikbaar op Docker Hub. SQLite is volledig functioneel voor deze schaalgrootte.
- Gitea fungeert ook als **container registry** op `<server-ip>:<http-port>`. Drone pusht images hierheen, k3s haalt ze hiervan. De `containerd-registry`-rol (Phase 4) configureert alle nodes om deze registry te vertrouwen.
- De OAuth-applicatie voor Drone wordt **niet** hier aangemaakt — dat doet de `drone`-rol zelf (zie Optie A in de ontwerpbeslissingen).
