# ATLAS Platform - Ansible Deployment

Automated deployment of the ATLAS microservices platform on Kubernetes (K3s/K3D).

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                         ATLAS Platform                           │
├──────────────────────────────────────────────────────────────────┤
│  Phase 0: Hardening (SSH, Firewall, Fail2ban, Auditd)           │
│  Phase 1: Prerequisites + Docker                                 │
│  Phase 2: K3s/K3D + Cilium + Longhorn + Cert-Manager            │
│  Phase 3: Vault + External Secrets                               │
│  Phase 4: PostgreSQL HA + Redis                                  │
│  Phase 5: Authentik + Mattermost + Nextcloud + OnlyOffice + ... │
│  Phase 6: Gitea + ArgoCD                                         │
│  Phase 7: Prometheus + Grafana + Hubble UI                       │
│  Phase 8: Network Policies                                       │
└──────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- **Ansible**: >= 2.15
- **Python**: >= 3.10
- **For local development**: Docker installed
- **For production**: SSH access to target servers (Debian/Ubuntu)

## Quick Start

### 1. Install Ansible Collections

```bash
ansible-galaxy collection install -r requirements.yml
```

### 2. Configure Environment

```bash
# Copy example environment file
cp .env.example .env

# Edit with your values
vim .env

# Source the environment
source .env
```

### 3. Deploy

```bash
# Local development (K3D)
ansible-playbook playbooks/phase-02-k3s-core.yml -i inventories/local

# Production
ansible-playbook playbooks/phase-00-hardening.yml -i inventories/production
ansible-playbook playbooks/phase-01-preparation.yml -i inventories/production
ansible-playbook playbooks/phase-02-k3s-core.yml -i inventories/production
# ... continue with phases 03-08
```

## Environments

| Environment | Inventory | K8s Type | HA | Hardening | Storage |
|-------------|-----------|----------|-----|-----------|---------|
| local | `inventories/local` | K3D | No | No | local-path |
| staging | `inventories/staging` | K3s | No | Yes | longhorn |
| production | `inventories/production` | K3s | Yes | Yes | longhorn-encrypted |

## Environment Variables

### Required (All Environments)

| Variable | Description |
|----------|-------------|
| `K3S_TOKEN` | Cluster join token |
| `POSTGRES_SUPERUSER_PASSWORD` | PostgreSQL admin password |
| `REDIS_PASSWORD` | Redis password |
| `AUTHENTIK_SECRET_KEY` | Authentik encryption key |

### Required (Production Only)

| Variable | Description |
|----------|-------------|
| `PROD_DOMAIN` | Domain name (e.g., atlas.example.com) |
| `ADMIN_IP` | Admin IP range for K3s API access |
| `LETSENCRYPT_EMAIL` | Email for Let's Encrypt certificates |
| `PROD_MASTER_HOST` | Master node IP |
| `PROD_SSH_KEY` | Path to SSH private key |

### Optional (Per-Service Database Passwords)

| Variable | Description |
|----------|-------------|
| `MATTERMOST_DB_PASSWORD` | Mattermost database password |
| `NEXTCLOUD_DB_PASSWORD` | Nextcloud database password |
| `AUTHENTIK_DB_PASSWORD` | Authentik database password |
| `GITEA_DB_PASSWORD` | Gitea database password |
| `REDCAP_DB_PASSWORD` | REDCap database password |
| `FLIPT_DB_PASSWORD` | Flipt database password |
| `VAULT_DB_PASSWORD` | Vault database password |

## Playbook Tags

Run specific components using tags:

```bash
# Deploy only Cilium
ansible-playbook playbooks/phase-02-k3s-core.yml -i inventories/local --tags cilium

# Deploy only databases
ansible-playbook playbooks/phase-04-databases.yml -i inventories/local --tags postgresql

# Deploy only monitoring
ansible-playbook playbooks/phase-07-monitoring.yml -i inventories/local --tags grafana
```

### Available Tags

| Phase | Tags |
|-------|------|
| 0 | `hardening`, `security`, `ssh`, `firewall`, `fail2ban`, `auditd` |
| 1 | `preparation`, `prerequisites`, `docker`, `k3d` |
| 2 | `k3s`, `cluster`, `infrastructure`, `cilium`, `longhorn`, `cert-manager`, `tls` |
| 3 | `vault`, `secrets`, `external-secrets`, `platform` |
| 4 | `databases`, `postgresql`, `redis` |
| 5 | `services`, `authentik`, `mattermost`, `nextcloud`, `seaweedfs`, `redcap`, `flipt` |
| 6 | `devops`, `gitea`, `argocd`, `gitops` |
| 7 | `monitoring`, `prometheus`, `grafana`, `hubble` |
| 8 | `security`, `network-policies` |

