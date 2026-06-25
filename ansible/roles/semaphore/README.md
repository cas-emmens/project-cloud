# semaphore

Deployt Semaphore, een webinterface voor het uitvoeren van Ansible-playbooks. Via Semaphore kunnen verkopers (sales) en operators (ops) klanten aanmaken zonder Ansible zelf te hoeven kennen.

**Gebruikt door:** `bootstrap-platform.yml` (Phase 3)

## Wat doet deze rol?

### Stap 1 — Encryption key beheren (idempotent)
Semaphore versleutelt zijn BoltDB-database met een access-key. Als die key bij elke Ansible-run opnieuw wordt gegenereerd, kan Semaphore zijn eigen database niet meer lezen en crasht de pod (`CrashLoopBackOff`). Oplossing:
- Lees de bestaande key uit het Kubernetes-secret (als die er al is).
- Genereer alleen een nieuwe key als het secret nog niet bestaat.
- Sla de key op in het secret zodat hij stabiel blijft over alle re-runs.

### Stap 2 — Deployment
Deployt via `kubectl apply`:
- **Deployment** met `strategy: Recreate` (geen rolling update — BoltDB is geen gedeelde opslag).
- **PVC** (1 Gi via Longhorn) voor de database.
- **Service** genaamd `semaphore-ui` (niet `semaphore`!) op vaste NodePort.

### Stap 3 — Project bootstrap via REST API
Maakt via `curl` en cookie-sessie-authenticatie de volledige projectstructuur aan (idempotent):
- Project "Orange Kuma Provisioning".
- SSH-key "none" (vereist placeholder in Semaphore).
- Repository die wijst naar het `project-cloud` GitHub-repo.
- Inventory "localhost" (Semaphore voert Ansible lokaal in de pod uit).
- Environments "sales" (→ customer-instances) en "ops" (→ test-customers).
- Templates "Nieuwe klant aanmaken" (sales) en "Testklant aanmaken" (ops) met survey-variabelen.

## Architectuur

Semaphore is de gebruikerslaag bovenop Ansible. Sales en ops vullen een formulier in; Semaphore voert het Ansible-playbook uit binnen de pod zelf:

```
Gebruiker (browser)
    │  vult formulier in (klantnaam, email, wachtwoord, domein)
    ▼
Semaphore UI  :30084
    │  kloont project-cloud van GitHub
    │  voert uit: ansible/playbooks/provision-customer.yml
    │  inventory: localhost (Ansible draait IN de Semaphore pod)
    ▼
Ansible (in de pod)
    │  rendert manifest → pusht naar Gitea repo
    ▼
ArgoCD detecteert nieuwe commit → sync → klant live
```

## Projectstructuur in Semaphore

Er zijn geen losse YAML-bestanden voor de Semaphore-configuratie. De volledige projectstructuur leeft in de BoltDB-database en wordt bij de bootstrap via de REST API aangemaakt. De structuur ziet er als volgt uit:

### Repository

| Veld | Waarde |
|---|---|
| Naam | `project-cloud` |
| Git URL | `https://github.com/cas-emmens/project-cloud.git` |
| Branch | Per omgeving (zie Variabelen) |

Semaphore kloont dit repo bij elke taakuitvoering vanuit GitHub — niet vanuit Gitea.

### Inventory

`localhost ansible_connection=local` — Ansible draait in de Semaphore pod zelf, niet op een externe host.

### Environments

De twee environments bepalen naar welke Gitea-repo het klantmanifest geschreven wordt:

| Environment | `target_repo` | Gebruik |
|---|---|---|
| `sales` | `customer-instances` | Productie-klanten |
| `ops` | `test-customers` | Testklanten |

Beide environments bevatten ook `k3s_server_ip`, `domain_suffix` en `ansible_python_interpreter`.

### Templates en survey-variabelen

Beide templates voeren hetzelfde playbook uit (`ansible/playbooks/provision-customer.yml`) maar met een andere environment. Bij uitvoering verschijnt een formulier:

