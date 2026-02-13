#!/usr/bin/env bash
# ansible-run.sh <environment> [ansible-playbook args...]
# Wrapper qui source le .env et execute ansible-playbook
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="${SCRIPT_DIR}/../ansible"
ENV="${1:-}"

if [[ -z "$ENV" || $# -lt 2 ]]; then
  echo "Usage: $0 <local|staging|production> [ansible-playbook args...]"
  exit 1
fi
shift

cd "$ANSIBLE_DIR"
set -a
source ".env.${ENV}"
set +a

ansible-playbook "$@"
