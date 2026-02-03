# ATLAS Platform - Kubernetes Infrastructure

Plateforme Kubernetes automatisée pour le déploiement de microservices orientés recherche et collaboration. Déploiement via Ansible sur K3s (production) ou K3D (développement local).

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              ATLAS Platform                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                        API Gateway (Envoy)                           │    │
│  │                     envoy-gateway-system                             │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│          ┌─────────────────────────┼─────────────────────────┐              │
│          │                         │                         │              │
│          ▼                         ▼                         ▼              │
│  ┌───────────────┐    ┌───────────────────────┐    ┌─────────────────┐     │
│  │   Authelia    │    │      Applications      │    │    DevOps       │     │
│  │  (login.)     │    │                        │    │                 │     │
│  │               │    │  Nextcloud (cloud.)    │    │  Gitea (git.)   │     │
│  │  SSO / OIDC   │    │  Mattermost (chat.)    │    │  ArgoCD         │     │
│  │  Forward Auth │    │  REDCap (redcap.)      │    │                 │     │
│  │  MFA          │    │  ECRIN (ecrin.)        │    └─────────────────┘     │
│  └───────────────┘    │  Flipt (flags.)        │                            │
│                       │  OnlyOffice (interne)  │    ┌─────────────────┐     │
│                       └───────────────────────┘    │   Monitoring    │     │
│                                                     │                 │     │
│  ┌─────────────────────────────────────────────┐   │  Prometheus     │     │
│  │              Data Layer                      │   │  Grafana        │     │
│  │                                              │   │  Hubble         │     │
│  │  PostgreSQL HA    Redis       SeaweedFS     │   └─────────────────┘     │
│  │  (7 databases)    (cache)     (S3)          │                            │
│  └─────────────────────────────────────────────┘                            │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                     Infrastructure Layer                             │    │
│  │                                                                       │    │
│  │  K3s │ Cilium (CNI) │ Longhorn (Storage) │ Cert-Manager │ Vault     │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Services

### Authentification

| Service  | URL              | Description                                  |
| -------- | ---------------- | -------------------------------------------- |
| Authelia | `login.<domain>` | SSO, OIDC, Forward Auth, MFA (TOTP/WebAuthn) |

### Applications

| Service    | URL               | Description                                     |
| ---------- | ----------------- | ----------------------------------------------- |
| Nextcloud  | `cloud.<domain>`  | Partage de fichiers et collaboration            |
| Mattermost | `chat.<domain>`   | Messagerie d'équipe                             |
| REDCap     | `redcap.<domain>` | Capture de données de recherche                 |
| ECRIN      | `ecrin.<domain>`  | Plateforme de collaboration chercheurs          |
| Flipt      | `flags.<domain>`  | Feature flags                                   |
| OnlyOffice | (interne)         | Édition de documents (via Nextcloud/Mattermost) |

### DevOps

| Service | URL               | Description                 |
| ------- | ----------------- | --------------------------- |
| Gitea   | `git.<domain>`    | Forge Git (SSH: port 30022) |
| ArgoCD  | `argocd.<domain>` | GitOps CD                   |

### Monitoring

| Service | URL                | Description                 |
| ------- | ------------------ | --------------------------- |
| Grafana | `grafana.<domain>` | Dashboards                  |
| Hubble  | `hubble.<domain>`  | Observabilité réseau Cilium |

## Prérequis

### Production / Staging

- Ubuntu 24.04 LTS
- 16 GB RAM minimum (32 GB recommandé)
- 4 CPU cores minimum (8 recommandé)
- 200 GB disque minimum
- IP publique
- Enregistrements DNS configurés

### Local (K3D)

- Docker Desktop
- 8 GB RAM alloués à Docker
- macOS, Linux ou Windows (WSL2)

## Installation

### 1. Configuration

```bash
# Cloner le repository
git clone <repository-url>
cd k8s

# Copier et éditer les variables d'environnement
cp .env.example .env
vim .env

# Installer les dépendances Ansible
pip install -r requirements.txt
ansible-galaxy install -r requirements.yml
```

### 2. Déploiement

#### Local (K3D)

```bash
# Déploiement complet
ansible-playbook playbooks/site.yml -i inventories/local

# Ou phase par phase
ansible-playbook playbooks/phase-01-preparation.yml -i inventories/local
ansible-playbook playbooks/phase-02-k3s-core.yml -i inventories/local
# ...
```

#### Staging

```bash
ansible-playbook playbooks/site.yml -i inventories/staging
```

#### Production

```bash
# Inclut le hardening système (Phase 0)
ansible-playbook playbooks/site.yml -i inventories/production
```

