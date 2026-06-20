# argocd-image-updater

Installeert de Argo CD Image Updater, een aanvulling op Argo CD die automatisch nieuwe container-images detecteert en de image-referentie in de Git-repository bijwerkt. Hierdoor worden klant-deployments automatisch bijgewerkt zodra Drone een nieuwe image bouwt.

**Gebruikt door:** `bootstrap-platform.yml`

## Wat doet deze rol?

1. Voegt de Argo CD Helm-repo toe (dezelfde als voor Argo CD zelf).
2. Installeert de Image Updater via Helm.

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `argocd_image_updater_chart_version` | `"0.11.0"` | Helm-chartversie |
| `argocd_image_updater_install_timeout` | `"8m"` | Timeout voor Helm install |

## Afhankelijkheden

- `argocd` is geïnstalleerd.
- `namespaces` heeft de `argocd`-namespace aangemaakt.

## Hoe werkt het?

De Image Updater wordt in Phase 4 (`argocd-gitops`-rol) volledig geconfigureerd met:
- Gitea registry-credentials (Secret).
- Registry-configuratie (ConfigMap met endpoint, prefix, insecure-flag).
- Write-back via Git naar de customer-instances en test-customers repos.

De Image Updater controleert periodiek de Gitea registry. Als er een nieuw image-digest beschikbaar is, commit hij de nieuwe image-referentie in Git. Argo CD detecteert die commit en rolt de update uit naar alle klant-deployments.

## Opmerkingen

- De Image Updater draait in de `argocd`-namespace maar is een apart component — het heeft eigen credentials nodig.
- **Write-back via Git** (niet direct naar k8s): dit is de aanbevolen aanpak omdat het een audit-trail geeft (elke image-update is een Git-commit).