## Service URLs

After deployment, services are available at:

| Service | URL |
|---------|-----|
| Authentik (SSO) | `https://auth.<domain>` |
| Vault | `https://vault.<domain>` |
| Mattermost | `https://chat.<domain>` |
| Nextcloud | `https://cloud.<domain>` |
| Gitea | `https://git.<domain>` |
| ArgoCD | `https://argocd.<domain>` |
| Grafana | `https://grafana.<domain>` |
| Hubble UI | `https://hubble.<domain>` |

## Directory Structure

```
ansible/
├── ansible.cfg              # Ansible configuration
├── requirements.yml         # Required collections
├── inventories/
│   ├── local/              # Local K3D environment
│   ├── staging/            # Staging environment
│   └── production/         # Production environment
├── playbooks/
│   ├── phase-00-hardening.yml
│   ├── phase-01-preparation.yml
│   ├── phase-02-k3s-core.yml
│   ├── phase-03-vault.yml
│   ├── phase-04-databases.yml
│   ├── phase-05-services.yml
│   ├── phase-06-devops.yml
│   ├── phase-07-monitoring.yml
│   └── phase-08-security.yml
├── roles/
│   ├── common/             # Prerequisites, Docker, Hardening
│   ├── k3s/                # K3s server, agent, K3D
│   ├── infrastructure/     # Cilium, Longhorn, Cert-Manager
│   ├── platform/           # Vault, PostgreSQL, Redis, Authentik
│   ├── services/           # Mattermost, Nextcloud, etc.
│   ├── devops/             # Gitea, ArgoCD
│   ├── monitoring/         # Prometheus, Grafana, Hubble
│   └── security/           # Network Policies
└── vars/
    ├── helm_versions.yml   # Centralized Helm chart versions
    └── secrets_mapping.yml # Environment variable mappings
```

## Upgrading Components

Update Helm chart versions in `vars/helm_versions.yml`:

```yaml
helm_versions:
  cilium: "1.16.5"
  postgresql_ha: "14.0.4"
  # ... etc
```

Then re-run the appropriate playbook.

## Troubleshooting

### Check deployment status

```bash
# Verify K3s cluster
kubectl get nodes

# Check all pods
kubectl get pods -A

# Check Cilium status
cilium status
```

### Common issues

1. **Vault sealed**: Run phase-03 again with unseal keys
2. **Database connection failed**: Check PostgreSQL pods are running
3. **Certificate issues**: Verify cert-manager ClusterIssuers

## Security Notes

- All secrets are managed via environment variables (never committed to repo)
- Production requires `ADMIN_IP` to restrict K3s API access
- Network policies enforce default-deny in production
- Storage is encrypted with Longhorn in production
- WireGuard encryption enabled for inter-node traffic

### Security Hardening Features

| Feature | Local | Staging | Production |
|---------|-------|---------|------------|
| SSH Hardening (key-only, no root) | - | Yes | Yes |
| UFW Firewall | - | Yes | Yes |
| Fail2ban | - | Yes | Yes |
| Auditd | - | Yes | Yes |
| Kernel Hardening (ASLR, sysctl) | - | Yes | Yes |
| AIDE File Integrity | - | Yes | Yes |
| AppArmor | - | Yes | Yes |
| Password Policies (PAM) | - | Yes | Yes |
| Network Policies (Cilium) | - | Yes | Yes |
| Pod Security Standards | Privileged | Baseline | Restricted |
| WireGuard Inter-node Encryption | - | Optional | Yes |
| Longhorn Encryption | - | Yes | Yes |
| Secret Rotation | - | - | Yes |
| Image Scanning (Trivy) | - | Yes | Yes |
| Off-site Encrypted Backups | - | - | Yes |

### Ansible Best Practices Applied

- **no_log: true** on all tasks handling secrets (K3s token, Vault tokens, database passwords)
- **SSH pipelining** enabled for secure module execution
- **Vault IDs** support for multi-environment secret separation
- Secrets sourced exclusively from environment variables

## License

This project is proprietary. All rights reserved.
