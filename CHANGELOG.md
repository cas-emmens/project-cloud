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

---

## feat/test-environment-inventory

Doel: de deployment scripts geschikt maken voor meerdere omgevingen (Hanze + test + acc),
zonder de bestaande configuratie te breken.

---

### Nieuwe features

**Multi-environment inventory structuur**

De losse `ansible/inventory.yml` en `ansible/group_vars/all.yml` zijn vervangen door een
directory-structuur met een inventory per omgeving:

```
ansible/inventories/
├── hanze/   ← originele Hanze Proxmox cluster (10.24.36.x)
├── test/    ← test Proxmox cluster (10.24.35.x)
└── acc/     ← acceptatie Proxmox cluster (10.24.39.x)
```

Elke omgeving heeft zijn eigen `inventory.yml` en `group_vars/all.yml`. Playbooks
worden aangeroepen met `-i inventories/test` of `-i inventories/hanze`.

**Longhorn distributed storage**

`local-path` (node-lokale opslag) vervangen door Longhorn (gedistribueerde opslag
met replicatie over nodes). Bij een node-uitval kunnen pods op een andere node
herstarten met hun data intact.

- `install-k3s.yml`: `open-iscsi` en `qemu-guest-agent` installeren op alle nodes
- `bootstrap-platform.yml`: Longhorn Helm chart toegevoegd vóór de andere services,
  `local-path` als default StorageClass uitgezet
- Alle `local-path` referenties vervangen door `longhorn`

Longhorn maakt nieuwe volumes aan als `root:root`. Containers die als niet-privileged
user draaien hebben een `fsGroup` instelling nodig: de kubelet chownt de volume-mount
dan naar de juiste GID zodat de container schrijfrechten heeft.

- Semaphore: `fsGroup: 1001`
- Uptime Kuma: `fsGroup: 1000`
- Drone Server: geen `fsGroup` nodig, draait als root

Deployments met een ReadWriteOnce PVC krijgen `strategy: Recreate` om een RollingUpdate
deadlock te voorkomen.

---

### Fixes

**Root-level group_vars verwijderd**

`ansible/group_vars/all.yml` is verwijderd. Ansible laadt playbook-directory group_vars
met hogere prioriteit dan inventory group_vars, waardoor de root-level file altijd de
omgevingsspecifieke waarden zou overschrijven. De inhoud leeft nu uitsluitend in de
per-omgeving directories.

**DNS-configuratie gecorrigeerd**

Cloud-init stelde de gateway (`10.24.35.1` / `10.24.36.1`) in als nameserver. De
gateways doen geen DNS-forwarding, waardoor `apt` op verse VMs geen pakketbronnen
kon bereiken en het `apt-get update` proces vastliep.

- `nameserver` in alle inventories gewijzigd naar `1.1.1.1`
- DNS-verificatietaak toegevoegd als eerste stap in `install-k3s.yml` via `getent
  hosts deb.debian.org` met 12 pogingen

**VM disk vergroot naar 100GB**

VM schijfgrootte in `create-vms.yml` verhoogd van 25GB naar 100GB. Longhorn
maakt standaard 3 replicas per volume. Met 25GB schijven liep de beschikbare ruimte
per node vol waardoor Longhorn geen nieuwe replicas kon aanmaken.

> ⚠️ **Let op:** elke Proxmox node heeft minimaal 100GB vrije local-lvm ruimte
> nodig. Controleer vóór deployment met `vgs` op de Proxmox nodes.

**Drone pod-selectie robuust gemaakt**

Bij een herrun bleven afgeronde (`Succeeded`) Drone pods zichtbaar naast de nieuwe
Running pod. De playbook selecteerde dan de verkeerde pod voor `kubectl exec`. Fix:
`--no-headers | grep Running | awk '{print $1}' | head -1` — puur tekstfiltering.

**Semaphore repo branch en cluster IP configureerbaar**

`semaphore_repo_url` en `semaphore_repo_branch` toegevoegd aan alle `group_vars`.
De Semaphore environment JSON uitgebreid met `k3s_server_ip` en `domain_suffix`.

**deploy.sh omgevingsonafhankelijk gemaakt**

- `--inventory` flag toegevoegd (default: `inventories/hanze`), doorgegeven aan alle
  `ansible-playbook` aanroepen
- `clear_vm_host_keys` leest VM-IPs dynamisch uit de inventory

**Hardcoded IPs in management tool manifest vervangen**

`k8s/management-tool/deployment.yml` omgezet naar Jinja2 template (`deployment.yml.j2`)
zodat `k3s_server_ip` variabelen worden ingevuld voor het manifest naar de server wordt
gestuurd.

**Phase 4 en Phase 3 summaries leesbaar gemaakt in Semaphore**

`msg: |` multiline blocks vervangen door YAML-lijsten zodat elke URL op een eigen
regel staat in de Semaphore output. Phase 4 summary uitgebreid met alle URLs,
gebruikersnamen en wachtwoorden, en weggeschreven naar `/root/platform-summary.txt`.

**Test VM-IDs uitgelijnd met IP-adressen**

VM-IDs in de test inventory gewijzigd naar 210/211/212 zodat het laatste cijfer
overeenkomt met het laatste octet van het IP-adres (`10.24.35.10` → VM 210).

