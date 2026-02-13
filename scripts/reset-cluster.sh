#!/usr/bin/env bash
# reset-cluster.sh <environment> - Reset complet d'un cluster K3s
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="${SCRIPT_DIR}/../ansible"
ENV="${1:-}"

if [[ "$ENV" != "staging" && "$ENV" != "production" ]]; then
  echo "Usage: $0 <staging|production>"
  exit 1
fi

cd "$ANSIBLE_DIR"
set -a
source ".env.${ENV}"
set +a

reset_host() {
  local host="$1"
  local ssh_key="$2"
  local ssh_user="$3"

  echo "→ Connexion a ${host}..."
  ssh -i "${ssh_key}" "${ssh_user}@${host}" "\
    echo '  [1/5] Desinstallation de K3s...'; \
    if sudo /usr/local/bin/k3s-uninstall.sh 2>/dev/null; then \
      echo '        K3s desinstalle'; \
    elif sudo /usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null; then \
      echo '        K3s agent desinstalle'; \
    else \
      echo '        K3s non installe (skip)'; \
    fi; \
    echo '  [2/5] Suppression de /etc/rancher /var/lib/rancher /var/lib/longhorn...'; \
    sudo rm -rf /etc/rancher /var/lib/rancher /var/lib/longhorn; \
    echo '  [3/5] Suppression de /opt/cni /etc/cni...'; \
    sudo rm -rf /opt/cni /etc/cni; \
    echo '  [4/5] Suppression de helm...'; \
    sudo rm -f /usr/local/bin/helm; \
    echo '  [5/5] Suppression du kubeconfig local...'; \
    rm -f ~/.kube/config; \
    echo '  Nettoyage distant termine.'"
}

case "$ENV" in
  staging)
    STAGING_HOST="${STAGING_HOST:-10.0.1.10}"
    STAGING_SSH_KEY="${STAGING_SSH_KEY:-~/.ssh/staging_key}"
    reset_host "$STAGING_HOST" "$STAGING_SSH_KEY" "ubuntu"
    echo "→ Suppression de kubeconfig-staging.yaml local..."
    rm -f kubeconfig-staging.yaml
    echo "✓ Cluster staging reinitialise. Relancez: task infra:staging"
    ;;
  production)
    PROD_MASTER_HOST="${PROD_MASTER_HOST:-10.0.2.10}"
    PROD_SSH_KEY="${PROD_SSH_KEY:-~/.ssh/production_key}"
    for HOST in "${PROD_MASTER_HOST}" "${PROD_WORKER1_HOST:-}" "${PROD_WORKER2_HOST:-}" "${PROD_WORKER3_HOST:-}"; do
      [ -z "${HOST}" ] && continue
      reset_host "$HOST" "$PROD_SSH_KEY" "debian"
    done
    echo "→ Suppression de kubeconfig-production.yaml local..."
    rm -f kubeconfig-production.yaml
    echo "✓ Cluster production reinitialise. Relancez: task infra:production"
    ;;
esac
