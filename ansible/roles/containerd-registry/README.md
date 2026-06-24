# containerd-registry

Configureert containerd op alle k3s-nodes om de Gitea container registry te vertrouwen als onbeveiligde (HTTP) registry. Zonder deze configuratie weigeren nodes images te pullen van een HTTP-registry.

**Gebruikt door:** `setup-cicd-pipeline.yml` (play 1: `hosts: k3s_server:k3s_agents`)

## Wat doet deze rol?

1. Zorgt dat `/etc/rancher/k3s/` bestaat.
2. Schrijft `/etc/rancher/k3s/registries.yaml` met een mirror-configuratie voor `<server-ip>:<gitea_http_port>`.
3. Als de configuratie is gewijzigd: herstart `k3s` (op de server) of `k3s-agent` (op agents).
4. Wacht tot k3s weer `Ready` is na een herstart.

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `k3s_server_ip` | — | IP van de server (uit inventory) |
| `gitea_http_port` | — | Poort van de Gitea registry (uit group_vars) |

## Afhankelijkheden

- Gitea draait en de registry is bereikbaar.
- `bootstrap-platform.yml` is succesvol uitgevoerd (Phase 3).

## Hoe werkt het?

`registries.yaml` vertelt containerd: "als je een image wilt pullen van `<server-ip>:<gitea_http_port>`, gebruik dan dit HTTP-endpoint." Containerd accepteert normaal alleen HTTPS-registries; de mirror-configuratie maakt een uitzondering voor dit specifieke adres.

```yaml
mirrors:
  "192.168.1.100:30080":
    endpoint:
      - "http://192.168.1.100:30080"
```

## Opmerkingen

- **Idempotent**: de configuratie wordt alleen gewijzigd als de bestandsinhoud verandert. k3s wordt dus niet onnodig herstart bij re-runs.
- **Alle nodes moeten worden geconfigureerd**: niet alleen de servernode. Pods kunnen op elke worker-node draaien — als die node de registry niet kent, mislukt de image-pull.
- De herstart van k3s duurt 30-60 seconden. De rol wacht tot de node weer `Ready` is voordat Phase 4 verdergaat.
