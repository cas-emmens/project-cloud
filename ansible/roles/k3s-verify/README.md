# k3s-verify

Verifieert dat alle k3s-nodes `Ready` zijn na de installatie. Geeft een leesbare samenvatting van de cluster-status.

**Gebruikt door:** `install-k3s.yml` (play 4: `hosts: k3s_server`)

## Wat doet deze rol?

1. Voert `kubectl get nodes` uit en toont de output.
2. Telt het aantal nodes met status `Ready` en vergelijkt met het verwachte aantal (3).
3. Faalt als niet alle nodes `Ready` zijn.

## Variabelen

Geen. Het verwachte aantal nodes (3) is hard-coded op basis van de platformarchitectuur.

## Afhankelijkheden

- `k3s-server` en `k3s-agent` zijn uitgevoerd.
- Alle drie nodes zijn bereikbaar vanuit de servernode.

## Opmerkingen

- Deze rol is bewust minimaal — verificatie na installatie is een aparte verantwoordelijkheid.
- Bij een mislukte verificatie: controleer of de agentnode de servernode kan bereiken op poort 6443.
