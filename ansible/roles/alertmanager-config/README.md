# alertmanager-config

Configureert Alertmanager om alle Kubernetes-alerts via e-mail naar Mailpit te sturen. Alertmanager is de component die bepaalt wie een melding krijgt, wanneer, en via welk kanaal.

**Gebruikt door:** `bootstrap-platform.yml`

## Wat doet deze rol?

1. Maakt (of overschrijft) een Kubernetes-secret `alertmanager-prometheus-kube-prometheus-alertmanager` in de `monitoring`-namespace. Dit is het secret dat de kube-prometheus-stack gebruikt als Alertmanager-configuratie.
2. De configuratie bevat:
   - **SMTP-smarthost**: `mailpit.mailpit.svc.cluster.local:1025` (in-cluster Mailpit service).
   - **Routing**: alle alerts, inclusief Watchdog, gaan naar de `email`-receiver.
   - **Inhibition-regels**: voorkomen dat een `warning`-alert ook veroorzaakt wordt als er al een `critical`-alert is voor hetzelfde probleem.
3. Herstart de Alertmanager StatefulSet zodat de nieuwe configuratie wordt ingelezen.

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `alert_receiver_email` | — | E-mailadres dat Alertmanager als ontvangeradres gebruikt (uit group_vars) |

## Afhankelijkheden

- `kube-prometheus-stack` is geïnstalleerd.
- `mailpit` draait en is bereikbaar op `mailpit.mailpit.svc.cluster.local:1025`.

## Opmerkingen

- **Watchdog-alert**: Prometheus stuurt permanent een `Watchdog`-alert. Dit is een heartbeat om te bevestigen dat de hele alerting-pipeline werkt. In deze configuratie gaat de Watchdog naar de `email`-receiver — je ziet hem dus in Mailpit. Dit is normaal gedrag.
- **Secret-naam is voorgeschreven** door de kube-prometheus-stack chart: `alertmanager-<release-naam>-alertmanager`. De releasenaam is `prometheus`, vandaar de lange naam.
- Bij een re-run wordt de configuratie overschreven via `--dry-run=client -o yaml | kubectl apply -f -` (idempotent).
