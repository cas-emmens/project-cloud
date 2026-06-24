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

## Hoe werkt de automatische image-update?

1. Drone bouwt een nieuwe image en pusht die naar de Gitea registry (tag: git-SHA).
2. De Image Updater detecteert de nieuwe digest.
3. De Image Updater commit de nieuwe image-referentie in `customer-instances` (en/of `test-customers`).
4. Argo CD detecteert de nieuwe commit en rolt de update uit naar alle klant-namespaces.

## Opmerkingen

- **AppProject-destination is `namespace: '*'`** (niet `customer-*`). Elke klant-manifest draagt zijn eigen namespace in `metadata.namespace`. Argo CD vult de destination-namespace in van de Application, niet van individuele manifests. Als de Application geen namespace heeft, is de effectieve namespace leeg — en `customer-*` matcht niet op leeg. Vandaar de wildcard.
- **In-cluster URL vs extern URL**: de Image Updater gebruikt `gitea-http.gitea.svc:3000` als API-URL (in-cluster), maar de registry-prefix is het externe IP:poort. Dit onderscheid is essentieel: containerd op de nodes spreekt de externe URL aan.
