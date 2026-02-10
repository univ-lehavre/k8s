# Secrets et chiffrement

**Date** : 2026-02-10

Gestion des secrets applicatifs, certificats TLS, clefs de chiffrement et rotation.

> Pour l'authentification utilisateur et le SSO, voir [Authentification](./authentication.md).
> Pour les regles d'acces par service, voir [Autorisations](./authorization.md).
> Pour l'architecture reseau et les flux, voir [Flux reseau](./network-flows.md).

---

## Principe : pas de mot de passe utilisateur, que des secrets machines

```text
  ┌──────────────────────────────────────────────────────────────────────┐
  │                                                                      │
  │     Utilisateurs ──► Keycloak/Authelia SSO (un seul mot de passe)   │
  │                                                                      │
  │     Applications ──► Secrets machines geres par Vault + ESO :        │
  │                      ● Mots de passe BDD (generes, uniques)          │
  │                      ● Clefs OIDC / JWT (generes, RSA 4096)          │
  │                      ● Tokens admin (generes, non partages)          │
  │                                                                      │
  └──────────────────────────────────────────────────────────────────────┘
```

---

## Circuit des secrets

```text
  1. Generation               2. Stockage              3. Distribution
  ─────────────               ──────────               ────────────────

  Ansible                     Vault KV v2              External Secrets
  lookup('password')  ──────► secret/platform/...  ──► ExternalSecret
  openssl genrsa 4096         secret/databases/...     ──► K8s Secret
                              secret/services/...      ──► Pod env/volume
```

- **Production/staging** : les secrets sont generes au premier deploiement par Ansible, stockes dans Vault, puis synchronises vers Kubernetes via External Secrets Operator (ESO)
- **Local** : les secrets sont generes a la volee par Ansible et injectes directement en tant que Kubernetes Secrets (pas de Vault)

---

## Inventaire des secrets par service

```text
┌───────────────┬──────────────────────┬──────────────────────────────────────┐
│   Service     │   Secret BDD         │   Autres secrets                     │
├───────────────┼──────────────────────┼──────────────────────────────────────┤
│               │                      │                                      │
│  Keycloak     │  KEYCLOAK_DB_PW     │  Admin password                      │
│               │  (PostgreSQL)        │  Secrets clients OIDC (par service)  │
│               │                      │                                      │
│  Authelia     │  AUTHELIA_DB_PW     │  JWT_SECRET                          │
│               │  (PostgreSQL)        │  SESSION_SECRET                      │
│               │                      │  OIDC_HMAC_SECRET                    │
│               │                      │  OIDC_PRIVATE_KEY (RSA 4096)         │
│               │                      │  STORAGE_ENCRYPTION_KEY              │
│               │                      │                                      │
│  Vault        │  VAULT_DB_PW        │  Root token + 5 unseal keys          │
│               │  (PostgreSQL)        │  (Shamir threshold 3/5)              │
│               │                      │                                      │
│  Mattermost   │  MATTERMOST_DB_PW   │  Admin password (initial)            │
│               │  (PostgreSQL)        │  OIDC client via Keycloak/Authelia   │
│               │                      │                                      │
│  Nextcloud    │  NEXTCLOUD_DB_PW     │  Admin password (initial)            │
│               │  (PostgreSQL)        │  OIDC client via Keycloak/Authelia   │
│               │                      │  SeaweedFS S3 access/secret key      │
│               │                      │                                      │
│  Gitea        │  GITEA_DB_PW        │  Admin password (initial)            │
│               │  (PostgreSQL)        │  Proxy auth headers (pas de secret)  │
│               │                      │                                      │
│  ArgoCD       │  —                   │  Admin password (initial)            │
│               │                      │  OIDC client via Keycloak/Authelia   │
│               │                      │                                      │
│  Grafana      │  —                   │  Admin password (initial)            │
│               │                      │  Proxy auth headers (pas de secret)  │
│               │                      │                                      │
│  REDCap       │  REDCAP_DB_PW       │  REDCAP_SALT                         │
│               │  (MariaDB)           │                                      │
│               │                      │                                      │
│  Flipt        │  FLIPT_DB_PW        │  (auth interne token-based)          │
│               │  (PostgreSQL)        │                                      │
│               │                      │                                      │
│  OnlyOffice   │  —                   │  JWT_SECRET (WOPI/Nextcloud)         │
│               │                      │                                      │
│  ECRIN        │  —                   │  OIDC client secret                  │
│               │                      │                                      │
│  SeaweedFS    │  —                   │  S3_ACCESS_KEY + S3_SECRET_KEY       │
│               │                      │                                      │
│  PostgreSQL   │  SUPERUSER_PW       │  REPLICATION_PW                      │
│  MariaDB      │  ROOT_PW            │  REPLICATION_PW                      │
│  Redis        │  REDIS_PASSWORD      │  —                                   │
│               │                      │                                      │
└───────────────┴──────────────────────┴──────────────────────────────────────┘
```

