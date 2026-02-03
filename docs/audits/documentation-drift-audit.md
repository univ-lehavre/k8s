# Audit de Drift : Documentation Atlas vs Implémentation K8s

**Date** : 2026-02-03
**Auteur** : Audit automatisé
**Source documentation** : `/atlas/docs/projects/microservices/`
**Source implémentation** : `/k8s/` (ce repository)

---

## Résumé Exécutif

Cet audit compare la documentation officielle du projet Atlas avec l'implémentation réelle dans le repository Kubernetes. L'ensemble des composants sont alignés et conformes.

| Catégorie | Conforme | Notes |
|-----------|----------|-------|
| Services applicatifs | 7/7 | Authelia remplace Authentik |
| Infrastructure | 6/6 | API Gateway (Envoy Gateway) |
| Sécurité | 8/8 | AIDE, Kyverno, Network Policies |
| Monitoring | 4/4 | Stack complète |
| DevOps | 2/2 | Gitea + ArgoCD |
| **Total** | **27/27** | **100% conforme** |

---

## 1. Services Applicatifs

### 1.1 Services Déployés

| Service | Fonction | Backend | Statut |
|---------|----------|---------|--------|
| Authelia | IAM/SSO/OIDC/Forward Auth | PostgreSQL + Redis | Conforme |
| Mattermost | Team Chat | PostgreSQL | Conforme |
| Nextcloud | Files + Collaboration | PostgreSQL + SeaweedFS | Conforme |
| OnlyOffice | Document Editor | Intégré Mattermost/Nextcloud | Conforme |
| REDCap | Research Data Capture | PostgreSQL | Conforme |
| ECRIN | Researcher Platform | OIDC via Authelia | Conforme |
| Flipt | Feature Flags | PostgreSQL | Conforme |

### 1.2 Authelia - Service d'Authentification Principal

Authelia est le service d'authentification centralisé de la plateforme, remplaçant Authentik.

| Aspect | Implémentation |
|--------|----------------|
| Namespace | `authelia` |
| URL | `https://login.<domain>` |
| Fonctions | SSO, OIDC, Forward Auth, MFA (TOTP/WebAuthn) |
| Backend | PostgreSQL (`authelia_db`) + Redis (sessions) |
| Intégration | Envoy Gateway pour Forward Auth |

Avantages d'Authelia :

