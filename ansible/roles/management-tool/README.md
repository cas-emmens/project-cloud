# management-tool

Deployt de Orange Kuma Management Tool, een read-only webdashboard dat een overzicht geeft van alle klant-instanties en hun Argo CD sync-status. Sluit Phase 4 af met een volledige samenvatting van alle toegangsadressen.

**Gebruikt door:** `setup-cicd-pipeline.yml` (play 2)

## Wat doet deze rol?

1. **Argo CD read-only token aanmaken** (idempotent):
   - Controleert of het secret `management-tool-argocd` al bestaat — sla over als dat zo is.
   - Maakt een local account `dashboard` aan in Argo CD met `apiKey`-rechten.
   - Kent het account de `role:readonly` RBAC-rol toe.
   - Herstart `argocd-server` zodat het nieuwe account herkend wordt.
   - Logt in als admin en mint een niet-verlopend API-token voor het `dashboard`-account.
   - Slaat het token op in het secret `management-tool-argocd` in de `orange-kuma`-namespace.

2. **Management Tool deployen**:
   - Rendert het Kubernetes-manifest vanuit `k8s/management-tool/deployment.yml.j2` (Jinja2-template).
   - Past de resources toe via `kubectl apply`.
   - Wacht tot de deployment `Ready` is.

3. **Health check**: controleert of de webinterface bereikbaar is.

4. **Samenvatting**: print een compleet overzicht van alle platform-URLs en slaat dit op in `/root/platform-summary.txt` op de k3s-server.

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `management_tool_container_port` | `4000` | Poort waarop de Node.js-app intern luistert |
| `management_tool_repo` | `"orange-uptime-kuma-management-tool"` | Naam van de repo in Gitea |
| `management_tool_image` | `"<server-ip>:<gitea_port>/<org>/orange-uptime-kuma-management-tool:latest"` | Volledig image-adres |
| `management_tool_port` | — | NodePort voor de webinterface (uit group_vars) |

## Afhankelijkheden

- Argo CD draait en de Applications zijn aangemaakt.
- De management-tool image is gebouwd door Drone en beschikbaar in de Gitea registry.
- `k8s/management-tool/deployment.yml.j2` bestaat in de repository.

## Opmerkingen

- **Token-aanmaak is idempotent**: als het secret `management-tool-argocd` al bestaat, wordt de hele token-minting overgeslagen. Dit voorkomt dat bij een re-run Argo CD's `argocd-server` onnodig herstart.
- **ArgoCD-configuratie na Helm-upgrade**: een `helm upgrade` van Argo CD reset `argocd-cm` en `argocd-rbac-cm`. Na een upgrade moet deze rol opnieuw draaien (of `--destroy-first` gebruiken). Het idempotentie-secret wordt dan niet gevonden en de token wordt opnieuw aangemaakt.
- **`/root/platform-summary.txt`**: bevat alle wachtwoorden en URLs. Bewaar dit bestand veilig — het is alleen leesbaar door root (`mode: 0600`).

## Argo CD dashboard-account

Het `dashboard`-account heeft read-only toegang via de `role:readonly` RBAC-rol. Het kan applications inzien maar niet wijzigen, synchroniseren of verwijderen.
