# setup-env

Schrijft de `K3S_SERVER_IP` omgevingsvariabele naar een lokaal `.env`-bestand op de Ansible-controllernode (je laptop/PC). Dit bestand kun je daarna `source`-en zodat andere scripts en tools het IP-adres kennen.

**Gebruikt door:** `setup-env.yml`

## Wat doet deze rol?

1. Maakt het `.env`-bestand aan als het nog niet bestaat (permissie `0600` — alleen eigenaar).
2. Schrijft of overschrijft de regel `export K3S_SERVER_IP=<ip>` idempotent met `lineinfile`.
3. Toont een instructie om het bestand te laden: `source ~/.env`.

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `env_file` | `/root/.env` | Pad naar het lokale .env-bestand |
| `k3s_server_ip` | — | IP van de k3s-servernode (komt uit inventory) |

## Afhankelijkheden

Geen. Dit is altijd de eerste stap.

## Opmerkingen

- Alle taken gebruiken `delegate_to: localhost` — er wordt **niets** op een remote host gedaan.
- `modification_time: preserve` voorkomt dat de timestamp verandert als het bestand al bestaat.
