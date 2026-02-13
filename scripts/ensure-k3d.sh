#!/usr/bin/env bash
# ensure-k3d.sh - Verifie et demarre le cluster k3d local si necessaire
set -euo pipefail

CLUSTER_NAME="atlas-local"

# Verifier si k3d est installe
if ! command -v k3d &> /dev/null; then
  echo "❌ k3d n'est pas installe. Installez-le avec: brew install k3d"
  exit 1
fi

# Verifier si le cluster existe
if k3d cluster list | grep -q "^${CLUSTER_NAME}"; then
  # Le cluster existe, verifier s'il est running
  if k3d cluster list | grep "^${CLUSTER_NAME}" | grep -q "running"; then
    echo "✓ Cluster k3d '${CLUSTER_NAME}' est deja en cours d'execution"
  else
    echo "🚀 Demarrage du cluster k3d '${CLUSTER_NAME}'..."
    k3d cluster start "${CLUSTER_NAME}"
    echo "✓ Cluster k3d '${CLUSTER_NAME}' demarre"
  fi
else
  echo "📦 Creation du cluster k3d '${CLUSTER_NAME}'..."
  k3d cluster create "${CLUSTER_NAME}" \
    --api-port 6550 \
    --port "80:80@loadbalancer" \
    --port "443:443@loadbalancer" \
    --agents 0 \
    --k3s-arg "--disable=traefik@server:*" \
    --k3s-arg "--disable=servicelb@server:*" \
    --k3s-arg "--disable=local-storage@server:*" \
    --k3s-arg "--flannel-backend=none@server:*" \
    --k3s-arg "--disable-network-policy@server:*"
  echo "✓ Cluster k3d '${CLUSTER_NAME}' cree et demarre"
fi

# Merger le kubeconfig pour que kubectl fonctionne
k3d kubeconfig merge "${CLUSTER_NAME}" --kubeconfig-merge-default

# Attendre que l'API soit accessible (le node sera NotReady tant que le CNI n'est pas installe)
echo "⏳ Attente que l'API Kubernetes soit accessible..."
until kubectl get nodes &> /dev/null; do
  sleep 2
done
echo "✓ Cluster k3d pret (API accessible)"
