---
layout: home

hero:
  name: ATLAS Platform
  text: Infrastructure Kubernetes
  tagline: >-
    Plateforme automatisee pour le deploiement de microservices
    orientes recherche et collaboration
  actions:
    - theme: brand
      text: Guide de deploiement
      link: /deployment-priority
    - theme: alt
      text: Voir sur GitHub
      link: https://github.com/univ-lehavre/k8s

features:
  - title: Securite
    details: >-
      Keycloak SSO/OIDC/MFA, Vault + External Secrets Operator,
      Kyverno, Network Policies, certificats Let's Encrypt
  - title: Deploiement
    details: >-
      9 phases ordonnees via Ansible, K3s en production,
      K3D pour le developpement local, resolution automatique des dependances
  - title: Observabilite
    details: >-
      Prometheus, Grafana, Hubble (Cilium),
      dashboards et alertes preconfigures
  - title: Collaboration
    details: >-
      Mattermost, Nextcloud, OnlyOffice, Gitea, ArgoCD,
      REDCap, ECRIN, Flipt
---

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
        | Keycloak   |  |   Apps    |  |   DevOps    |
        | SSO/OIDC   |  | Nextcloud |  | Gitea       |
        |            |  | Mattermost|  | ArgoCD      |
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

## Services

| Service    | URL                | Description                     |
|------------|--------------------|---------------------------------|
| Keycloak   | `login.<domain>`   | IAM, SSO, OIDC, MFA            |
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
| 5     | `phase-05-services.yml`    | Keycloak, apps, SeaweedFS              |
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