---

## Privileges base de donnees

Chaque service dispose d'un utilisateur dedie avec le minimum de privileges :

```text
  vault_user      ──► ALL PRIVILEGES  (schema owner, migrations)
  keycloak_user   ──► ALL PRIVILEGES  (schema owner, migrations)
  authelia_user   ──► CRUD only       (SELECT, INSERT, UPDATE, DELETE)
  mattermost_user ──► CRUD only
  nextcloud_user  ──► CRUD only
  gitea_user      ──► CRUD only
  flipt_user      ──► CRUD only
  redcap_user     ──► CRUD only       (MariaDB)
```

L'isolation L7 Cilium garantit que chaque service ne peut acceder qu'a **sa propre base** au niveau reseau.

---

## Rotation des secrets

### Mecanisme automatique (production)

```text
  ┌──────────┐    refreshInterval    ┌──────────────────┐     ┌────────────┐
  │  Vault   │ ◄─────────────────── │ ExternalSecret    │ ──► │ K8s Secret │
  │  KV v2   │    (interrogation)    │ (ESO controller)  │     │ (mis a jour│
  └──────────┘                       └──────────────────┘     │ si change) │
                                                               └──────┬─────┘
                                                                      │
                                                              Redemarrage
                                                              manuel requis
```

### Frequences de rotation

| Categorie | Refresh interval | Secrets concernes |
|-----------|-----------------|-------------------|
| Credentials BDD | **24 heures** | PostgreSQL, MariaDB, Redis passwords |
| Secrets plateforme | **7 jours** | Authelia JWT, session, OIDC keys |
| Mots de passe admin | **7 jours** | Mattermost, Nextcloud, Gitea, ArgoCD, Grafana |

> **Note** : la rotation met a jour le Kubernetes Secret mais les pods doivent etre
> redemares manuellement pour prendre en compte les nouveaux secrets.
> Un label `security.atlas/rotation-enabled: "true"` identifie les secrets concernes.

---

## Certificats TLS

### Cycle de vie automatique

```text
  Cert-Manager          ACME (Let's Encrypt)       Envoy Gateway
  ──────────────        ────────────────────       ──────────────

  Certificate CR  ───►  Challenge HTTP-01    ───►  Wildcard TLS
  (par service)         via Envoy Gateway          *.<domain>
       │                                               │
       │           Renouvellement auto                 │
       └───────────  30j avant expiration  ────────────┘
```

### ClusterIssuers disponibles

| Issuer | Type | Environnement | Validite |
|--------|------|---------------|----------|
| `selfsigned-issuer` | Self-signed | local | N/A |
| `letsencrypt-staging` | ACME staging | staging | 90 jours (auto) |
| `letsencrypt-prod` | ACME prod | production | 90 jours (auto) |

### Certificats emis

```text
  Certificat wildcard (*.<domain>)
  └── wildcard-tls (ns: envoy-gateway-system)

  Certificats internes (bases de donnees, staging/prod)
  ├── postgresql-tls      (postgresql.postgresql.svc.cluster.local)
  │                       SANs: *.postgresql-hl.postgresql.svc.cluster.local
  └── mariadb-tls         (mariadb.mariadb.svc.cluster.local)
                          SANs: mariadb-primary.*, mariadb-secondary.*
```

Le renouvellement est **entierement automatique**. Cert-Manager renouvelle 30 jours avant expiration ; aucune intervention manuelle requise.

---

## Clefs de chiffrement

### Vue d'ensemble

