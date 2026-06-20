#!/usr/bin/env bash
# tests/test-alertmanager.sh
# Test de Alertmanager → Mailpit keten via twee scenario's:
#   1. Directe alert injectie via de Alertmanager API
#   2. Keten test via een echte K8s alert (scale deployment naar 0)
#
# Vereisten:
#   - K3S_SERVER_IP moet beschikbaar zijn in de shell
#   - kubectl geconfigureerd op de control node
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
KUBECTL="ssh debian@${K3S_SERVER_IP} sudo kubectl"

echo ""
echo "=== Alertmanager test suite ==="
echo "    Server       : ${K3S_SERVER_IP}"
echo "    Alertmanager : ${ALERTMANAGER}"
echo "    Mailpit      : ${MAILPIT}"
echo ""

# ─── Hulpfuncties ─────────────────────────────────────────────────────────────
clear_mailpit() {
    curl -sf -X DELETE "${MAILPIT}/api/v1/messages" > /dev/null 2>&1 || true
}

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
clear_mailpit

curl -sf -X POST "${ALERTMANAGER}/api/v2/alerts" \
    -H 'Content-Type: application/json' \
    -d '[{
        "labels": {"alertname": "DirecteInjectieTest", "severity": "critical"},
        "annotations": {"summary": "Directe injectie test via test-alertmanager.sh"}
    }]' > /dev/null

if wait_for_mail "DirecteInjectieTest" 90; then
    green "Test 1: mail ontvangen in Mailpit"
    PASS=$((PASS + 1))
else
    red "Test 1: geen mail ontvangen binnen 60s"
    FAIL=$((FAIL + 1))
fi

echo ""

# ─── Test 2: Keten test via echte K8s alert ───────────────────────────────────
echo "--- Test 2: Keten test via echte K8s alert ---"
clear_mailpit

info "Mailpit deployment schalen naar 0..."
$KUBECTL -n mailpit scale deployment mailpit --replicas=0
info "Wachten op KubeDeploymentReplicasMismatch alert (max 180s)..."

if wait_for_mail "KubeDeployment" 180; then
    green "Test 2: K8s alert mail ontvangen in Mailpit"
    PASS=$((PASS + 1))
else
    red "Test 2: geen alert mail ontvangen binnen 180s"
    FAIL=$((FAIL + 1))
fi

info "Mailpit deployment herstellen naar 1 replica..."
$KUBECTL -n mailpit scale deployment mailpit --replicas=1
$KUBECTL -n mailpit rollout status deployment mailpit --timeout=60s > /dev/null
info "Mailpit is weer beschikbaar op ${MAILPIT}"

echo ""

# ─── Samenvatting ─────────────────────────────────────────────────────────────
echo "=== Resultaat: ${PASS} geslaagd, ${FAIL} mislukt ==="
echo ""

[ $FAIL -eq 0 ]