## Phases de Déploiement

| Phase | Playbook                   | Description                                                                  |
| ----- | -------------------------- | ---------------------------------------------------------------------------- |
| 0     | `phase-00-hardening.yml`   | Hardening système : SSH, UFW, Fail2ban, Auditd, AIDE, AppArmor               |
| 1     | `phase-01-preparation.yml` | Prérequis système, Docker (K3D)                                              |
| 2     | `phase-02-k3s-core.yml`    | K3s/K3D, Cilium, Envoy Gateway, Cert-Manager, Longhorn                       |
| 3     | `phase-03-vault.yml`       | HashiCorp Vault, External Secrets Operator                                   |
| 4     | `phase-04-databases.yml`   | PostgreSQL HA, Redis                                                         |
| 5     | `phase-05-services.yml`    | Authelia, Mattermost, Nextcloud, OnlyOffice, REDCap, ECRIN, Flipt, SeaweedFS |
| 6     | `phase-06-devops.yml`      | Gitea, ArgoCD                                                                |
| 7     | `phase-07-monitoring.yml`  | Prometheus, Grafana, Hubble UI                                               |
| 8     | `phase-08-security.yml`    | Kyverno, Network Policies, Pod Security, Backups                             |

## Structure du Repository

```
.
├── ansible/
│   ├── playbooks/
│   │   ├── site.yml                    # Orchestration principale
│   │   └── phase-*.yml                 # Playbooks par phase
│   │
│   ├── roles/
│   │   ├── common/
│   │   │   ├── prerequisites/          # Paquets système
│   │   │   ├── docker/                 # Installation Docker
│   │   │   └── hardening/              # SSH, UFW, Fail2ban, Auditd, AIDE
│   │   │
│   │   ├── k3s/
│   │   │   ├── server/                 # K3s master
│   │   │   ├── agent/                  # K3s worker
│   │   │   └── k3d/                    # K3D local
│   │   │
│   │   ├── infrastructure/
│   │   │   ├── cilium/                 # CNI + Network Policies
│   │   │   ├── envoy_gateway/          # API Gateway
│   │   │   ├── cert_manager/           # TLS
│   │   │   └── longhorn/               # Storage
│   │   │
│   │   ├── platform/
│   │   │   ├── vault/                  # Secrets management
│   │   │   ├── external_secrets/       # Secret sync
│   │   │   ├── postgresql/             # Database
│   │   │   ├── redis/                  # Cache
│   │   │   └── authelia/               # IAM
│   │   │
│   │   ├── services/
│   │   │   ├── mattermost/
│   │   │   ├── nextcloud/
│   │   │   ├── onlyoffice/
│   │   │   ├── redcap/
│   │   │   ├── ecrin/
│   │   │   ├── seaweedfs/
│   │   │   └── flipt/
│   │   │
│   │   ├── devops/
│   │   │   ├── gitea/
│   │   │   └── argocd/
│   │   │
│   │   ├── monitoring/
│   │   │   ├── kube_prometheus/
│   │   │   └── hubble_ui/
│   │   │
│   │   └── security/
│   │       ├── kyverno/
│   │       ├── network_policies/
│   │       ├── pod_security/
│   │       └── backup_offsite/
│   │
│   ├── inventories/
│   │   ├── local/
│   │   ├── staging/
│   │   └── production/
│   │
│   └── vars/
│       └── helm_versions.yml           # Versions centralisées
│
├── docs/
│   └── audits/
│       └── documentation-drift-audit.md
│
├── Taskfile.yml
└── README.md
```

## Configuration par Environnement

### Différences clés

| Aspect           | Local        | Staging               | Production            |
| ---------------- | ------------ | --------------------- | --------------------- |
| Cluster          | K3D (Docker) | K3s single-node       | K3s HA (3+ nodes)     |
| Storage          | local-path   | Longhorn              | Longhorn + encryption |
| TLS              | Self-signed  | Let's Encrypt staging | Let's Encrypt prod    |
| Hardening        | Désactivé    | Activé                | Activé                |
| Network Policies | Désactivées  | Activées              | Activées              |
| Kyverno          | Audit        | Audit                 | Enforce               |
| HA               | Non          | Optionnel             | Oui                   |

### Network Policies

Les Network Policies Cilium sont **désactivées en environnement local** pour faciliter le développement :

```yaml
# inventories/local/group_vars/all.yml
network_policies_enabled: false
network_policy_l7_enabled: false
```

Pour les activer en local :

```yaml
network_policies_enabled: true
network_policy_l7_enabled: true
```

