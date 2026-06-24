#!/usr/bin/env bash
# deploy.sh - One-command greenfield deployment of the Orange Kuma platform
#
# Usage:
#   ./deploy.sh                                   # Full deploy (default: inventories/hanze)
#   ./deploy.sh --inventory inventories/test       # Deploy to test cluster
#   ./deploy.sh --destroy-first                    # Tear down existing, then redeploy
#   ./deploy.sh --phase 2                          # Run from a specific phase (1=VMs, 2=k3s, 3=platform, 4=cicd)
#
# Prerequisites:
#   - Ansible installed on this machine
#   - SSH access to Proxmox nodes defined in the inventory
#   - SSH access to k3s VMs after Phase 1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$SCRIPT_DIR/ansible"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }
info() { echo -e "${BLUE}[i]${NC} $*"; }

# Check prerequisites
check_prereqs() {
    command -v ansible-playbook >/dev/null 2>&1 || err "ansible-playbook not found. Install Ansible first."

    [ -f "$ANSIBLE_DIR/$INVENTORY/inventory.yml" ] || \
        err "Inventory niet gevonden: $ANSIBLE_DIR/$INVENTORY/inventory.yml"

    if [ -z "${PROXMOX_PASSWORD:-}" ]; then
        read -sp "Enter Proxmox root password: " PROXMOX_PASSWORD
        echo
        export PROXMOX_PASSWORD
    fi

    if [ -z "${SSH_PUBLIC_KEY:-}" ]; then
        if [ -f "$HOME/.ssh/hanze_prox.pub" ]; then
            export SSH_PUBLIC_KEY="$(cat "$HOME/.ssh/hanze_prox.pub")"
            log "Using SSH key from ~/.ssh/hanze_prox.pub"
        elif [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
            export SSH_PUBLIC_KEY="$(cat "$HOME/.ssh/id_ed25519.pub")"
            log "Using SSH key from ~/.ssh/id_ed25519.pub"
        elif [ -f "$HOME/.ssh/id_rsa.pub" ]; then
            export SSH_PUBLIC_KEY="$(cat "$HOME/.ssh/id_rsa.pub")"
            log "Using SSH key from ~/.ssh/id_rsa.pub"
        else
            err "No SSH_PUBLIC_KEY set and no key found in ~/.ssh/"
        fi
    fi
}

# Parse arguments
DESTROY_FIRST=false
START_PHASE=1
INVENTORY="inventories/hanze"

while [[ $# -gt 0 ]]; do
    case $1 in
        --destroy-first) DESTROY_FIRST=true; shift ;;
        --phase) START_PHASE="$2"; shift 2 ;;
        --inventory) INVENTORY="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--inventory PATH] [--destroy-first] [--phase N]"
            echo "  --inventory PATH  Inventory directory (default: inventories/hanze)"
            echo "  --destroy-first   Destroy existing VMs before deploying"
            echo "  --phase N         Start from phase N (1=VMs, 2=k3s, 3=platform, 4=cicd)"
            exit 0
            ;;
        *) err "Unknown option: $1" ;;
    esac
done

# Main
cd "$ANSIBLE_DIR"
check_prereqs

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Orange Kuma Platform - Deployment      ║${NC}"
echo -e "${BLUE}║   Phases: 1=VMs 2=k3s 3=platform 4=cicd ║${NC}"
echo -e "${BLUE}║   Inventory: $INVENTORY ${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""

clear_vm_host_keys() {
    info "Clearing stale SSH host keys for VM IPs..."
    VM_IPS=$(grep 'vm_ip:' "$INVENTORY/inventory.yml" | awk '{print $2}' | tr -d '"')
    for ip in $VM_IPS; do
        ssh-keygen -R "$ip" -f "$HOME/.ssh/known_hosts" > /dev/null 2>&1 || true
    done
    log "Host keys cleared."
}

if [ "$DESTROY_FIRST" = true ]; then
    warn "Destroying existing VMs..."
    ansible-playbook -i "$INVENTORY" playbooks/destroy-vms.yml
    log "VMs destroyed. Starting fresh deployment."
    clear_vm_host_keys
    echo ""
fi

TOTAL_START=$(date +%s)

if [ "$START_PHASE" -le 1 ]; then
    info "Phase 1/4: Creating VMs on Proxmox..."
    PHASE_START=$(date +%s)
    clear_vm_host_keys
    ansible-playbook -i "$INVENTORY" playbooks/create-vms.yml
    log "Phase 1 complete ($(( $(date +%s) - PHASE_START ))s)"
    echo ""
fi

if [ "$START_PHASE" -le 2 ]; then
    info "Phase 2/4: Installing k3s cluster..."
    PHASE_START=$(date +%s)
    ansible-playbook -i "$INVENTORY" playbooks/install-k3s.yml
    log "Phase 2 complete ($(( $(date +%s) - PHASE_START ))s)"
    echo ""
fi

if [ "$START_PHASE" -le 3 ]; then
    info "Phase 3/4: Bootstrapping platform services..."
    PHASE_START=$(date +%s)
    ansible-playbook -i "$INVENTORY" playbooks/bootstrap-platform.yml
    log "Phase 3 complete ($(( $(date +%s) - PHASE_START ))s)"
    echo ""
fi

if [ "$START_PHASE" -le 4 ]; then
    info "Phase 4/4: Setting up CI/CD pipeline and deploying management tool..."
    PHASE_START=$(date +%s)
    ansible-playbook -i "$INVENTORY" playbooks/setup-cicd-pipeline.yml
    log "Phase 4 complete ($(( $(date +%s) - PHASE_START ))s)"
    echo ""
fi

TOTAL_TIME=$(( $(date +%s) - TOTAL_START ))
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Deployment complete! (${TOTAL_TIME}s)              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
