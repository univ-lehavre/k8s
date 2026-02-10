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
│  │  PostgreSQL HA   MariaDB   Redis  SeaweedFS │   └─────────────────┘     │
│  │  (7 databases)  (REDCap)  (cache)   (S3)    │                            │
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
| 4     | `phase-04-databases.yml`   | PostgreSQL HA, MariaDB, Redis                                                |
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
│   │   │   ├── postgresql/             # Database (PostgreSQL)
│   │   │   ├── mariadb/                # Database (MySQL-compatible)
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
│   ├── CONTRIBUTING.md                    # Guide du développeur (linting, hooks, CI)
│   ├── audits/
│   │   ├── 2026-02-03-code-documentation-coherence.md
│   │   ├── 2026-02-03-code-review.md
│   │   └── 2026-02-03-documentation-drift-audit.md
│   └── roadmaps/
│       ├── 2026-02-03-documentation-coherence-remediation.md
│       └── 2026-02-05-ecrin-deployment-guide.md
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

| Database     | Service         |
| ------------ | --------------- |
| `vault`      | HashiCorp Vault |
| `authelia`   | Authelia        |
| `mattermost` | Mattermost      |
| `nextcloud`  | Nextcloud       |
| `gitea`      | Gitea           |
| `flipt`      | Flipt           |

### MariaDB

REDCap nécessite MySQL ou un dérivé MySQL (MariaDB, Percona). Il n'est **pas compatible avec PostgreSQL**.

| Database   | Service |
| ---------- | ------- |
| `redcap`   | REDCap  |

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

| Composant        | Version | Latest  | Commentaires                                                 |
| ---------------- | ------- | ------- | ------------------------------------------------------------ |
| K3s              | 1.29.2  | 1.35.x  | Version LTS stable, upgrade planifié après validation        |
| Cilium           | 1.16.5  | 1.17.5  | Attente stabilisation 1.17, breaking changes Gateway API     |
| Envoy Gateway    | 1.2.0   | 1.6.3   | Upgrade majeur requis, testing en cours sur staging          |
| Longhorn         | 1.6.0   | 1.11.0  | v1.11 a un bug mémoire (hotfix requis), reste sur 1.6 LTS    |
| Cert-Manager     | 1.14.3  | 1.19.3  | Upgrade planifié, pas de breaking changes bloquants          |
| Vault            | 1.15.2  | 1.21.2  | Upgrade planifié, requiert Kubernetes 1.29+                  |
| External Secrets | 0.9.12  | 1.3.x   | Version 1.x = breaking changes API, migration en cours       |
| PostgreSQL       | 16.x    | 18.1    | Migration données requise pour version majeure               |
| MariaDB          | 11.2.x  | 11.8.5  | Pour REDCap (incompatible PostgreSQL)                        |
| Redis            | 7.2.x   | 8.6-rc  | v8.x breaking changes config, évaluation en cours            |
| Authelia         | 4.38.x  | 4.39.15 | Upgrade vers 4.39.15 planifié                                |
| Gitea            | 1.21.x  | 1.25.4  | Upgrade planifié                                             |
| ArgoCD           | 2.10.x  | 3.3.0   | v3.x breaking changes majeurs, migration planifiée Q2        |
| Prometheus       | 2.x     | 3.9.1   | Via kube-prometheus-stack                                    |
| Kyverno          | 1.12.x  | 1.17.0  | Upgrade planifié                                             |

## Autorisations et Contrôle d'Accès

### Groupes Utilisateurs

| Groupe        | Description                              |
| ------------- | ---------------------------------------- |
| `admins`      | Administrateurs avec accès complet       |
| `devops`      | Équipe DevOps (déploiement, monitoring)  |
| `developers`  | Développeurs (accès lecture + sync)      |
| `researchers` | Chercheurs (accès aux outils recherche)  |

### Matrice des Autorisations par Service

