# argocd

Installeert Argo CD, een GitOps-controller die Kubernetes-resources automatisch synchroniseert met wat er in een Git-repository staat. Wijzigingen in Git worden automatisch uitgerold naar het cluster.

**Gebruikt door:** `bootstrap-platform.yml`

## Wat doet deze rol?

1. Voegt de Argo CD Helm-repo toe.
2. Installeert Argo CD via Helm met:
   - NodePort-service voor HTTP en HTTPS.
   - `--insecure` modus (geen TLS op de Argo CD server zelf — TLS wordt afgehandeld door ingress-nginx).
   - Reconciliation-interval van 30 seconden.
3. Wacht tot de `argocd-server`-deployment klaar is.
4. Herstart de `application-controller` zodat het reconciliation-interval wordt opgepikt (dit wordt alleen bij opstart gelezen).
5. Leest het initiële admin-wachtwoord uit het Kubernetes-secret en slaat het op als Ansible-fact (`argocd_password.stdout`) voor gebruik in de afsluitsamenvatting.

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `argocd_namespace` | `"argocd"` | Kubernetes namespace |
| `argocd_chart_version` | `"7.6.12"` | Helm-chartversie |
| `argocd_reconciliation_interval` | `"30s"` | Hoe vaak Argo CD de Git-repo controleert |
| `argocd_install_timeout` | `"10m"` | Timeout voor Helm install |
| `argocd_port` | — | NodePort HTTP (uit group_vars) |
| `argocd_https_port` | — | NodePort HTTPS (uit group_vars, gepind op 30443) |

## Afhankelijkheden

- `helm` is geïnstalleerd.
- `namespaces` heeft de `argocd`-namespace aangemaakt.

## Opmerkingen

- **Reconciliation 30s i.p.v. standaard 3 minuten.** Gitea's webhooks werken niet vanuit het cluster naar de Argo CD server (ROOT_URL mismatch bij in-cluster communicatie). Polling elke 30 seconden compenseert dit.
- **`application-controller` wordt apart herstart** omdat dit component het reconciliation-interval alleen inleest bij het opstarten, niet bij een config-update.
- Het initiële admin-wachtwoord staat in het secret `argocd-initial-admin-secret`. Dit secret is door Argo CD aangemaakt bij de eerste installatie en wordt bewust bewaard (niet verwijderd na eerste login).
