# ingress-nginx

Installeert de ingress-nginx controller, die inkomend HTTPS-verkeer van buiten het cluster routeert naar de juiste klant-Uptime Kuma instantie op basis van de hostnaam.

**Gebruikt door:** `bootstrap-platform.yml`

## Wat doet deze rol?

1. Voegt de ingress-nginx Helm-repo toe.
2. Installeert ingress-nginx via Helm als LoadBalancer-service met:
   - HTTP (poort 80) **uitgeschakeld**.
   - HTTPS (poort 443) ingeschakeld.

## Variabelen

| Variabele | Default | Omschrijving |
|-----------|---------|--------------|
| `ingress_nginx_chart_version` | `"4.11.3"` | Helm-chartversie |
| `ingress_nginx_namespace` | `"ingress-nginx"` | Kubernetes namespace |

## Afhankelijkheden

- `namespaces` heeft de `ingress-nginx`-namespace aangemaakt.
- `helm` is geïnstalleerd.

## Hoe werkt de routering?

Elke klant krijgt een Ingress-resource met hostnaam `<klantnaam>.<domain_suffix>`. De domain_suffix gebruikt `nip.io` zodat DNS automatisch resolvet naar het server-IP zonder externe DNS-configuratie.

Voorbeeld: `testklant.192.168.1.100.nip.io` resolvet automatisch naar `192.168.1.100`.

De ingress-nginx controller laat HTTPS-verkeer naar `https://testklant.<server-ip>.nip.io` door naar de ClusterIP-service van de klant.

## Opmerkingen

- **Poort 80 is uitgeschakeld** omdat Drone CI een LoadBalancer-service heeft die host-poort 80 bindt via k3s ServiceLB. Een tweede LoadBalancer op poort 80 zou blijven hangen in `Pending`. Poort 443 is vrij.
- **Geen extern DNS nodig** dankzij nip.io — een publieke DNS-service die elk IP-adres in de hostnaam resolvet naar dat IP.
- **Zelfondertekend certificaat**: ingress-nginx genereert automatisch een self-signed TLS-certificaat. Browsers tonen een beveiligingswaarschuwing — dit is acceptabel voor een educatief platform.
- k3s heeft standaard **Traefik** als ingress-controller. Die is uitgeschakeld (`--disable=traefik`) bij de k3s-installatie om conflicten te vermijden.
