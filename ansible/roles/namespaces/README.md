# namespaces

Maakt alle Kubernetes-namespaces aan die het platform nodig heeft. Door namespaces vooraf aan te maken, kunnen alle volgende rollen hun resources deployen zonder zelf de namespace te hoeven controleren.

**Gebruikt door:** `bootstrap-platform.yml`

## Wat doet deze rol?

Maakt de volgende namespaces aan (idempotent via `--dry-run=client | kubectl apply`):

| Namespace | Gebruik |
|-----------|---------|
| `gitea` | Gitea Git-server en container registry |
| `drone` | Drone CI server en runner |
| `argocd` | Argo CD GitOps-controller |
| `monitoring` | Prometheus, Grafana, Alertmanager |
| `semaphore` | Semaphore Ansible-UI |
| `orange-kuma` | Management Tool dashboard |
| `mailpit` | Mailpit SMTP-catcher |
| `ingress-nginx` | Ingress-nginx controller |

## Variabelen

Geen.

## Afhankelijkheden

- k3s is actief.

## Opmerkingen

- Namespaces zijn bewust centraal beheerd: als een rol zelf zijn namespace aanmaakt en de rol mislukt halverwege, kan de namespace al bestaan terwijl de rest van de configuratie ontbreekt. Door namespaces vooraf aan te maken is de staat voorspelbaar.
- De namespace `kube-system` bestaat altijd al in k3s en hoeft niet aangemaakt te worden (gebruikt door Headlamp).
