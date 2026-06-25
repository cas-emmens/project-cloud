# kube-prometheus-stack

Installeert de volledige monitoring-stack: Prometheus (metrics-opslag), Grafana (dashboards) en Alertmanager (meldingen). Pinned op vaste NodePorts zodat adressen stabiel zijn bij re-deploys.

**Gebruikt door:** `bootstrap-platform.yml` (Phase 3)

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

## Componenten

Alle drie de componenten worden geïnstalleerd via één Helm chart in de `monitoring` namespace:

| Component | NodePort | Opslag | Omschrijving |
|---|---|---|---|
| Prometheus | `:30090` | 5Gi Longhorn | Metrics scraping en opslag (TSDB, 7 dagen retentie) |
| Grafana | `:30083` | 2Gi Longhorn | Dashboards en visualisatie |
| Alertmanager | `:30085` | 2Gi Longhorn | Verwerking en routering van alerts |

## Grafana datasources — statisch geconfigureerd

Datasources worden **niet** via de sidecar aangemaakt, maar statisch geprovisiond via een values-bestand dat Ansible voor de Helm install rendert:

```yaml
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Prometheus
        uid: prometheus
        type: prometheus
        url: http://prometheus-kube-prometheus-prometheus.monitoring:9090
        isDefault: true
      - name: Alertmanager
        uid: alertmanager
        type: alertmanager
        url: http://prometheus-kube-prometheus-alertmanager.monitoring:9093
```

Beide URLs zijn in-cluster DNS-namen — Grafana praat niet via NodePort naar buiten. De datasource-sidecar is uitgeschakeld (`enabled: false`) omdat die bij elke restart datasources kan dupliceren.

## Grafana dashboards — wel via sidecar

Voor dashboards is de sidecar wél ingeschakeld. Hij scant alle namespaces op ConfigMaps met het label `grafana_dashboard=1` en importeert die automatisch zonder Grafana te herstarten:

```yaml
sidecar:
  dashboards:
    enabled: true
    label: grafana_dashboard
    labelValue: "1"
    searchNamespace: ALL
```

Het Orange Platform dashboard wordt als ConfigMap aangemaakt:

```bash
kubectl -n monitoring create configmap orange-platform-dashboard \
  --from-file=orange-platform.json=...
kubectl -n monitoring label configmap orange-platform-dashboard grafana_dashboard=1
```

Eigen dashboards toevoegen: maak een ConfigMap aan met het label `grafana_dashboard=1` in willekeurig welke namespace — de sidecar importeert hem automatisch.

## Config-reloader NodePorts — expliciet gepind

Prometheus en Alertmanager exposen intern poort 8080 voor hun config-reloader sidecar. k3s wijst hier bij elke greenfield-deploy een willekeurige NodePort aan, die kan conflicteren met andere services. Ansible patcht dit na de Helm install:

```bash
# zoek de index van poort 8080 in de service-definitie
IDX=$(kubectl get svc prometheus-kube-prometheus-prometheus -o json | \
  python3 -c "import sys,json; s=json.load(sys.stdin); \
  print(next(i for i,p in enumerate(s['spec']['ports']) if p['port']==8080))")
# patch de nodePort naar de vaste waarde
kubectl patch svc ... --type=json \
  -p='[{"op":"replace","path":"/spec/ports/<IDX>/nodePort","value":30091}]'
```

| Service | Vaste NodePort |
|---|---|
| Prometheus config-reloader | `30091` |
| Alertmanager config-reloader | `30092` |

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `prometheus_stack_chart_version` | `"65.1.1"` | Helm-chartversie (gepind) |
| `prometheus_namespace` | `"monitoring"` | Kubernetes namespace |
| `prometheus_retention` | `"7d"` | Hoe lang Prometheus data bewaart |
| `prometheus_storage_size` | `"5Gi"` | Opslag voor Prometheus TSDB |
| `grafana_storage_size` | `"2Gi"` | Opslag voor Grafana |
| `alertmanager_storage_size` | `"2Gi"` | Opslag voor Alertmanager |
| `prometheus_install_timeout` | `"15m"` | Timeout voor Helm install (lang vanwege veel CRDs) |
| `grafana_port` | — | NodePort voor Grafana (uit group_vars, `30083`) |
| `prometheus_port` | — | NodePort voor Prometheus (uit group_vars, `30090`) |
| `alertmanager_port` | — | NodePort voor Alertmanager (uit group_vars, `30085`) |
| `prometheus_reloader_port` | — | Gepinde NodePort voor Prometheus reloader (`30091`) |
| `alertmanager_reloader_port` | — | Gepinde NodePort voor Alertmanager reloader (`30092`) |

## Afhankelijkheden

- `longhorn` is geïnstalleerd (vereist voor PVCs).
- `namespaces` heeft de `monitoring`-namespace aangemaakt.

## Configuratie nakijken in een live systeem

**Grafana UI:**
```
http://<k3s_server_ip>:30083
gebruiker: admin
wachtwoord: zelfde als Gitea admin (staat in /root/platform-summary.txt)
```

**Actieve Helm values:**
```bash
helm get values prometheus -n monitoring
```

**Datasources en dashboards (ConfigMaps):**
```bash
kubectl -n monitoring get configmap prometheus-grafana -o yaml
kubectl get configmap -A -l grafana_dashboard=1
```

**Prometheus scrape targets en rules:**
```
http://<k3s_server_ip>:30090/targets   ← welke endpoints gescraped worden
http://<k3s_server_ip>:30090/config    ← volledige scrape-configuratie
http://<k3s_server_ip>:30090/rules     ← alerting rules
```

**Alle resources in de monitoring namespace:**
```bash
kubectl -n monitoring get all
kubectl -n monitoring get pvc          ← persistent volumes (Longhorn)
```

## Architectuurkeuzes en alternatieven

| Keuze | Alternatief | Trade-off |
|---|---|---|
| Één chart voor alle drie componenten | Prometheus, Grafana en Alertmanager apart installeren | De community chart is de standaard aanpak; apart installeren geeft meer controle maar veel meer configuratiewerk |
| Datasources statisch | Datasource-sidecar | Sidecar kan datasources dupliceren bij herstart; statisch is deterministisch |
| Dashboards via sidecar | Dashboards statisch in Helm values | Sidecar maakt het eenvoudig nieuwe dashboards toe te voegen zonder Helm upgrade |
| NodePort | Ingress voor Grafana | NodePort is eenvoudiger; Grafana achter ingress vereist subpath-configuratie |
| Chartversie gepind (`65.1.1`) | Floating versie | Chart installeert tientallen CRDs; een onverwachte upgrade kan CRD-schema's breken |

## Dashboard

Het bestand `files/orange-platform-dashboard.json` bevat een vooraf geconfigureerd Grafana-dashboard met:
- CPU/memory gebruik per node.
- Longhorn volume-status.
- Pod-status voor customer-instanties.
