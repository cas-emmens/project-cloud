# kube-prometheus-stack

Installeert de volledige monitoring-stack: Prometheus (metrics-opslag), Grafana (dashboards) en Alertmanager (meldingen). Pinned op vaste NodePorts zodat adressen stabiel zijn bij re-deploys.

**Gebruikt door:** `bootstrap-platform.yml`

## Wat doet deze rol?

1. Voegt de Prometheus community Helm-repo toe.
2. Rendert een Grafana-values-bestand met datasource-configuratie (Prometheus + Alertmanager) en dashboard-sidecar-instellingen.
3. Installeert de stack via Helm met:
   - Persistente opslag voor Prometheus, Grafana en Alertmanager (via Longhorn).
   - NodePort-services op vaste poortnummers.
   - Grafana-wachtwoord gelijk aan het Gitea-adminwachtwoord (één wachtwoord voor het hele platform).
4. **Pinned NodePorts voor de config-reloaders** (poort 8080): Prometheus en Alertmanager hebben een tweede poort voor hun config-reloader-sidecar. k3s wijst hier een willekeurige NodePort aan die kan conflicteren. Expliciet gepind op 30091 (Prometheus) en 30092 (Alertmanager).
5. Kopieert het Orange Platform Grafana-dashboard JSON naar de node.
6. Maakt een ConfigMap aan met het dashboard JSON en voegt het label `grafana_dashboard=1` toe zodat de Grafana sidecar het automatisch importeert.

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `prometheus_stack_chart_version` | `"65.1.1"` | Helm-chartversie |
| `prometheus_namespace` | `"monitoring"` | Kubernetes namespace |
| `prometheus_retention` | `"7d"` | Hoe lang Prometheus data bewaart |
| `prometheus_storage_size` | `"5Gi"` | Opslag voor Prometheus TSDB |
| `grafana_storage_size` | `"2Gi"` | Opslag voor Grafana |
| `alertmanager_storage_size` | `"2Gi"` | Opslag voor Alertmanager |
| `prometheus_install_timeout` | `"15m"` | Timeout voor Helm install (lang vanwege veel CRDs) |
| `grafana_port` | — | NodePort voor Grafana (uit group_vars) |
| `prometheus_port` | — | NodePort voor Prometheus (uit group_vars) |
| `alertmanager_port` | — | NodePort voor Alertmanager (uit group_vars) |
| `prometheus_reloader_port` | — | Gepinde NodePort voor Prometheus reloader (30091) |
| `alertmanager_reloader_port` | — | Gepinde NodePort voor Alertmanager reloader (30092) |

## Afhankelijkheden

- `longhorn` is geïnstalleerd.
- `namespaces` heeft de `monitoring`-namespace aangemaakt.

## Opmerkingen

- **Config-reloader NodePorts worden gepind** omdat k3s bij elke greenfield-deploy een willekeurige poort kiest die kan botsen met andere services. De patchlogica gebruikt Python3 om de juiste index in de ports-array te vinden.
- **Dashboard-sidecar** scant alle namespaces op ConfigMaps met het label `grafana_dashboard=1`. Het Orange Platform-dashboard wordt zo automatisch zichtbaar in Grafana zonder Grafana te herstarten.
- **Grafana datasources** worden statisch geconfigureerd (geen sidecar) om te voorkomen dat ze bij elke restart opnieuw worden aangemaakt of dupliceren.
- De installatie duurt 15+ minuten bij een eerste deploy vanwege de grote hoeveelheid CRDs die het chart installeert.

## Dashboard

Het bestand `files/orange-platform-dashboard.json` bevat een vooraf geconfigureerd Grafana-dashboard met:
- CPU/memory gebruik per node.
- Longhorn volume-status.
- Pod-status voor customer-instanties.
