# mailpit

Deployt Mailpit, een SMTP-catcher die alle uitgaande e-mails opvangt en presenteert in een webinterface. In dit platform vangt Mailpit de Alertmanager-meldingen op zodat alerts te zien zijn zonder een extern e-mailaccount nodig te hebben.

**Gebruikt door:** `bootstrap-platform.yml`

## Wat doet deze rol?

Deployt via `kubectl apply`:
- **Deployment**: één Mailpit-pod met twee poorten (SMTP op 1025, webinterface op 8025).
- **Service** (NodePort): bereikbaar op `<server-ip>:<mailpit_smtp_port>` (SMTP) en `<server-ip>:<mailpit_web_port>` (web).

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `mailpit_namespace` | `"mailpit"` | Kubernetes namespace |
| `mailpit_image` | `"axllent/mailpit:v1.21.6"` | Container-image |
| `mailpit_smtp_port` | — | NodePort voor SMTP (uit group_vars, bv. 30025) |
| `mailpit_web_port` | — | NodePort voor webinterface (uit group_vars, bv. 30026) |

## Afhankelijkheden

- `namespaces` heeft de `mailpit`-namespace aangemaakt.

## Hoe werkt het?

Alertmanager is geconfigureerd om e-mails te sturen naar `mailpit.mailpit.svc.cluster.local:1025` (de in-cluster service). Mailpit accepteert alle SMTP-verbindingen zonder authenticatie en toont de ontvangen berichten in de webinterface op `http://<server-ip>:<mailpit_web_port>`.

## Opmerkingen

- Mailpit slaat geen berichten op na een herstart (geen PVC). Dit is bewust — het is een tijdelijke catcher voor development/test.
- **Niet voor productie**: in productie wil je een echte SMTP-relay (SendGrid, Mailgun, of eigen mailserver).