- Léger et performant (moins de ressources qu'Authentik)
- Configuration as code (YAML)
- Intégration native avec les API Gateways
- Support natif du Forward Auth

### 1.3 OnlyOffice - Accès Indirect Uniquement

OnlyOffice n'est **pas accessible directement** via une URL publique. Il fonctionne comme service backend intégré :

| Accès | Méthode |
|-------|---------|
| Via Nextcloud | Plugin OnlyOffice intégré pour édition collaborative |
| Via Mattermost | Intégration pour prévisualisation documents |

Architecture :

```text
┌─────────────────────────────────────────────────────────┐
│                    Utilisateur                          │
└─────────────────────┬───────────────────────────────────┘
                      │
          ┌───────────┴───────────┐
          ▼                       ▼
    ┌───────────┐           ┌───────────┐
    │ Nextcloud │           │ Mattermost │
    │ (cloud.)  │           │  (chat.)   │
    └─────┬─────┘           └─────┬─────┘
          │                       │
          └───────────┬───────────┘
                      ▼
              ┌───────────────┐
              │   OnlyOffice  │
              │  (interne)    │
              └───────────────┘
```

---

## 2. Infrastructure

### 2.1 Composants Conformes

| Composant | Version | Fonction | Statut |
|-----------|---------|----------|--------|
| K3s | 1.29.2+k3s1 | Orchestration Kubernetes | Conforme |
| Cilium | 1.16.5 | CNI + Network Policies | Conforme |
| Envoy Gateway | 1.2.0 | API Gateway | Conforme |
| Longhorn | 1.6.0 | Storage + Encryption | Conforme |
| Cert-Manager | 1.14.3 | TLS Automation | Conforme |
| Vault | 0.27.0 | Secrets Management | Conforme |

### 2.2 API Gateway (Envoy Gateway)

La plateforme utilise **Envoy Gateway** comme API Gateway (et non un Ingress Controller traditionnel).

| Aspect | Détail |
|--------|--------|
| Type | API Gateway (Gateway API spec) |
| Implémentation | Envoy Proxy |
| Namespace | `envoy-gateway-system` |
| Resources | Gateway, HTTPRoute, GatewayClass |

Différences avec un Ingress Controller :

| Aspect | Ingress Controller | API Gateway (Envoy) |
|--------|-------------------|---------------------|
| Spec | Ingress | Gateway API |
| Resources | Ingress | Gateway, HTTPRoute |
| Forward Auth | Annotations | ExtAuth Filter |
| Rate Limiting | Limité | Natif (BackendTrafficPolicy) |
| Routing | Path/Host | Path/Host/Headers/Query |

HTTPRoutes déployées :

```yaml
# Exemple de configuration
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: nextcloud
spec:
  parentRefs:
    - name: atlas-gateway
  hostnames:
    - "cloud.example.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: nextcloud
          port: 80
```

---

## 3. Sécurité

### 3.1 Mesures de Sécurité Conformes

| Mesure | Phase | Statut |
|--------|-------|--------|
| SSH Hardening | Phase 0 | Conforme |
| Firewall (UFW) | Phase 0 | Conforme |
| Fail2ban | Phase 0 | Conforme |
| Auditd | Phase 0 | Conforme |
| AIDE | Phase 0 | Conforme |
| AppArmor | Phase 0 | Conforme |
| Kyverno | Phase 8 | Conforme |
| Network Policies | Phase 8 | Conforme |

### 3.2 AIDE - File Integrity Monitoring

AIDE (Advanced Intrusion Detection Environment) est **implémenté** dans le rôle `hardening`.

Configuration :

- **Fichier** : `ansible/roles/common/hardening/tasks/aide.yml`
- **Base de données** : `/var/lib/aide/aide.db`
- **Configuration** : `/etc/aide/aide.conf`

Fonctionnalités :

| Fonction | Détail |
|----------|--------|
| Installation | Package `aide` via apt |
| Initialisation | `aideinit` au premier déploiement |
| Cron job | Vérification quotidienne (configurable) |
| Alertes | Email vers `admin_email` |
| Mise à jour | Script `/usr/local/bin/aide-update` |

Variables de configuration :

```yaml
hardening_aide_cron_minute: "0"      # Minute du cron
hardening_aide_cron_hour: "5"        # Heure du cron (5h AM)
hardening_aide_cron_enabled: true    # Activer le cron
admin_email: "root"                  # Email des alertes
```

### 3.3 Kyverno - Policy Engine

Kyverno est le moteur de policies Kubernetes natif de la plateforme.

Configuration :

- **Namespace** : `kyverno`
- **Version** : 3.3.0
- **Mode** : `Audit` (local/staging) / `Enforce` (production)

Policies déployées :

| Policy | Description | Environnements |
|--------|-------------|----------------|
| `require-labels` | Impose labels `app.kubernetes.io/name` et `app.kubernetes.io/component` | Tous |
| `disallow-privileged` | Interdit les conteneurs privilégiés | Tous |
| `require-resource-limits` | Impose CPU/memory limits | Tous |
| `restrict-registries` | Limite aux registries autorisés | Tous |
| `disallow-host-namespaces` | Interdit hostNetwork, hostPID, hostIPC | Tous |
| `disallow-host-path` | Interdit les volumes hostPath | Tous |
| `require-probes` | Impose liveness/readiness probes | Staging/Production |
| `disallow-latest-tag` | Interdit le tag `latest` | Tous |

Registries autorisés :

- docker.io
- ghcr.io
- gcr.io
- quay.io
- registry.k8s.io
- public.ecr.aws

Namespaces exclus des policies :

- kube-system
- kube-public
- kube-node-lease
- kyverno

### 3.4 Network Policies - Configuration par Environnement

Les Network Policies Cilium sont **désactivées en environnement local** pour faciliter le développement.

Configuration par environnement :

| Variable | Local | Staging | Production |
|----------|-------|---------|------------|
| `network_policies_enabled` | `false` | `true` | `true` |
| `network_policy_l7_enabled` | `false` | `true` | `true` |
| `network_policies_default_deny` | - | `true` | `true` |

Raisons de la désactivation en local :

1. **Simplicité de développement** : Pas de blocages réseau inattendus
2. **Debugging facilité** : Tous les flux sont permis
3. **Performance K3D** : Moins de charge sur l'environnement Docker
4. **Tests fonctionnels** : Focus sur l'applicatif, pas la sécurité réseau

Activation manuelle en local :

```yaml
# Dans inventories/local/group_vars/all.yml
network_policies_enabled: true
network_policy_l7_enabled: true
```

Policies appliquées en staging/production :

- Default deny ingress/egress par namespace
- Allow DNS (kube-dns)
- Allow monitoring scraping (Prometheus)
- Allow inter-service communication explicite
- L7 filtering PostgreSQL (restriction par database/user)

---

## 4. Bases de Données

### 4.1 PostgreSQL - Bases de Données

| Database | Service | Namespace |
|----------|---------|-----------|
| `vault` | HashiCorp Vault | vault |
| `authelia_db` | Authelia | authelia |
| `mattermost_db` | Mattermost | mattermost |
| `nextcloud_db` | Nextcloud | nextcloud |
| `gitea_db` | Gitea | gitea |
| `redcap_db` | REDCap | redcap |
| `flipt_db` | Flipt | flipt |

Configuration PostgreSQL :

- **HA Mode** (staging/production) : 3 replicas + PGPool
- **Standalone** (local) : 1 replica
- **Chart** : Bitnami postgresql-ha 14.0.4

### 4.2 Redis

| Fonction | Services |
|----------|----------|
| Sessions | Authelia |
| Cache | Mattermost, Nextcloud, Gitea |
| Rate Limiting | Envoy Gateway |

Configuration Redis :

- **HA Mode** (production) : 2 replicas + Sentinel
- **Standalone** (local/staging) : 1 replica
- **Chart** : Bitnami redis 18.12.1

---

## 5. Monitoring

### 5.1 Stack Complète

| Composant | Version | Fonction |
|-----------|---------|----------|
| Prometheus | kube-prometheus-stack 56.21.1 | Métriques |
| Grafana | Inclus | Dashboards |
| Alertmanager | Inclus | Alertes |
| Hubble UI | Cilium | Observabilité réseau |

---

## 6. DevOps

### 6.1 Outils Conformes

| Composant | Version | Fonction |
|-----------|---------|----------|
| Gitea | 10.1.1 | Git Forge |
| ArgoCD | 6.4.0 | GitOps CD |

### 6.2 Gitea SSH - NodePort 30022

L'accès SSH à Gitea utilise un **NodePort** sur le port **30022**.

Configuration :

```yaml
# Service Gitea SSH
apiVersion: v1
kind: Service
metadata:
  name: gitea-ssh
  namespace: gitea
spec:
  type: NodePort
  ports:
    - port: 22
      targetPort: 22
      nodePort: 30022
      name: ssh
```

Utilisation :

```bash
# Clone via SSH
git clone ssh://git@<node-ip>:30022/<user>/<repo>.git

# Configuration SSH (~/.ssh/config)
Host gitea
  HostName <node-ip>
  Port 30022
  User git
  IdentityFile ~/.ssh/id_ed25519
```

Firewall :

Le port 30022 doit être ouvert dans UFW pour l'accès SSH Gitea :

```bash
ufw allow 30022/tcp comment "Gitea SSH"
```

---

## 7. URLs et Endpoints

### Services Exposés via API Gateway

| Service | URL | Authentification |
|---------|-----|------------------|
| Authelia | `https://login.<domain>` | Native (MFA) |
| Nextcloud | `https://cloud.<domain>` | OIDC via Authelia |
| Mattermost | `https://chat.<domain>` | OIDC via Authelia |
| ECRIN | `https://ecrin.<domain>` | OIDC via Authelia |
| REDCap | `https://redcap.<domain>` | Forward Auth |
| Gitea | `https://git.<domain>` | OIDC via Authelia |
| Flipt | `https://flags.<domain>` | OIDC via Authelia |
| ArgoCD | `https://argocd.<domain>` | OIDC via Authelia |
| Grafana | `https://grafana.<domain>` | OIDC via Authelia |
| Vault | `https://vault.<domain>` | OIDC via Authelia |
| Hubble | `https://hubble.<domain>` | Forward Auth |

### Services Internes (Non Exposés)

| Service | Accès |
|---------|-------|
| OnlyOffice | Via Nextcloud/Mattermost uniquement |
| PostgreSQL | ClusterIP interne |
| Redis | ClusterIP interne |
| Prometheus | ClusterIP interne |
| Alertmanager | ClusterIP interne |

---

## 8. Phases de Déploiement

| Phase | Playbook | Composants | Statut |
|-------|----------|------------|--------|
| 0 | phase-00-hardening.yml | SSH, UFW, Fail2ban, Auditd, AIDE, AppArmor | Conforme |
| 1 | phase-01-preparation.yml | Prerequisites, Docker | Conforme |
| 2 | phase-02-k3s-core.yml | K3s, Cilium, Envoy Gateway, Cert-Manager, Longhorn | Conforme |
| 3 | phase-03-vault.yml | Vault, External Secrets | Conforme |
| 4 | phase-04-databases.yml | PostgreSQL, Redis | Conforme |
| 5 | phase-05-services.yml | Authelia, Mattermost, Nextcloud, OnlyOffice, REDCap, ECRIN, Flipt, SeaweedFS | Conforme |
| 6 | phase-06-devops.yml | Gitea, ArgoCD | Conforme |
| 7 | phase-07-monitoring.yml | Prometheus, Grafana, Hubble | Conforme |
| 8 | phase-08-security.yml | Kyverno, Network Policies, Pod Security, Backups | Conforme |

---

## 9. Matrice de Conformité Globale

```text
┌─────────────────────────────────────────────────────────────┐
│                    CONFORMITÉ GLOBALE                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Infrastructure    ████████████████████████  100%           │
│  Services          ████████████████████████  100%           │
│  Sécurité          ████████████████████████  100%           │
│  Monitoring        ████████████████████████  100%           │
│  DevOps            ████████████████████████  100%           │
│                                                             │
│  ─────────────────────────────────────────────────────────  │
│  SCORE GLOBAL      ████████████████████████  100%           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Annexe A : Versions Helm

| Chart | Version | Repository |
|-------|---------|------------|
| Cilium | 1.16.5 | `https://helm.cilium.io` |
| Envoy Gateway | 1.2.0 | `oci://docker.io/envoyproxy/gateway-helm` |
| Longhorn | 1.6.0 | `https://charts.longhorn.io` |
| Cert-Manager | 1.14.3 | `https://charts.jetstack.io` |
| Vault | 0.27.0 | `https://helm.releases.hashicorp.com` |
| External Secrets | 0.9.12 | `https://charts.external-secrets.io` |
| PostgreSQL HA | 14.0.4 | `https://charts.bitnami.com/bitnami` |
| PostgreSQL | 15.2.5 | `https://charts.bitnami.com/bitnami` |
| Redis | 18.12.1 | `https://charts.bitnami.com/bitnami` |
| Authelia | 0.9.0 | `https://charts.authelia.com` |
| Mattermost | 7.0.0 | `https://helm.mattermost.com` |
| Nextcloud | 4.6.4 | `https://nextcloud.github.io/helm` |
| SeaweedFS | 3.67.0 | `https://seaweedfs.github.io/seaweedfs/helm` |
| Gitea | 10.1.1 | `https://dl.gitea.io/charts` |
| ArgoCD | 6.4.0 | `https://argoproj.github.io/argo-helm` |
| Kube-Prometheus | 56.21.1 | `https://prometheus-community.github.io/helm-charts` |
| Kyverno | 3.3.0 | `https://kyverno.github.io/kyverno` |

---

## Annexe B : Variables d'Environnement Importantes

### Sécurité

| Variable | Local | Staging | Production |
|----------|-------|---------|------------|
| `network_policies_enabled` | `false` | `true` | `true` |
| `network_policy_l7_enabled` | `false` | `true` | `true` |
| `kyverno_validation_failure_action` | `Audit` | `Audit` | `Enforce` |
| `kyverno_policy_require_probes` | `false` | `true` | `true` |

### Infrastructure

| Variable | Local | Staging | Production |
|----------|-------|---------|------------|
| `ha_enabled` | `false` | `false` | `true` |
| `longhorn_encryption` | `false` | `true` | `true` |
| `wireguard_enabled` | `false` | `true` | `true` |

---

Fin de l'audit de drift - Documentation et implémentation alignées.
