# drone-setup

Koppelt Drone CI aan de Gitea-repositories: injecteert het OAuth-token, synchroniseert repos in de Drone-database, activeert repositories, stelt secrets in en triggert de eerste builds. Wacht vervolgens op buildcompletion.

**Gebruikt door:** `setup-cicd-pipeline.yml` (play 2)

## Wat doet deze rol?

1. **Admin-token ophalen/aanmaken**: leest `DRONE_ADMIN_TOKEN` uit het k8s-secret. Als het secret ontbreekt, wordt een nieuw token gegenereerd.
2. **OAuth-token injecteren**: schrijft de `drone-oauth` Gitea-tokenwaarde direct naar de SQLite-database van Drone (`UPDATE users SET user_oauth_token=...`). Dit is een workaround omdat de officiële Drone API-sync (`/api/user/repos?flush=true`) een actieve browser-sessie vereist en niet werkt via de API.
3. **Drone server + runner herstarten**: na de database-update herstart Drone om de cache te legen. De runner herstart zodat hij opnieuw verbinding maakt met de verse server-pod.
4. **Repos in Drone-database invoegen via directe SQL INSERT**: Drone's normale sync-mechanisme werkt niet in-cluster. De oplossing is een `INSERT OR REPLACE` in de SQLite-database met alle repo-metadata (gecloned van Gitea).
5. **Repos activeren**: via de Drone API (`POST /api/repos/<org>/<repo>`) — dit maakt de Gitea-webhook aan.
6. **Secrets instellen**: registry-URL, gebruikersnaam, wachtwoord, en image-repo-paden als Drone repo-secrets.
7. **Code pushen**: kloont elke repo van GitHub (bare clone) en pusht naar Gitea. Hierdoor triggert de webhook een build.
8. **Wachten op builds**: wacht tot alle builds klaar zijn (max. 30 minuten per build). Waarschuwt bij mislukte builds maar faalt het playbook niet.

## Variabelen

Geen rolspecifieke defaults. Gebruikt `repos` (uit `gitea-repos/defaults/main.yml`) en variabelen uit group_vars.

## Afhankelijkheden

- `gitea-repos` is uitgevoerd en heeft `repo_checks`, `gitea_repo_details` en `gitea_drone_pat` geregistreerd.
- Drone server en runner draaien.

## Opmerkingen

- **Directe SQL-inserts zijn een workaround**: de officiële manier om repos te synchroniseren in Drone vereist een OAuth-browser-flow die Ansible niet kan uitvoeren. De directe database-aanpak is robuust gebleken.
- **sqlite3 gaat verloren na pod-herstart**: het `apk add sqlite`-commando in de Drone-pod is vluchtig. Daarom wordt sqlite3 opnieuw geïnstalleerd na de herstart van Drone.
- **Builds mislukken niet het playbook**: als een externe repo (GitHub) een buildfout heeft (bv. Dockerfile-bug), hoeft het hele platform niet opnieuw uitgerold te worden. Een waarschuwing volstaat.
- **`delegate_to: localhost`** bij de GitHub→Gitea push: de git-commando's worden uitgevoerd op de Ansible-controllernode, niet op de k3s-server.
