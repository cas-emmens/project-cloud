# Changelog

## feat/mailpit-alertmanager

Doel: Alertmanager volledig configureren met email routing via Mailpit, NodePort conflicten oplossen en testinfrastructuur toevoegen.

---

### Nieuwe features

**Mailpit mail catcher**

Mailpit wordt als lightweight SMTP mail catcher gedeployd in de `mailpit` namespace. Alle alert emails van Alertmanager worden opgevangen en zijn zichtbaar in de Mailpit web UI. Geen externe SMTP dependency nodig.

- SMTP op NodePort `30025` (in-cluster: `mailpit.mailpit.svc.cluster.local:1025`)
- Web UI op NodePort `30026`

**Alertmanager email routing**

Alertmanager geconfigureerd met SMTP routing naar Mailpit. Alle alerts (inclusief Watchdog als heartbeat) gaan naar `alert_receiver_email` (default: `admin@orangekuma.local`). De configuratie wordt automatisch gezet via een Kubernetes Secret in Phase 3.

**setup-env role en playbook**

Nieuw playbook `ansible/playbooks/setup-env.yml` met bijbehorende role `ansible/roles/setup-env/` schrijft `K3S_SERVER_IP` vanuit de inventory naar `/root/.env` op de control node. Na uitvoeren: `source ~/.env`.

```bash
ansible-playbook ansible/playbooks/setup-env.yml -i ansible/inventories/test/inventory.yml
source ~/.env
```

**Alertmanager test script**

`tests/test-alertmanager.sh` test de volledige Alertmanager → Mailpit keten via twee scenario's:
1. Directe alert injectie via de Alertmanager API
2. Watchdog check — bewijst dat de Prometheus → Alertmanager → mail keten actief is

Vereist `K3S_SERVER_IP` in de shell (zie setup-env).

---

### Fixes

**Git clone/push via delegate_to localhost**

De `Clone from GitHub and push to Gitea` taak in `setup-cicd-pipeline.yml` werd uitgevoerd op de k3s-server, maar `git` was niet geïnstalleerd op een greenfield VM. De taak is gemigreerd naar `delegate_to: localhost` (de Ansible control node) zodat de k3s-server geen git dependency heeft. De push URL gebruikt nu `{{ k3s_server_ip }}` in plaats van `localhost`.

**NodePort conflicten opgelost**

`kube-prometheus-stack` en ArgoCD exposeren extra service poorten als willekeurige NodePorts. Deze kunnen andere services blokkeren op een greenfield deploy. Alle NodePorts zijn nu expliciet gepind:

| Service | Poort | NodePort |
|---|---|---|
| Prometheus config-reloader | 8080 | 30091 |
| Alertmanager config-reloader | 8080 | 30092 |
| ArgoCD HTTPS | 443 | 30443 |

**Semaphore branch ingesteld op development**

`semaphore_repo_branch` voor de `test` en `acc` inventory gezet op `development` zodat Semaphore de actuele werkbranch gebruikt.

