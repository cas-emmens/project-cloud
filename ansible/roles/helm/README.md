# helm

Installeert de Helm 3 package-manager op de k3s-servernode. Helm is het standaard tool om Kubernetes-applicaties te installeren via zogenaamde "charts" (pakketbeschrijvingen).

**Gebruikt door:** `bootstrap-platform.yml` (eerste rol, vóór alle andere)

## Wat doet deze rol?

1. Controleert of `/usr/local/bin/helm` al bestaat.
2. Installeert Helm via het officiële installatiescript als het nog niet aanwezig is:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   ```

## Wat is Helm?

Helm is het pakketbeheersysteem voor Kubernetes. Een Helm **chart** is een bundel van Kubernetes-manifesten (Deployments, Services, ConfigMaps, CRDs, RBAC-regels, etc.) voor één applicatie. In plaats van tientallen losse YAML-bestanden handmatig toe te passen, installeer je met Helm één chart met een paar parameters.

```bash
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version 7.6.12 \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttp=30082
```

Helm regelt de volgorde van resources, verwerkt dependencies en houdt bij welke versie geïnstalleerd is.

## Welke services draaien via Helm in dit platform?

| Service | Chart | Versie |
|---|---|---|
| ArgoCD | `argo/argo-cd` | `7.6.12` |
| ArgoCD Image Updater | `argo/argocd-image-updater` | `0.11.0` |
| Gitea | `gitea-charts/gitea` | `10.4.1` |
| kube-prometheus-stack | `prometheus-community/kube-prometheus-stack` | `65.1.1` |
| Longhorn | `longhorn/longhorn` | latest |
| Headlamp | `headlamp/headlamp` | `0.27.0` |
| ingress-nginx | `ingress-nginx/ingress-nginx` | `4.11.3` |

Drone, Semaphore, Mailpit en de Management Tool worden **niet** via Helm geïnstalleerd — die hebben eenvoudige manifesten die direct via `kubectl apply` worden toegepast.

## Helm vs. kubectl apply

| | Helm | kubectl apply |
|---|---|---|
| Geschikt voor | Complexe upstream applicaties met veel resources | Eenvoudige eigen manifesten |
| Configuratie | Via `--set` flags of values-bestanden | Rechtstreeks in YAML |
| Upgrade | `helm upgrade` beheert de delta | Handmatig manifesten bijhouden |
| Rollback | `helm rollback` | Niet ingebouwd |
| Versie-tracking | Ingebouwd (`helm list`) | Niet ingebouwd |

## Variabelen

Geen. Het installatiescript bepaalt zelf de laatste stabiele Helm 3 versie.

## Afhankelijkheden

- k3s is geïnstalleerd en `kubectl` werkt.
- Internetverbinding naar `raw.githubusercontent.com`.

## Opmerkingen

- **Geen versiepin**: het installatiescript installeert altijd de nieuwste Helm 3. Dit is de enige plek in het platform zonder expliciete versiepin. Helm 3's CLI is backwards-compatible, waardoor dit in de praktijk geen problemen geeft.
- **Idempotent**: bestaat `/usr/local/bin/helm` al, dan wordt het script niet opnieuw uitgevoerd.
- **Helm 3 heeft geen Tiller meer**: Helm 2 had een servercomponent (`tiller`) in het cluster nodig. Helm 3 werkt rechtstreeks met de Kubernetes API — geen extra component, geen extra rechten.
- Alle versies van de geïnstalleerde charts zijn gepind in de playbook-variabelen. Zie `docs/auto-update-strategy.md` voor de redenering (Tier C).
