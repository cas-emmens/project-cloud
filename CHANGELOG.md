# Changelog

## feat/test-environment-inventory

Doel: de deployment scripts geschikt maken voor meerdere omgevingen (Hanze + test),
zonder de bestaande configuratie te breken.

---

### Nieuwe features

**Multi-environment inventory structuur** (`f9a304f`)

De losse `ansible/inventory.yml` en `ansible/group_vars/all.yml` zijn vervangen door een
directory-structuur met een inventory per omgeving:

```
ansible/inventories/
├── hanze/   ← originele Hanze Proxmox cluster (10.24.36.x)
└── test/    ← test Proxmox cluster (10.24.35.x)
```

Elke omgeving heeft zijn eigen `inventory.yml` en `group_vars/all.yml`. Playbooks
worden aangeroepen met `-i inventories/test` of `-i inventories/hanze`.

---

### Fixes

**Root-level group_vars verwijderd** (`682d051`)

`ansible/group_vars/all.yml` is verwijderd. Ansible laadt playbook-directory group_vars
met hogere prioriteit dan inventory group_vars, waardoor de root-level file altijd de
omgevingsspecifieke waarden zou overschrijven. De inhoud leeft nu uitsluitend in de
per-omgeving directories.

**Test inventory compleet gemaakt** (`07a9c87`)

De test inventory miste de `proxmox_nodes` groep. Phase 1 (`create-vms.yml`) target
deze groep om VMs aan te maken via `qm`-commando's op de Proxmox nodes. Zonder deze
groep faalde de playbook met "no hosts matched".

**Hardcoded IPs in management tool manifest vervangen** (`147b2aa`)

`k8s/management-tool/deployment.yml` bevatte hardcoded `10.24.36.10` IPs in de
ConfigMap en de image-referentie. Het bestand is omgezet naar een Jinja2 template
(`deployment.yml.j2`). De playbook gebruikt nu `ansible.builtin.template` in plaats
van `ansible.builtin.copy` zodat variabelen worden ingevuld voor het manifest naar
de server wordt gestuurd.

**Drone pod-selectie robuust gemaakt** (`5d832f1` → `7dc45e2` → `ce54d3c` → `11a9809`)

Bij een herrun van Phase 4 bleven afgeronde (`Succeeded`) Drone pods zichtbaar naast
de nieuwe Running pod. De playbook selecteerde dan de verkeerde pod voor `kubectl exec`,
wat leidde tot "cannot exec into a completed pod". Meerdere aanpakken geprobeerd:

- `--field-selector=status.phase=Running` → werkt niet betrouwbaar in k3s
- jsonpath filter `?(@.status.phase=="Running")` → Ansible escapet de `"` naar `\"`,
  waardoor kubectl een lege string teruggeeft
- **Uiteindelijke fix:** `--no-headers | grep Running | awk '{print $1}' | head -1`
  — puur tekstfiltering, geen quotes, werkt in alle omgevingen

**sqlite3 output-onderdrukking verwijderd** (`f5fe3ac`)

De `apk add sqlite` installatie had `>/dev/null 2>&1` waardoor fouten onzichtbaar waren.
Verwijderd zodat installatiefouten direct zichtbaar zijn in de Ansible output.

**Semaphore repo branch en cluster IP configureerbaar** (`89539d1`)

Semaphore haalde de playbook-code altijd van de hardcoded GitHub `main` branch. Voor de
test-omgeving moet dit de `feat/test-environment-inventory` branch zijn. Opgelost door:

- `semaphore_repo_url` en `semaphore_repo_branch` toe te voegen aan beide `group_vars`
- De hardcoded waarden in `bootstrap-platform.yml` te vervangen door deze variabelen
- De Semaphore environment JSON uitgebreid met `k3s_server_ip` en `domain_suffix` zodat
  `provision-customer.yml` de juiste omgevingswaarden krijgt in plaats van de Hanze IPs
  uit de GitHub main branch

**Python interpreter warning onderdrukt** (`c026b65` → `574e5e1`)

Ansible gaf een waarschuwing over automatische Python interpreter-detectie. Opgelost
door `ansible_python_interpreter: auto_silent` toe te voegen aan beide `group_vars` en
aan de Semaphore environment JSON.

**Test proxmox nodes hernoemd** (`0cb3bc8`)

