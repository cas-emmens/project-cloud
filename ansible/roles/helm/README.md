# helm

Installeert de Helm 3 package-manager op de k3s-servernode. Helm is het standaard tool om Kubernetes-applicaties te installeren via zogenaamde "charts" (pakketbeschrijvingen).

**Gebruikt door:** `bootstrap-platform.yml` (eerste rol)

## Wat doet deze rol?

1. Controleert of `/usr/local/bin/helm` al bestaat.
2. Installeert Helm via het officiële installatiescript als het nog niet aanwezig is.

## Variabelen

Geen.

## Afhankelijkheden

- k3s is geïnstalleerd en `kubectl` werkt.
- Internetverbinding naar `raw.githubusercontent.com`.

## Opmerkingen

- De installatie is idempotent: bestaat Helm al, dan wordt het script niet opnieuw uitgevoerd.
- Helm 3 heeft geen aparte servercomponent (Tiller) meer nodig, in tegenstelling tot Helm 2.
- Alle volgende rollen in `bootstrap-platform.yml` gebruiken Helm om hun charts te installeren.
