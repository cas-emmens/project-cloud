# drone-setup

Koppelt Drone CI aan de Gitea-repositories: injecteert het OAuth-token, synchroniseert repos in de Drone-database, activeert repositories, stelt secrets in en triggert de eerste builds. Wacht vervolgens op buildcompletion.

**Gebruikt door:** `setup-cicd-pipeline.yml` (Phase 4)

## Wat doet deze rol?

1. **Admin-token ophalen/aanmaken**: leest `DRONE_ADMIN_TOKEN` uit het k8s-secret. Als het secret ontbreekt, wordt een nieuw token gegenereerd.
2. **OAuth-token injecteren**: schrijft de `drone-oauth` Gitea-PAT direct naar de SQLite-database van Drone. Dit is een workaround omdat de officiële Drone API-sync een actieve browser-sessie vereist en niet via de API werkt.
3. **Drone server + runner herstarten**: na de database-update herstart Drone om de in-memory cache te legen. De runner herstart zodat hij opnieuw verbinding maakt met de verse server-pod.
4. **Repos invoegen via directe SQL INSERT**: Drone's normale sync-mechanisme werkt niet in-cluster. De oplossing is een `INSERT OR REPLACE` in de SQLite-database met repo-metadata opgehaald van de Gitea API.
5. **Repos activeren**: via de Drone API (`POST /api/repos/<org>/<repo>`) — dit maakt de Gitea-webhook aan.
6. **Secrets instellen**: registry-URL, gebruikersnaam, wachtwoord en image-repo-paden als Drone repo-secrets.
7. **Code pushen**: kloont elke repo van GitHub (bare clone) op de Ansible-controllernode en pusht naar Gitea. Dit triggert de webhook en daarmee de eerste build.
8. **Wachten op builds**: wacht tot alle builds klaar zijn (max. 30 minuten per build). Waarschuwt bij mislukte builds maar faalt het playbook niet.

## Koppeling met Gitea — drie contactmomenten

### 1. OAuth-token injectie (PAT in SQLite)

Drone's ingebouwde repo-sync vereist een browser-OAuth-flow die Ansible niet kan uitvoeren. De `gitea-repos` rol heeft eerder een PAT aangemaakt met scope `write:repository`, `write:organization`, `write:user`, `write:admin`. Die PAT wordt direct in de Drone-database geschreven:

```sql
UPDATE users
SET user_oauth_token = '<gitea-drone-PAT>'
WHERE user_login = '<admin>'
```

Na deze stap kan Drone namens de admin-user Gitea-repos benaderen. Drone wordt daarna herstart om de cache te legen.

### 2. Repo-activering via Drone API (maakt Gitea-webhook aan)

```
POST http://localhost:<drone_port>/api/repos/<org>/<repo>
Authorization: Bearer <DRONE_ADMIN_TOKEN>
```

Drone maakt bij activering automatisch een webhook aan in Gitea. Bij elke push naar die Gitea-repo stuurt Gitea een HTTP POST naar Drone, waarna Drone een build start.

### 3. Code pushen van GitHub naar Gitea (eerste build triggeren)

Er is geen automatische sync van GitHub naar Gitea. Bij de eerste deployment kloont `drone-setup` de repos eenmalig van GitHub op de Ansible-controllernode en pusht ze naar Gitea:

```bash
git clone --bare <github_url> /tmp/repo.git
git -C /tmp/repo.git push --mirror http://<admin>:<password>@<gitea>/<org>/<repo>.git
```

Dit wordt uitgevoerd met `delegate_to: localhost` — de git-commando's draaien op de Ansible-controllernode, niet op de k3s-server. De push naar Gitea triggert de webhook en daarmee de eerste Drone build.

Nieuwe commits op GitHub worden **niet** automatisch naar Gitea gespiegeld. Een nieuwe push vereist een herrun van Phase 4, of een directe push naar Gitea.

## Build-secrets

Per repo worden vijf secrets ingesteld via de Drone API, zodat `.drone.yml` pipelines ze als omgevingsvariabele kunnen gebruiken:

| Secret | Waarde | Gebruik in pipeline |
|---|---|---|
| `GITEA_REGISTRY` | `<k3s_server_ip>:30080` | Docker login endpoint |
| `GITEA_REGISTRY_USERNAME` | Gitea admin gebruikersnaam | Docker login |
| `GITEA_REGISTRY_PASSWORD` | Gitea admin wachtwoord | Docker login |
| `KUMA_IMAGE_REPO` | `<registry>/<org>/orange-uptime-kuma` | Image push destination |
| `MGMT_IMAGE_REPO` | `<registry>/<org>/orange-uptime-kuma-management-tool` | Image push destination |

## Volledig stroomschema

```
Ansible (drone-setup, delegate_to: localhost)
  │  git clone --bare <github_url>
  │  git push --mirror → Gitea repo
  ▼
Gitea (:30080)
  │  webhook POST naar Drone
  ▼
Drone Server (:80)
  │  stuurt build-opdracht via RPC (DRONE_RPC_SECRET)
  ▼
Drone Runner
  │  leest .drone.yml
  │  stuurt Docker-commando's naar DinD sidecar (tcp://localhost:2375)
  ▼
DinD
  │  bouwt Docker image
  │  pusht naar Gitea registry als <org>/orange-uptime-kuma:<sha7>
  ▼
Gitea container registry (:30080)
  ▼
ArgoCD Image Updater detecteert nieuwe digest → commit → sync
```

## Variabelen

Geen rolspecifieke defaults. Gebruikt `repos` (uit `gitea-repos/defaults/main.yml`) en variabelen uit group_vars.

## Afhankelijkheden

- `gitea-repos` is uitgevoerd en heeft `repo_checks`, `gitea_repo_details` en `gitea_drone_pat` geregistreerd.
- Drone server en runner draaien.

## Opmerkingen

- **Directe SQL-inserts zijn een workaround**: de officiële manier om repos te synchroniseren in Drone vereist een OAuth-browser-flow die Ansible niet kan uitvoeren. De directe database-aanpak is robuust gebleken.
- **sqlite3 gaat verloren na pod-herstart**: het `apk add sqlite`-commando in de Drone-pod is vluchtig. Daarom wordt sqlite3 opnieuw geïnstalleerd na de herstart van Drone.
- **Builds mislukken niet het playbook**: als een repo een buildfout heeft (bv. Dockerfile-bug), hoeft het hele platform niet opnieuw uitgerold te worden. Er verschijnt een waarschuwing met een link naar de build-logs in Drone.
- **`delegate_to: localhost`** bij de GitHub→Gitea push: de git-commando's worden uitgevoerd op de Ansible-controllernode, niet op de k3s-server.
