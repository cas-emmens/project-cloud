#!/usr/bin/env bash
# tests/test-alertmanager.sh
# Test de Alertmanager → Mailpit keten via twee scenario's:
#   1. Directe injectie via de Alertmanager API
#   2. Watchdog check — bewijst dat de volledige Prometheus → Alertmanager → mail keten werkt
#
# Vereisten:
#   - K3S_SERVER_IP moet beschikbaar zijn in de shell
#
# Gebruik:
#   source ~/.env
#   ./tests/test-alertmanager.sh

set -euo pipefail

green() { echo -e "\033[32m[PASS]\033[0m $*"; }
red()   { echo -e "\033[31m[FAIL]\033[0m $*"; }
info()  { echo -e "\033[34m[INFO]\033[0m $*"; }
warn()  { echo -e "\033[33m[WARN]\033[0m $*"; }

PASS=0
FAIL=0

# ─── Controleer K3S_SERVER_IP ─────────────────────────────────────────────────
if [ -z "${K3S_SERVER_IP:-}" ]; then
    echo ""
    red "K3S_SERVER_IP is niet ingesteld."
    echo ""
    warn "Voer eerst het volgende uit:"
    echo ""
    echo "    ansible-playbook ansible/playbooks/setup-env.yml -i ansible/inventories/test/inventory.yml"
    echo "    source ~/.env"
    echo ""
    exit 1
fi

ALERTMANAGER="http://${K3S_SERVER_IP}:30085"
MAILPIT="http://${K3S_SERVER_IP}:30026"
ALERT_ID="InjectieTest-$(date +%s)"

echo ""
echo "=== Alertmanager test suite ==="
echo "    Server       : ${K3S_SERVER_IP}"
echo "    Alertmanager : ${ALERTMANAGER}"
echo "    Mailpit      : ${MAILPIT}"
echo ""

# ─── Hulpfuncties ─────────────────────────────────────────────────────────────
wait_for_mail() {
    local label="$1"
    local timeout="${2:-120}"
    local interval=5
    local elapsed=0

    info "Wachten op mail met label '${label}' (max ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        count=$(curl -sf "${MAILPIT}/api/v1/messages" | \
            python3 -c "
import sys, json
data = json.load(sys.stdin)
msgs = data.get('messages', [])
print(sum(1 for m in msgs if '${label}' in m.get('Subject', '') or '${label}' in str(m.get('Snippet', ''))))
" 2>/dev/null || echo 0)
        if [ "${count}" -gt 0 ]; then
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    return 1
}

# ─── Test 1: Directe injectie ─────────────────────────────────────────────────
echo "--- Test 1: Directe injectie via Alertmanager API ---"
info "Alert injecteren met id '${ALERT_ID}'..."
curl -sf -X POST "${ALERTMANAGER}/api/v2/alerts" \
    -H 'Content-Type: application/json' \
    -d "[{
        \"labels\": {\"alertname\": \"${ALERT_ID}\", \"severity\": \"critical\", \"namespace\": \"test\"},
        \"annotations\": {\"summary\": \"Directe injectie test via test-alertmanager.sh\"}
    }]" > /dev/null

if wait_for_mail "${ALERT_ID}" 90; then
    green "Test 1: mail ontvangen voor directe injectie"
    PASS=$((PASS + 1))
else
    red "Test 1: geen mail ontvangen binnen 90s"
    FAIL=$((FAIL + 1))
fi

echo ""

# ─── Test 2: Watchdog check ───────────────────────────────────────────────────
echo "--- Test 2: Watchdog check (Prometheus → Alertmanager → mail keten) ---"
info "Controleren of Watchdog mail aanwezig is in Mailpit..."

if wait_for_mail "Watchdog" 90; then
    green "Test 2: Watchdog mail aanwezig — volledige keten werkt"
    PASS=$((PASS + 1))
else
    red "Test 2: geen Watchdog mail gevonden — controleer Alertmanager config"
    FAIL=$((FAIL + 1))
fi

echo ""

# ─── Samenvatting ─────────────────────────────────────────────────────────────
echo "=== Resultaat: ${PASS} geslaagd, ${FAIL} mislukt ==="
echo ""

[ $FAIL -eq 0 ]
