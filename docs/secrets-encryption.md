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
  │     Utilisateurs ──► Keycloak SSO (un seul mot de passe)            │
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
│  Vault        │  VAULT_DB_PW        │  Root token + 5 unseal keys          │
│               │  (PostgreSQL)        │  (Shamir threshold 3/5)              │
│               │                      │                                      │
│  Mattermost   │  MATTERMOST_DB_PW   │  Admin password (initial)            │
│               │  (PostgreSQL)        │  OIDC client via Keycloak            │
│               │                      │                                      │
│  Nextcloud    │  NEXTCLOUD_DB_PW     │  Admin password (initial)            │
│               │  (PostgreSQL)        │  OIDC client via Keycloak            │
│               │                      │  SeaweedFS S3 access/secret key      │
│               │                      │                                      │
│  Gitea        │  GITEA_DB_PW        │  Admin password (initial)            │
│               │  (PostgreSQL)        │  Proxy auth headers (pas de secret)  │
│               │                      │                                      │
│  ArgoCD       │  —                   │  Admin password (initial)            │
│               │                      │  OIDC client via Keycloak            │
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
  mattermost_user ──► CRUD only
  nextcloud_user  ──► CRUD only
  gitea_user      ──► CRUD only
  flipt_user      ──► CRUD only
  redcap_user     ──► CRUD only       (MariaDB)