## Bases de Données

### PostgreSQL

| Database        | Service         |
| --------------- | --------------- |
| `vault`         | HashiCorp Vault |
| `authelia_db`   | Authelia        |
| `mattermost_db` | Mattermost      |
| `nextcloud_db`  | Nextcloud       |
| `gitea_db`      | Gitea           |
| `redcap_db`     | REDCap          |
| `flipt_db`      | Flipt           |

### Redis

Utilisé pour les sessions (Authelia), le cache (Mattermost, Nextcloud, Gitea) et le rate limiting (Envoy Gateway).

## Sécurité

### Phase 0 - Hardening Système

- **SSH** : Authentification par clé uniquement, pas de root login
- **UFW** : Firewall avec allow-list
- **Fail2ban** : Protection brute-force SSH
- **Auditd** : Journalisation des événements système
- **AIDE** : File Integrity Monitoring
- **AppArmor** : Contrôle d'accès obligatoire

### Phase 8 - Sécurité Kubernetes

- **Kyverno** : Policy engine avec 8 policies (privileged, labels, limits, registries, etc.)
- **Network Policies** : Default deny + allow explicites via Cilium
- **Pod Security** : Standards baseline/restricted par namespace
- **Velero** : Backups off-site chiffrés

## Accès Gitea SSH

Gitea expose le SSH via NodePort 30022 :

```bash
# Clone
git clone ssh://git@<node-ip>:30022/<user>/<repo>.git

# Configuration SSH
cat >> ~/.ssh/config << EOF
Host gitea
  HostName <node-ip>
  Port 30022
  User git
  IdentityFile ~/.ssh/id_ed25519
EOF

# Firewall (production)
ufw allow 30022/tcp comment "Gitea SSH"
```

## Commandes Utiles

```bash
# Déployer une phase spécifique
ansible-playbook playbooks/phase-05-services.yml -i inventories/local

# Déployer un service spécifique
ansible-playbook playbooks/phase-05-services.yml -i inventories/local --tags nextcloud

# Vérifier l'état du cluster
kubectl get pods -A

# Voir les policies Kyverno
kubectl get policyreport -A

# Voir les Network Policies Cilium
kubectl get ciliumnetworkpolicy -A

# Accéder à Hubble UI (observabilité réseau)
kubectl port-forward -n kube-system svc/hubble-ui 8080:80
```

## Versions des Composants

| Composant        | Version     | Latest   | Commentaires                                                                 |
| ---------------- | ----------- | -------- | ---------------------------------------------------------------------------- |
| K3s              | 1.29.2+k3s1 | 1.35.x   | Version LTS stable, upgrade planifié après validation des workloads          |
| Cilium           | 1.16.5      | 1.17.5   | Attente stabilisation 1.17, breaking changes Gateway API                     |
| Envoy Gateway    | 1.2.0       | 1.6.3    | Upgrade majeur requis, testing en cours sur staging                          |
| Longhorn         | 1.6.0       | 1.11.0   | v1.11 a un bug mémoire (hotfix requis), reste sur 1.6 LTS                    |
| Cert-Manager     | 1.14.3      | 1.19.3   | Upgrade planifié, pas de breaking changes bloquants                          |
| Vault            | 0.27.0      | 0.30.0   | Upgrade planifié, requiert Kubernetes 1.29+                                  |
| External Secrets | 0.9.12      | 1.3.1    | Version 1.x = breaking changes API, migration en cours                       |
| PostgreSQL HA    | 14.0.4      | 16.3.2   | v16.x requiert migration données, planifié prochain cycle maintenance        |
| Redis            | 18.12.1     | 24.1.2   | v24.x = Redis 8, breaking changes config, évaluation en cours                |
| Authelia         | 0.9.0       | 0.10.49  | Chart beta, upgrade après stabilisation                                      |
| Gitea            | 10.1.1      | 12.5.0   | v12.x supprime support MySQL/MariaDB intégré, OK pour nous (PostgreSQL)      |
| ArgoCD           | 6.4.0       | 9.3.7    | v9.x = ArgoCD v3.0, breaking changes majeurs, migration planifiée Q2         |
| Kube-Prometheus  | 56.21.1     | 81.4.3   | Upgrade fréquents, version stable testée en production                       |
| Kyverno          | 3.3.0       | 3.7.0    | Upgrade planifié, pas de breaking changes majeurs                            |

## Documentation

- [Audit de conformité](docs/audits/documentation-drift-audit.md)

## License

MIT License. Voir le fichier [LICENSE](LICENSE) pour plus de détails.
