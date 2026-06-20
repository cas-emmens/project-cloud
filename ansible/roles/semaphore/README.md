# semaphore

Deployt Semaphore, een webinterface voor het uitvoeren van Ansible-playbooks. Via Semaphore kunnen verkopers (sales) en operators (ops) klanten aanmaken zonder Ansible zelf te hoeven kennen.

**Gebruikt door:** `bootstrap-platform.yml`

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

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `semaphore_namespace` | `"semaphore"` | Kubernetes namespace |
| `semaphore_image` | `"semaphoreui/semaphore:v2.10.34"` | Container-image |
| `semaphore_persistence_size` | `"1Gi"` | Opslag voor BoltDB-database |
| `semaphore_port` | — | NodePort (uit group_vars, bv. 30084) |
| `semaphore_repo_url` | — | GitHub-URL van project-cloud (uit inventory group_vars) |
| `semaphore_repo_branch` | — | Branch die Semaphore gebruikt (uit inventory group_vars) |

## Afhankelijkheden

- `longhorn` is geïnstalleerd.
- `namespaces` heeft de `semaphore`-namespace aangemaakt.

## Opmerkingen

- **Service heet `semaphore-ui`, niet `semaphore`.** Kubernetes injecteert omgevingsvariabelen voor elke service in de namespace (`SERVICENAAM_PORT=tcp://...`). Als de service `semaphore` heet, injecteert Kubernetes `SEMAPHORE_PORT=tcp://10.43.x.x:3000` in de Semaphore-pod. Semaphore leest `SEMAPHORE_PORT` als zijn eigen luisterpoort en verwacht een getal — de `tcp://`-waarde laat de pod crashen. Door de service `semaphore-ui` te noemen wordt deze injectie omzeild.
- **BoltDB vs PostgreSQL**: BoltDB is embedded en heeft geen externe database nodig. De oorspronkelijke crash was key-drift, niet een database-probleem.
- Semaphore voert Ansible uit **binnen de pod** (localhost inventory). Het project-cloud repo wordt gekloond vanuit GitHub, niet vanuit Gitea.
