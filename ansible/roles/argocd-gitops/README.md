# argocd-gitops

Koppelt Argo CD aan de twee GitOps-repositories en configureert de Image Updater voor automatische image-updates. Na deze rol synchroniseert Argo CD alle klant-deployments automatisch vanuit Git.

**Gebruikt door:** `setup-cicd-pipeline.yml` (play 2)

## Wat doet deze rol?

1. **Repository-credentials**: maakt twee Secrets aan in de `argocd`-namespace (gelabeld als `argocd.argoproj.io/secret-type: repository`) zodat Argo CD de Gitea-repos kan lezen:
   - `gitea-customer-instances` → `http://gitea-http.gitea.svc:3000/<org>/customer-instances.git`
   - `gitea-test-customers` → `http://gitea-http.gitea.svc:3000/<org>/test-customers.git`

2. **Image Updater configureren**:
   - Secret `gitea-image-updater` met Gitea-credentials.
   - ConfigMap `argocd-image-updater-config` met registry-definitie (HTTP, prefix op het externe IP:poort, in-cluster API via `gitea-http.gitea.svc:3000`).
   - Herstart de Image Updater zodat de nieuwe config actief wordt.

3. **AppProject `customer-provisioning`**: begrenst wat Argo CD mag doen:
   - Alleen de twee GitOps-repos als bron.
   - Alleen de benodigde resource-types (Namespace, Service, PVC, Deployment, NetworkPolicy, Ingress).

4. **Applications**:
   - `customer-instances`: synchroniseert `customers/*.yaml` uit de customer-instances-repo.
   - `test-customers`: synchroniseert `customers/*.yaml` uit de test-customers-repo.
   - Beide met `automated sync`, `prune: true` en `CreateNamespace: true`.
   - Beide met Image Updater-annotaties om de Uptime Kuma image automatisch bij te werken.

5. Wacht tot beide Applications `Synced` zijn.

## Variabelen

Geen rolspecifieke defaults. Gebruikt `gitea_argocd_pat` (geregistreerd door `gitea-repos`) en group_vars.

## Afhankelijkheden

- `gitea-repos` heeft `gitea_argocd_pat` geregistreerd.
- `argocd` en `argocd-image-updater` draaien.
- GitOps-repos bestaan in Gitea.

## Koppeling met Gitea

### Authenticatie — Personal Access Token

De `gitea-repos` rol maakt een PAT aan via de Gitea API:

```
POST /api/v1/users/<admin>/tokens
  naam:  "argocd-gitops"
  scope: read:repository
```

Die token wordt als Ansible-fact doorgegeven (`gitea_argocd_pat.json.sha1`) en in deze rol in Kubernetes gezet als Secret-inhoud.

### Repository Secrets

ArgoCD herkent Secrets met het label `argocd.argoproj.io/secret-type: repository` automatisch als repo-credentials. Er worden twee zulke Secrets aangemaakt:

```yaml
stringData:
  type: git
  url: http://gitea-http.gitea.svc:3000/<org>/customer-instances.git
  username: <gitea_admin_user>
  password: <argocd-gitops PAT>
```

De URL is de **in-cluster DNS-naam** van de Gitea service (`gitea-http.gitea.svc:3000`), niet het externe IP. ArgoCD praat nooit via de NodePort naar buiten.

### Polling in plaats van webhook

ArgoCD pollt de Gitea Git-repo elke 30 seconden via gewone Git-fetch operaties. Webhooks van Gitea naar ArgoCD werken niet: Gitea stuurt webhooks naar z'n eigen `ROOT_URL` (extern adres), maar ArgoCD is alleen in-cluster bereikbaar. De twee komen niet overeen. Zie ook de `argocd` rol voor de reconciliation-interval instelling.

### Image Updater — twee contactpunten naar Gitea

De Image Updater heeft een afwijkende configuratie omdat hij zowel de registry API aanspreekt als terugschrijft naar Git:

| Contactpunt | URL | Reden |
|---|---|---|
| Registry API (lezen) | `http://gitea-http.gitea.svc:3000` | In-cluster, geen NodePort nodig |
| Registry prefix (images) | `<k3s_server_ip>:30080` | Extern adres, want containerd op de nodes gebruikt dit om images te pullen |
| Git write-back | zelfde in-cluster URL | Commit nieuwe image-digest terug naar `customer-instances.git` |

```
[ArgoCD Image Updater]
    │  pollt registry API: gitea-http.gitea.svc:3000
    │  image prefix voor containerd: <extern IP>:30080
    │  detecteert nieuwe digest
    │  commit image-referentie terug naar customer-instances.git
    ▼
[ArgoCD detecteert nieuwe commit → sync → rolling update]
```

## Hoe werkt de automatische image-update?

1. Drone bouwt een nieuwe image en pusht die naar de Gitea registry (tag: git-SHA).
2. De Image Updater detecteert de nieuwe digest via de Gitea registry API.
3. De Image Updater commit de nieuwe image-referentie in `customer-instances` (en/of `test-customers`).
4. Argo CD detecteert de nieuwe commit via polling en rolt de update uit naar alle klant-namespaces.

Audit trail bij elke stap: Drone build log → Gitea registry tag history → Git commit op de manifest-repo → Argo CD sync history. Terugdraaien is een `git revert` op de manifest-commit; Argo CD reconcilieert automatisch terug naar het vorige image.

## Volledig stroomschema

```
[ArgoCD application-controller]
    │  elke 30s: git fetch
    │  via: gitea-http.gitea.svc:3000 (in-cluster)
    │  auth: argocd-gitops PAT (read:repository)
    ▼
[Gitea repo: customer-instances.git / test-customers.git]
    │  customers/*.yaml

[ArgoCD Image Updater]
    │  pollt registry API: gitea-http.gitea.svc:3000
    │  image prefix voor containerd: <extern IP>:30080
    │  bij nieuwe digest: git commit + push naar customer-instances.git
    │  auth: argocd-gitops PAT
    ▼
[ArgoCD detecteert nieuwe commit → sync → kubectl apply]
    ▼
[Kubernetes: customer-<naam> namespaces — draaiend op nieuwe image]
```

## Opmerkingen

- **AppProject-destination is `namespace: '*'`** (niet `customer-*`). Elke klant-manifest draagt zijn eigen namespace in `metadata.namespace`. Argo CD vult de destination-namespace in van de Application, niet van individuele manifests. Als de Application geen namespace heeft, is de effectieve namespace leeg — en `customer-*` matcht niet op leeg. Vandaar de wildcard.
- **In-cluster URL vs extern URL**: de Image Updater gebruikt `gitea-http.gitea.svc:3000` als API-URL (in-cluster), maar de registry-prefix is het externe IP:poort. Dit onderscheid is essentieel: containerd op de nodes spreekt de externe URL aan.