| Service    | admins | devops | developers | researchers | Niveau Auth |
| ---------- | :----: | :----: | :--------: | :---------: | ----------- |
| Vault      | ✅     | ✅     | ❌         | ❌          | 2FA         |
| ArgoCD     | ✅     | ✅     | 👁️         | ❌          | 2FA         |
| Gitea      | ✅     | ✅     | ✅         | ✅          | 1FA         |
| Grafana    | ✅     | ✅     | ✅         | ✅          | 1FA         |
| Hubble UI  | ✅     | ✅     | ❌         | ❌          | 1FA         |
| Mattermost | ✅     | ✅     | ✅         | ✅          | 1FA         |
| Nextcloud  | ✅     | ✅     | ✅         | ✅          | 1FA         |
| REDCap     | ✅     | ❌     | ❌         | ✅          | 2FA         |

**Légende** : ✅ Accès complet | 👁️ Lecture seule | ❌ Pas d'accès | 1FA = mot de passe | 2FA = mot de passe + TOTP/WebAuthn

### Politiques de Sécurité Kubernetes

| Politique                     | Local   | Staging  | Production | Description                                     |
| ----------------------------- | ------- | -------- | ---------- | ----------------------------------------------- |
| Network Policies (Cilium)     | ❌      | ✅       | ✅         | Default deny + allowlist explicite              |
| L7 Network Filtering          | ❌      | ✅       | ✅         | Filtrage applicatif PostgreSQL                  |
| Pod Security Standards        | ❌      | baseline | restricted | Restrictions conteneurs (privileged, hostPath…) |
| Kyverno Policies              | Audit   | Audit    | Enforce    | 8 policies (registries, labels, limits…)        |
| etcd Encryption               | ❌      | ✅       | ✅         | Chiffrement secrets au repos                    |

### Kyverno Policies Déployées

| Policy                     | Description                                              |
| -------------------------- | -------------------------------------------------------- |
| `disallow-privileged`      | Interdit les conteneurs privilégiés                      |
| `disallow-host-namespaces` | Interdit l'accès aux namespaces host (PID, network)      |
| `disallow-host-path`       | Interdit le montage de chemins host                      |
| `disallow-latest-tag`      | Interdit l'utilisation du tag `:latest`                  |
| `restrict-registries`      | Limite aux registries approuvés (docker.io, ghcr.io…)    |
| `require-labels`           | Exige les labels `app.kubernetes.io/name` et `/component`|
| `require-resource-limits`  | Exige les limites CPU et mémoire                         |
| `require-probes`           | Exige les probes liveness et readiness (non-local)       |

### Network Policies par Namespace

| Namespace  | Ingress autorisé depuis                                 | Egress autorisé vers                  |
| ---------- | ------------------------------------------------------- | ------------------------------------- |
| postgresql | vault, authelia, mattermost, nextcloud, gitea, flipt    | -                                     |
| mariadb    | redcap                                                  | -                                     |
| redis      | authelia, nextcloud, gitea                              | -                                     |
| vault      | external-secrets, envoy-gateway                         | postgresql                            |
| authelia   | envoy-gateway                                           | redis, postgresql                     |
| argocd     | envoy-gateway                                           | gitea, external (HTTPS, SSH)          |
| gitea      | envoy-gateway, argocd                                   | postgresql, redis                     |
| nextcloud  | envoy-gateway                                           | postgresql, redis, seaweedfs          |
| mattermost | envoy-gateway                                           | postgresql, redis                     |
| onlyoffice | nextcloud, mattermost                                   | -                                     |
| seaweedfs  | nextcloud                                               | -                                     |
| redcap     | envoy-gateway                                           | mariadb                               |
| ecrin      | envoy-gateway                                           | authelia (OIDC)                       |
| flipt      | envoy-gateway                                           | postgresql                            |
| monitoring | envoy-gateway                                           | tous (scraping)                       |

### Isolation des Bases de Données (L7)

Chaque service ne peut accéder qu'à sa propre base de données grâce au filtrage L7 Cilium :

#### PostgreSQL

| Service    | Base de données autorisée |
| ---------- | ------------------------- |
| Vault      | `vault`                   |
| Authelia   | `authelia`                |
| Mattermost | `mattermost`              |
| Nextcloud  | `nextcloud`               |
| Gitea      | `gitea`                   |
| Flipt      | `flipt`                   |

#### MariaDB

| Service    | Base de données autorisée |
| ---------- | ------------------------- |
| REDCap     | `redcap`                  |

## Documentation

- [Audit de conformité](docs/audits/2026-02-03-documentation-drift-audit.md)

## License

MIT License. Voir le fichier [LICENSE](LICENSE) pour plus de détails.