```

L'isolation L7 Cilium garantit que chaque service ne peut acceder qu'a **sa propre base** au niveau reseau.

---

## Rotation des secrets

### Ce qui tourne, ce qui ne tourne pas

```text
  Secret                          Rotation    Mecanisme            Frequence
  ──────────────────────────────────────────────────────────────────────────────

  SECRETS DYNAMIQUES (rotation automatique)
  ──────────────────────────────────────────
  Certificats TLS (Let's Encrypt) Auto        Cert-Manager          90j (renew a 60j)
  Clefs WireGuard (inter-noeud)   Auto        Cilium                Transparente
  Sessions Keycloak               Auto        Keycloak (interne)    Transparente
  OIDC signing keys               Auto        Keycloak key rotation Configurable

  SECRETS STATIQUES (rotation via ESO polling)
  ─────────────────────────────────────────────
  Credentials BDD (PostgreSQL)    ESO poll    Vault KV v2 → ESO     24h refresh
  Credentials BDD (MariaDB)       ESO poll    Vault KV v2 → ESO     24h refresh
  Credentials BDD (Redis)         ESO poll    Vault KV v2 → ESO     24h refresh
  Mots de passe admin services    ESO poll    Vault KV v2 → ESO     7j refresh
  Clefs OIDC clients              ESO poll    Vault KV v2 → ESO     7j refresh

  SECRETS FIXES (jamais rotes automatiquement)
  ─────────────────────────────────────────────
  Vault root token                Jamais      Genere a l'init       Manuel (revoke/regen)
  Vault unseal keys (Shamir)      Jamais      Genere a l'init       Rekey manuel
  etcd encryption key             Jamais      Variable env           Manuel (procedure)
  Longhorn crypto key (LUKS)      Jamais      Variable env           Impossible (re-encrypt)
  K3s cluster token               Jamais      Variable env           Manuel (rotate-token)
  POSTGRES_SUPERUSER_PASSWORD     Jamais      Variable env           Manuel (ALTER ROLE)
```

> **Important** : « ESO poll » signifie qu'ESO interroge Vault selon le `refreshInterval`
> et met a jour le K8s Secret si la valeur a change dans Vault. Mais **la valeur elle-meme
> ne change que si quelqu'un (ou un processus) la met a jour dans Vault**. Aujourd'hui,
> aucun processus automatique ne fait cette mise a jour — la rotation reelle est manuelle.

### Mecanisme actuel (production)

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

Le label `security.atlas/rotation-enabled: "true"` identifie les secrets concernes.

### Frequences de synchronisation ESO

| Categorie | Refresh interval | Secrets concernes |
|-----------|-----------------|-------------------|
| Credentials BDD | **24 heures** | PostgreSQL, MariaDB, Redis passwords |
| Secrets plateforme | **7 jours** | Keycloak OIDC keys |
| Mots de passe admin | **7 jours** | Mattermost, Nextcloud, Gitea, ArgoCD, Grafana |

> **Note** : ces intervalles controlent la frequence de **synchronisation** Vault → K8s,
> pas la frequence de **rotation** des secrets eux-memes (qui est manuelle aujourd'hui).

---

## Evolution : Vault Database Secrets Engine

### Probleme actuel

Les credentials BDD sont **statiques** : generes une fois au deploiement, stockes dans
Vault KV v2, et jamais rotes automatiquement. Si un password est compromis, il reste
valide indefiniment.

```text
  Aujourd'hui (statique) :

  .env (bootstrap)
       │
       ▼
  Ansible ──► vault kv put secret/databases/postgresql keycloak-password=XXX
                                    │
                                    ▼
                           ExternalSecret (poll 24h)
                                    │
                                    ▼
                             K8s Secret ──► Pod
                             (password fixe, jamais rote)
```

### Solution : credentials ephemeres

Le [Vault Database Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/databases)
genere des credentials PostgreSQL **temporaires** avec un TTL. Vault cree un role
PostgreSQL a la volee, le pod l'utilise, et Vault le revoque a expiration.

```text
  Avec Database Secrets Engine (dynamique) :

  Pod ──► ESO ──► Vault database/creds/mattermost-role
                       │
                       ▼
                  Vault se connecte a PostgreSQL avec le superuser
                       │
                       ▼
                  CREATE ROLE temp_mattermost_a7f3 WITH PASSWORD '...'
                  GRANT SELECT, INSERT, UPDATE, DELETE ON mattermost.*
                       │
                       ▼
                  Retourne username + password (TTL 1h, renew jusqu'a 24h)
                       │
                       ▼
                  K8s Secret ──► Pod (credentials temporaires)
                       │
                       ▼
                  A expiration : DROP ROLE temp_mattermost_a7f3
```

### Ce que ca change

```text
  Secret                          Avant (KV v2)        Apres (Database Engine)
  ──────────────────────────────────────────────────────────────────────────────

  VAULT_DB_PASSWORD               .env (statique)      Supprime
  KEYCLOAK_DB_PASSWORD            .env (statique)      Supprime
  MATTERMOST_DB_PASSWORD          .env (statique)      Supprime
  NEXTCLOUD_DB_PASSWORD           .env (statique)      Supprime
  GITEA_DB_PASSWORD               .env (statique)      Supprime
  REDCAP_DB_PASSWORD              .env (statique)      Supprime
  FLIPT_DB_PASSWORD               .env (statique)      Supprime
  ──────────────────────────────────────────────────────────────────────────────
  Total : -7 variables dans .env

  POSTGRES_SUPERUSER_PASSWORD     .env (statique)      .env (statique) — INCHANGE
                                                       Vault en a besoin pour creer
                                                       les roles temporaires
```

### Configuration Vault necessaire

```text
  1. Activer le secrets engine

     vault secrets enable database

  2. Configurer la connexion PostgreSQL

     vault write database/config/postgresql \
       plugin_name=postgresql-database-plugin \
       connection_url="postgresql://{{username}}:{{password}}@postgresql-ha-pgpool.postgresql:5432/postgres?sslmode=require" \
       allowed_roles="*" \
       username="postgres" \
       password="$POSTGRES_SUPERUSER_PASSWORD"

  3. Creer un role par service (exemple : Mattermost)

     vault write database/roles/mattermost \
       db_name=postgresql \
       creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
         GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
       revocation_statements="DROP ROLE IF EXISTS \"{{name}}\";" \
       default_ttl=1h \
       max_ttl=24h

  4. Vault policy (par service)

     path "database/creds/mattermost" {
       capabilities = ["read"]
     }
```

### Roles et privileges (identiques a aujourd'hui)

| Role Vault | Base | Privileges SQL | TTL |
|------------|------|---------------|-----|
| `vault` | vault | ALL PRIVILEGES (schema owner) | 1h / max 24h |
| `keycloak` | keycloak | ALL PRIVILEGES (schema owner) | 1h / max 24h |
| `mattermost` | mattermost | SELECT, INSERT, UPDATE, DELETE | 1h / max 24h |
| `nextcloud` | nextcloud | SELECT, INSERT, UPDATE, DELETE | 1h / max 24h |
| `gitea` | gitea | SELECT, INSERT, UPDATE, DELETE | 1h / max 24h |
| `flipt` | flipt | SELECT, INSERT, UPDATE, DELETE | 1h / max 24h |
| `redcap` | redcap | SELECT, INSERT, UPDATE, DELETE | 1h / max 24h |

### Impact sur ExternalSecret

```yaml
# Avant (KV v2 — statique)
spec:
  secretStoreRef:
    name: vault-backend
  data:
    - secretKey: password
      remoteRef:
        key: secret/databases/postgresql
        property: mattermost-password

# Apres (Database Engine — dynamique)
spec:
  secretStoreRef:
    name: vault-backend
  dataFrom:
    - extract:
        key: database/creds/mattermost
  # Retourne automatiquement : username + password
  # Refresh = TTL/2 pour renouveler avant expiration
  refreshInterval: 30m
```

### Pre-requis et contraintes

- **Vault doit etre unseal et accessible** pour que les pods demarrent (dependance forte)
- Les applications doivent tolerer un **changement de username** (pas juste de password)
- Le `refreshInterval` ESO doit etre < TTL/2 pour eviter l'expiration en vol
- PostgreSQL `max_connections` doit etre suffisant pour les roles temporaires cumules
- MariaDB/Redis ne supportent pas le Database Secrets Engine — restent en KV v2

### Tableau de rotation final (apres migration)

```text
  Secret                          Rotation    Frequence        Mecanisme
  ──────────────────────────────────────────────────────────────────────────────

  ROTATION AUTOMATIQUE
  ────────────────────
  Credentials BDD PostgreSQL      Auto        TTL 1h (max 24h) Vault Database Engine
  Certificats TLS                 Auto        90j              Cert-Manager
  Clefs WireGuard                 Auto        Transparente     Cilium
  Sessions Keycloak               Auto        Transparente     Keycloak
  OIDC signing keys               Auto        Configurable     Keycloak

  SYNCHRONISATION PERIODIQUE (valeur statique dans Vault)
  ───────────────────────────────────────────────────────
  Redis password                  ESO poll    24h              KV v2 (pas de DB engine)
  MariaDB passwords (REDCap)      ESO poll    24h              KV v2 (pas de DB engine)
  Mots de passe admin services    ESO poll    7j               KV v2
  OIDC client secrets             ESO poll    7j               KV v2

  JAMAIS ROTES AUTOMATIQUEMENT
  ────────────────────────────
  Vault root token                Manuel      —                vault token revoke + regen
  Vault unseal keys               Manuel      —                vault operator rekey
  etcd encryption key             Manuel      —                Procedure 4 etapes
  Longhorn crypto key             Jamais      —                Non rotable (LUKS)
  K3s cluster token               Manuel      —                k3s token rotate
  PostgreSQL superuser            Manuel      —                ALTER ROLE (Vault en depend)
  SMTP credentials (Brevo)        Manuel      —                Externe (provider)
  SeaweedFS S3 keys               Manuel      —                Externe (SeaweedFS admin)
```

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

  Sessions Keycloak       HMAC-SHA256      Geree par Keycloak       Automatique
                                           (interne au realm)
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

  7  Application     Keycloak SSO                   tous
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