Nodes in de test inventory hernoemd van `CE01/CE02/CE3` naar `pve2/pve3/pve4` zodat
de naam overeenkomt met het laatste octet van het IP-adres (`10.24.35.2` → `pve2`).

**group_vars gesplitst in gedeeld en omgevingsspecifiek** (`9ffb4a4` → `63ed486`)

`ansible/group_vars/all.yml` is her-aangemaakt met uitsluitend gedeelde variabelen
(poorten, Gitea-credentials). De inventory group_vars bevatten alleen
omgevingsspecifieke waarden (`k3s_server_ip`, `domain_suffix`, `dns_servers`,
`semaphore_repo_branch`).

Reden: `provision-customer.yml` draait vanuit Semaphore zonder inventory en laadt
vars via `vars_files: ../group_vars/all.yml`. Zonder dit bestand ontbraken poorten
en credentials, wat leidde tot `gitea_http_port is undefined`. De gedeelde vars
moeten ook in de inventory group_vars staan omdat Ansible die file niet automatisch
laadt voor reguliere playbooks (Ansible zoekt group_vars in de inventory-directory
en de playbook-directory, niet in `ansible/`).

**deploy.sh omgevingsonafhankelijk gemaakt** (`4245182` → `aa7f9bd` → `2762dcd`)

- `--inventory` flag toegevoegd (default: `inventories/hanze`), doorgegeven aan alle
  `ansible-playbook` aanroepen inclusief `destroy-vms.yml`
- `clear_vm_host_keys` leest VM-IPs dynamisch uit `vm_ip:` velden in de inventory
  in plaats van hardcoded `10.24.36.x` adressen
- `hanze_prox.pub` toegevoegd als eerste optie in SSH-key detectie (Proxmox genereert
  altijd `id_rsa` wat op test-omgevingen de verkeerde key zou selecteren)

**Phase 4 summary leesbaar gemaakt in Semaphore** (`88bb5f9`)

De `msg: |` multiline block werd door Semaphore als JSON-string getoond met letterlijke
`\n` tekens. Vervangen door een YAML-lijst zodat elke URL op een eigen regel staat.
Alle service URLs toegevoegd die eerder ontbraken (Argo CD, Semaphore, Grafana,
Headlamp, Prometheus).

**Longhorn distributed storage toegevoegd** (`2ec8102` → `f9b0847`)

`local-path` (node-lokale opslag) vervangen door Longhorn (gedistribueerde opslag
met replicatie over nodes). Bij een node-uitval kunnen pods op een andere node
herstarten met hun data intact.

- `install-k3s.yml`: `open-iscsi` en `qemu-guest-agent` installeren op alle nodes
- `bootstrap-platform.yml`: Longhorn Helm chart toegevoegd vóór de andere services,
  `local-path` als default StorageClass uitgezet
- Alle 7 `local-path` referenties vervangen door `longhorn`

**Documentatie bijgewerkt** (`27a3fe1`)

- Architectuurdiagram toegevoegd (`docs/architecture.md`) met infrastructuur,
  services en beide flows (GitOps + CI/CD)
- `DOCUMENTATION.md` bijgewerkt: Longhorn als storage-keuze, multi-environment
  inventory structuur, nieuwe deploy.sh syntax, onjuist "Minimal Debian cloud image"
  known issue verwijderd

**Deployment summaries verbeterd** (`9d5775a` → `382ac69`)

Phase 3 summary omgezet van `msg: |` naar lijst (zelfde fix als Phase 4 eerder).
Phase 4 summary uitgebreid tot volledige platformsamenvatting met alle URLs,
gebruikersnamen, wachtwoorden en token-locaties. Na afloop van Phase 4 wordt de
samenvatting ook weggeschreven naar `/root/platform-summary.txt` op de k3s-server
(mode 0600, inclusief tijdstempel) zodat de toegangsgegevens beschikbaar blijven
zonder de Ansible-output terug te hoeven zoeken.

---

### Openstaande punten voor overleg

- Branch mergen naar `main` zodat beide omgevingen de nieuwe inventory-structuur gebruiken
- Na merge: `semaphore_repo_branch` in Hanze `group_vars` blijft `main` — geen actie nodig
- Na merge: de tijdelijke handmatige Semaphore environment-aanpassing op het test-cluster
  vervalt bij de volgende volledige deployment (Phase 3 vult dit dan automatisch in)
