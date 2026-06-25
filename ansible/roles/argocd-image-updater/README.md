# argocd-image-updater

Installeert de Argo CD Image Updater, een aanvulling op Argo CD die automatisch nieuwe container-images detecteert en de image-referentie in de Git-repository bijwerkt. Hierdoor worden klant-deployments automatisch bijgewerkt zodra Drone een nieuwe image bouwt.

**Gebruikt door:** `bootstrap-platform.yml` (Phase 3)

## Wat doet deze rol?

1. Voegt de Argo CD Helm-repo toe (dezelfde als voor Argo CD zelf).
2. Installeert de Image Updater via Helm met:
   - `config.applicationsAPIKind=kubernetes` — leest ArgoCD Applications direct uit de Kubernetes API, niet via de ArgoCD API server.
   - `config.argocd.plaintext=true` en `config.argocd.insecure=true` — spreekt de ArgoCD server aan via HTTP (in-cluster, geen TLS nodig).
   - `config.argocd.serverAddress=argocd-server.argocd.svc:80` — in-cluster adres van de ArgoCD server.

Na deze rol draait de Image Updater als pod in de `argocd` namespace, maar zonder registry-configuratie of credentials. De volledige configuratie volgt in Phase 4 via de `argocd-gitops` rol.

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `argocd_image_updater_chart_version` | `"0.11.0"` | Helm-chartversie (gepind) |
| `argocd_image_updater_install_timeout` | `"8m"` | Timeout voor Helm install |

## Afhankelijkheden

- `argocd` is geïnstalleerd en draait.
- `namespaces` heeft de `argocd`-namespace aangemaakt.

## Configuratie (Phase 4)

De daadwerkelijke configuratie gebeurt in de `argocd-gitops` rol, omdat de Gitea PAT pas in Phase 4 beschikbaar is. Die rol voegt toe:

**Secret `gitea-image-updater`** — Gitea-credentials voor registry-toegang en Git write-back:
```yaml
stringData:
  username: <gitea_admin_user>
  password: <argocd-gitops PAT>
```

**ConfigMap `argocd-image-updater-config`** — registry-definitie en Git-identiteit:
```yaml
data:
  registries.conf: |
    registries:
      - name: gitea
        api_url: http://gitea-http.gitea.svc:3000   # in-cluster registry API
        prefix: <k3s_server_ip>:30080               # extern adres voor containerd op nodes
        insecure: true
        credentials: secret:argocd/gitea-image-updater#username:password
        default: true
  git.user: image-updater
  git.email: image-updater@orange-kuma.local
```

Na het aanmaken van deze configuratie herstart de `argocd-gitops` rol de Image Updater pod zodat de nieuwe config actief wordt.

## Hoe werkt de Image Updater?

De Image Updater is geen onderdeel van ArgoCD zelf — het is een afzonderlijk proces dat naast ArgoCD draait. Hij leest de ArgoCD Applications uit Kubernetes, kijkt welke images gevolgd moeten worden (via annotaties op de Application), en schrijft updates terug naar Git.

### Annotaties op de Applications

De twee ArgoCD Applications (`customer-instances` en `test-customers`) dragen annotaties die de Image Updater vertellen wat hij moet doen:

```yaml
annotations:
  argocd-image-updater.argoproj.io/image-list: "kuma=<registry>/<org>/orange-uptime-kuma"
  argocd-image-updater.argoproj.io/kuma.update-strategy: digest
  argocd-image-updater.argoproj.io/kuma.allow-tags: "regexp:^[0-9a-f]{7}$|^latest$"
  argocd-image-updater.argoproj.io/write-back-method: "git:secret:argocd/gitea-customer-instances"
  argocd-image-updater.argoproj.io/git-branch: main
```

| Annotatie | Waarde | Betekenis |
|---|---|---|
| `image-list` | `kuma=...` | Alias `kuma` voor het te volgen image |
| `update-strategy` | `digest` | Update op basis van SHA-digest, niet alleen op tagnaam |
| `allow-tags` | `regexp:^[0-9a-f]{7}$\|^latest$` | Alleen 7-karakter SHA-tags of `latest` worden opgepikt |
| `write-back-method` | `git:secret:...` | Schrijf terug naar Git via de opgegeven credentials |
| `git-branch` | `main` | Commit op de `main` branch |

### Update-strategie: digest

De Image Updater gebruikt `digest` als update-strategie. Dit betekent dat hij niet alleen kijkt of een tagnaam nieuw is, maar of de onderliggende image-digest veranderd is. Zo wordt ook een `latest`-tag opgepikt als er een nieuw image achter zit.

### Write-back via Git

De Image Updater schrijft updates **niet direct naar Kubernetes**, maar commit een gewijzigde image-referentie naar de Gitea repo. ArgoCD detecteert die commit via polling en voert de sync uit.

Het write-back bestand heet `.argocd-source-<appnaam>.yaml` en staat in de root van de repo. Argo CD leest dit bestand samen met de manifesten in `customers/`.

## Volledig stroomschema

```
Drone CI
  │  bouwt image, pusht naar Gitea registry
  │  tag: <git-sha7>
  ▼
Gitea container registry (:30080)
  │
  │  (Image Updater pollt registry API via gitea-http.gitea.svc:3000)
  ▼
ArgoCD Image Updater
  │  detecteert nieuwe digest voor orange-uptime-kuma
  │  kloont customer-instances.git
  │  schrijft nieuwe image-digest naar .argocd-source-customer-instances.yaml
  │  commit + push (als user "image-updater")
  ▼
Gitea repo: customer-instances.git
  │
  │  (ArgoCD pollt repo elke 30s)
  ▼
ArgoCD
  │  detecteert nieuwe commit
  │  sync → rolling update op alle customer-<naam> namespaces
  ▼
Alle klant-pods draaien op nieuwe image
```

## Audit trail en rollback

Elke stap laat een spoor achter:

| Stap | Waar te vinden |
|---|---|
| Image gebouwd | Drone CI build log |
| Image gepusht | Gitea registry tag history |
| Image-referentie bijgewerkt | Git commit op `customer-instances.git` (auteur: `image-updater`) |
| Uitgerold naar cluster | ArgoCD sync history |

Terugdraaien naar een vorig image: `git revert` op de manifest-commit in `customer-instances.git`. ArgoCD reconcilieert automatisch terug.

## Opmerkingen

- De Image Updater draait in de `argocd`-namespace maar is een apart component met eigen credentials.
- **Write-back via Git** (niet direct naar k8s) is de aanbevolen aanpak: elke image-update is een Git-commit, wat een volledige audit trail geeft en rollback eenvoudig maakt.
- De Image Updater heeft twee contactpunten naar Gitea met verschillende URLs: `gitea-http.gitea.svc:3000` voor de registry API (in-cluster), en `<extern IP>:30080` als image-prefix (want containerd op de nodes gebruikt het externe adres om images te pullen).
