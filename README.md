# ATLAS Platform - Kubernetes Infrastructure

[![DOI](https://zenodo.org/badge/1148296093.svg)](https://doi.org/10.5281/zenodo.18588428)

Plateforme Kubernetes automatisee pour le deploiement de microservices
orientes recherche et collaboration.
Deploiement via Ansible sur K3s (production) ou K3D (developpement local).

## Architecture

```text
                          INTERNET
                             |
                     +-----------------+
                     | Envoy Gateway   |
                     | (443/80)        |
                     +--------+--------+
                              |
              +---------------+---------------+
              |               |               |
        +-----+-----+  +-----+-----+  +------+------+
        | Keycloak/  |  |   Apps    |  |   DevOps    |
        | Authelia   |  | Nextcloud |  | Gitea       |
        | SSO/OIDC   |  | Mattermost|  | ArgoCD      |
        +-----+------+  | REDCap   |  +-------------+
              |          | ECRIN    |  +-------------+
              |          | Flipt    |  | Monitoring  |
              |          | OnlyOffice| | Grafana     |
              |          +----------+  | Hubble      |
              |                        +-------------+
     +--------+-----------------------------------+
     |            Data Layer                       |
     | PostgreSQL HA | MariaDB | Redis | SeaweedFS |
     +--------+-----------------------------------+
     |          Infrastructure Layer               |
     | K3s | Cilium | Longhorn | Cert-Mgr | Vault  |
     +---------------------------------------------+
```

## Quickstart

```bash
# Cloner et configurer
git clone <repository-url> && cd k8s
cp .env.example .env && vim .env
pip install -r requirements.txt
ansible-galaxy install -r ansible/requirements.yml

# Deploiement local (K3D)
ansible-playbook playbooks/site.yml -i inventories/local

# Deploiement production
ansible-playbook playbooks/site.yml -i inventories/production
```

## Services

| Service    | URL                | Description                     |
|------------|--------------------|---------------------------------|
| Keycloak   | `login.<domain>`   | IAM, SSO, OIDC, MFA (staging/prod) |
| Authelia   | `login.<domain>`   | SSO, Forward Auth, MFA (local)  |
| Mattermost | `chat.<domain>`    | Messagerie d'equipe             |
| Nextcloud  | `cloud.<domain>`   | Partage de fichiers             |
| OnlyOffice | `office.<domain>`  | Edition collaborative           |
| REDCap     | `redcap.<domain>`  | Capture de donnees de recherche |
| ECRIN      | `ecrin.<domain>`   | Collaboration chercheurs        |
| Flipt      | `flags.<domain>`   | Feature flags                   |
| Gitea      | `git.<domain>`     | Forge Git (SSH: port 30022)     |
| ArgoCD     | `argocd.<domain>`  | GitOps CD                       |
| Grafana    | `grafana.<domain>` | Dashboards                      |
| Hubble     | `hubble.<domain>`  | Observabilite reseau            |

## Phases de deploiement

| Phase | Playbook                   | Description                            |
|-------|----------------------------|----------------------------------------|
| 0     | `phase-00-hardening.yml`   | Hardening systeme (SSH, UFW, Fail2ban) |
| 1     | `phase-01-preparation.yml` | Prerequis systeme, Docker              |
| 2     | `phase-02-k3s-core.yml`    | K3s, Cilium, Envoy GW, Cert-Mgr       |
| 3     | `phase-03-vault.yml`       | Vault, External Secrets Operator       |
| 4     | `phase-04-databases.yml`   | PostgreSQL HA, MariaDB, Redis          |
| 5     | `phase-05-services.yml`    | Keycloak/Authelia, apps, SeaweedFS     |
| 6     | `phase-06-devops.yml`      | Gitea, ArgoCD                          |
| 7     | `phase-07-monitoring.yml`  | Prometheus, Grafana, Hubble            |
| 8     | `phase-08-security.yml`    | Kyverno, Network Policies, backups     |

## Environnements

| Aspect           | Local        | Staging               | Production            |
|------------------|--------------|-----------------------|-----------------------|
| Cluster          | K3D (Docker) | K3s single-node       | K3s HA (3+ nodes)     |
| TLS              | Self-signed  | Let's Encrypt staging | Let's Encrypt prod    |
| Kyverno          | Audit        | Audit                 | Enforce               |
| Network Policies | Non          | Oui                   | Oui                   |
| Hardening        | Non          | Oui                   | Oui                   |
| Authentification | Authelia     | Keycloak              | Keycloak              |

## Documentation

| Document | Description |
|----------|-------------|
| [Guide de deploiement](docs/deployment-priority.md) | Deploiement par jalons avec dependances |
| [Authentification](docs/authentication.md) | Authentification |
| [Autorisations](docs/authorization.md) | Autorisations |
| [Secrets et chiffrement](docs/secrets-encryption.md) | Secrets et chiffrement |
| [Flux reseau](docs/network-flows.md) | Flux reseau |
| [Contribuer](docs/CONTRIBUTING.md) | Linting, hooks, CI/CD |

## License

MIT License. Voir le fichier [LICENSE](LICENSE) pour plus de details.
