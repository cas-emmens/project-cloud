# longhorn

Installeert Longhorn, een gedistribueerd block-storage systeem voor Kubernetes. Longhorn repliceert data over meerdere nodes zodat opslag beschikbaar blijft als een node uitvalt.

**Gebruikt door:** `bootstrap-platform.yml`

## Wat doet deze rol?

1. Voegt de Longhorn Helm-repo toe.
2. Installeert Longhorn via Helm in de `longhorn-system` namespace.
3. Schakelt Longhorn uit als **default** StorageClass — wij specificeren `storageClassName: longhorn` expliciet in elke PVC, zodat er geen verwarring is over welke storage class wordt gebruikt.

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `longhorn_namespace` | `"longhorn-system"` | Kubernetes namespace |
| `longhorn_chart_version` | `""` | Pinnen op specifieke versie; leeg = nieuwste |
| `longhorn_install_timeout` | `"10m"` | Timeout voor Helm install |

## Afhankelijkheden

- `helm` is geïnstalleerd.
- **`open-iscsi` en `iscsid` draaien op alle nodes** (gezet door `node-prepare`).
- Elke node heeft minimaal **100 GB** vrije schijfruimte. Longhorn weigert te starten op nodes met minder.

## Opmerkingen

- Longhorn verdeelt volumes standaard over 3 replica's (één per node). Dit beschermt tegen schijfuitval maar kost 3× de opslag.
- **Replica count per PVC**: voor development/test is 1 replica voldoende en veel sneller. Kan worden aangepast in de Longhorn-UI of via storage class parameters.
- Longhorn is langzamer dan local-path storage omdat data via het netwerk wordt gesynchroniseerd. Voor een productiesysteem is dit de juiste keuze; voor een test-omgeving kan het bouwtijden verlengen.