| Veld | Vereist | Omschrijving |
|---|---|---|
| `customer_name` | ja | Slug: 3-32 tekens, kleine letters/cijfers/streepjes |
| `customer_email` | ja | Contactadres van de klant |
| `admin_password` | ja | Initieel Uptime Kuma admin wachtwoord |
| `customer_domain` | nee | Domein om automatisch te monitoren (bv. `klant.example.com`) |

| Template | Environment | Doelgroep |
|---|---|---|
| `Nieuwe klant aanmaken` | sales | Verkopers — schrijft naar `customer-instances` |
| `Testklant aanmaken` | ops | Operators — schrijft naar `test-customers` |

## Waar staat de configuratie?

De projectconfiguratie (project, repository, inventory, environments, templates) leeft uitsluitend in de BoltDB-database op `/var/lib/semaphore` (Longhorn PVC, 1Gi). Er zijn geen losse configuratiebestanden.

De database wordt versleuteld met `SEMAPHORE_ACCESS_KEY_ENCRYPTION`, bewaard in het Kubernetes Secret `semaphore-secrets`. Als die key wijzigt bij een herdeployment kan Semaphore de database niet meer lezen en crasht de pod in `CrashLoopBackOff`.

**Configuratie nakijken in een live systeem:**
```bash
# Kubernetes Secret met encryption key en admin wachtwoord
kubectl -n semaphore get secret semaphore-secrets -o yaml

# Via de Semaphore UI
http://<k3s_server_ip>:30084
# Navigeer naar: Project → Repositories / Inventory / Environment / Templates
```

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `semaphore_namespace` | `"semaphore"` | Kubernetes namespace |
| `semaphore_image` | `"semaphoreui/semaphore:v2.10.34"` | Container-image (gepind) |
| `semaphore_persistence_size` | `"1Gi"` | Opslag voor BoltDB-database |
| `semaphore_port` | — | NodePort (uit group_vars, `30084`) |
| `semaphore_repo_url` | — | GitHub-URL van project-cloud (uit inventory group_vars) |
| `semaphore_repo_branch` | — | Branch die Semaphore gebruikt (per omgeving) |

**Branch per omgeving** (in `inventories/<env>/group_vars/all.yml`):

| Omgeving | Branch |
|---|---|
| `test`, `acc` | `development` |
| `hanze` | `main` |

## Afhankelijkheden

- `longhorn` is geïnstalleerd.
- `namespaces` heeft de `semaphore`-namespace aangemaakt.

## Opmerkingen

- **Service heet `semaphore-ui`, niet `semaphore`.** Kubernetes injecteert omgevingsvariabelen voor elke service in de namespace (`SERVICENAAM_PORT=tcp://...`). Als de service `semaphore` heet, injecteert Kubernetes `SEMAPHORE_PORT=tcp://10.43.x.x:3000` in de Semaphore-pod. Semaphore leest `SEMAPHORE_PORT` als zijn eigen luisterpoort en verwacht een getal — de `tcp://`-waarde laat de pod crashen. Door de service `semaphore-ui` te noemen wordt deze injectie omzeild.
- **Strategy: Recreate** — BoltDB is embedded en kan niet door meerdere pods tegelijk beschreven worden. Bij een update stopt de oude pod volledig voor de nieuwe start.
- **BoltDB vs PostgreSQL**: BoltDB is embedded en heeft geen externe database nodig. De crash-oorzaak was key-drift bij re-runs, niet een database-probleem op zich.
- **Idempotent bootstrap**: bij een re-run wordt elk object (project, repo, inventory, environment, template) alleen aangemaakt als het nog niet bestaat. Bestaande objecten worden niet overschreven.
- Semaphore voert Ansible uit **binnen de pod** (localhost inventory). Het project-cloud repo wordt gekloond vanuit GitHub, niet vanuit Gitea.
