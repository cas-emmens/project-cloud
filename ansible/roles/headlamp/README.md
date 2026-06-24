# headlamp

Installeert Headlamp, een webgebaseerde Kubernetes-GUI. Headlamp geeft een visueel overzicht van alle resources in het cluster: pods, services, deployments, volumes, etc.

**Gebruikt door:** `bootstrap-platform.yml`

## Wat doet deze rol?

1. Voegt de Headlamp Helm-repo toe.
2. Installeert Headlamp via Helm met een NodePort-service.
3. **Pinned NodePort**: het Headlamp-chart respecteert `service.nodePort` niet. k3s wijst daardoor een willekeurige poort toe. Deze rol patcht de service expliciet naar `headlamp_port` zodat het adres stabiel blijft.
4. Maakt een `headlamp-admin` ServiceAccount + ClusterRoleBinding (`cluster-admin`) aan.
5. Maakt een token-secret aan die Kubernetes automatisch vult met een long-lived token.
6. Leest het token uit en slaat het op in `/tmp/headlamp-token.txt` lokaal.

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `headlamp_chart_version` | `"0.27.0"` | Helm-chartversie |
| `headlamp_namespace` | `"kube-system"` | Kubernetes namespace (standaard voor cluster-tools) |
| `headlamp_port` | — | NodePort (uit group_vars, bv. 30086) |

## Afhankelijkheden

- `helm` is geïnstalleerd.

## Inloggen in Headlamp

1. Open `http://<server-ip>:<headlamp_port>`.
2. Kies "Token" als authenticatiemethode.
3. Plak de inhoud van `/tmp/headlamp-token.txt`.

Of haal het token direct op:
```bash
kubectl -n kube-system get secret headlamp-admin-token -o jsonpath='{.data.token}' | base64 -d
```

## Opmerkingen

- **ClusterRoleBinding `cluster-admin`** geeft volledige toegang tot het cluster. Dit is bewust gekozen voor een beheerders-dashboard in een single-tenant platform. In productie met meerdere teams zou je fijnmaziger RBAC willen.
- Het token-secret (`type: kubernetes.io/service-account-token`) is een "legacy" format dat Kubernetes automatisch vult. Moderne Kubernetes gebruikt kortlevende tokens via `kubectl create token`, maar voor een permanente GUI-toegang is een long-lived token praktischer.