```text
  Couche                  Algorithme       Gestion des clefs        Rotation
  ─────────────────────────────────────────────────────────────────────────────

  etcd at rest            AES-CBC 256      Manuelle (env var)       Manuelle
                          (K8s Secrets)    ETCD_ENCRYPTION_KEY      (procedure)

  Volumes Longhorn        LUKS             Manuelle (env var)       Non
                          (block device)   LONGHORN_CRYPTO_KEY      (clef maitre)

  Reseau inter-noeud      WireGuard        Automatique (Cilium)     Automatique
                          (Curve25519)     Clefs par noeud          (transparente)

  OIDC tokens             RSA 4096         Generee par Ansible      7 jours (ESO)
                          (signature JWT)  stockee dans Vault

  Sessions Authelia       HMAC-SHA256      Generee par Ansible      7 jours (ESO)
                                           stockee dans Vault
```

### etcd — chiffrement au repos

```text
  kube-apiserver
       │
       ├── encryption-provider-config
       │   └── /etc/rancher/k3s/encryption-config.yaml (mode 0600)
       │       ├── provider: aescbc
       │       └── key: ETCD_ENCRYPTION_KEY (256-bit, base64)
       │
       └── Ressources chiffrees : Secrets uniquement
```

La rotation de la clef etcd est **manuelle** :

1. Ajouter la nouvelle clef en premiere position dans la config
2. Redemarrer le kube-apiserver
3. Re-chiffrer tous les secrets : `kubectl get secrets --all-namespaces -o json | kubectl replace -f -`
4. Retirer l'ancienne clef

### Longhorn — chiffrement des volumes

```text
  StorageClass: longhorn-encrypted (defaut)
       │
       └── Secret: longhorn-crypto (ns: longhorn-system)
           ├── CRYPTO_KEY_VALUE : LONGHORN_CRYPTO_KEY (256-bit, base64)
           └── CRYPTO_KEY_PROVIDER : secret

  Chaque PVC → chiffrement LUKS au niveau block device
```

### WireGuard — chiffrement reseau

```text
  Cilium Agent (par noeud)
       │
       └── Genere automatiquement :
           ├── Clef privee WireGuard (Curve25519)
           ├── Clef publique (echangee entre noeuds)
           └── Rotation automatique et transparente
```

---

## Clefs critiques a sauvegarder hors-cluster

| Clef | Emplacement | Consequence si perdue |
|------|-------------|----------------------|
| Vault unseal keys (3/5) | `/root/.vault-init-{timestamp}.yml` | Vault inaccessible apres redemarrage |
| Vault root token | `/root/.vault-init-{timestamp}.yml` | Plus d'acces admin a Vault |
| etcd encryption key | `/etc/rancher/k3s/encryption-config.yaml` | Secrets K8s illisibles apres restore |
| Longhorn crypto key | Secret `longhorn-crypto` | Volumes PVC illisibles |
| K3s cluster token | Variable d'env `K3S_TOKEN` | Impossible d'ajouter des noeuds |

---

## Couches de securite

```text
     Couche                 Composant               Environnement
    ─────────────────────────────────────────────────────────────────

  7  Application     Keycloak/Authelia SSO          staging-prod / local
                     (SecurityPolicy par route)
                     ● SSO, OIDC, MFA
                     ● Groupes : admins/devops/
                       researchers/users

  6  Rate Limiting   Cilium + Envoy Gateway         staging/prod
                     ● Par service
                     ● Protection slow loris

  5  Network Policy  Cilium CiliumNetworkPolicy     staging/prod
                     ● Default deny ingress+egress
                     ● L7 PostgreSQL isolation
                     ● Regles explicites par NS

  4  Pod Security    Kyverno + PSS                  staging/prod
                     ● 8 ClusterPolicies
                     ● Audit (staging)
                     ● Enforce (production)

  3  TLS             Cert-Manager + Let's Encrypt   staging/prod
                     ● Wildcard *.<domain>
                     ● Auto-renouvellement

  2  Chiffrement     etcd encryption at rest        staging/prod
                     Longhorn volume encryption      prod
                     WireGuard (inter-node)          prod

  1  Systeme         SSH key-only + Fail2ban        staging/prod
                     UFW + AppArmor + AIDE
                     Auditd
```
