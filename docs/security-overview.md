# Securite Reseau & Authentification - ATLAS Platform

**Date** : 2026-02-10

Vue d'ensemble de la posture de securite du cluster : comptes utilisateurs, secrets applicatifs, certificats, clefs de chiffrement, couches d'authentification et flux reseau.

---

## Comptes utilisateurs

### Modele d'identite

Les utilisateurs sont geres dans Authelia (fichier `/config/users_database.yml`).
En production, ce fichier est alimente par un annuaire externe (LDAP).
En local, trois comptes de test sont crees automatiquement.

```text
  ┌────────────────────────────────────────────────────────────────┐
  │                    Authelia (Identity Provider)                 │
  │                                                                │
  │   Utilisateur ──► Mot de passe (Argon2id) ──► Session cookie   │
  │        │                                          │            │
  │        ├──► TOTP / WebAuthn (2FA optionnel)       │            │
  │        │                                          ▼            │
  │        └──► Groupes (admins/devops/researchers/users)          │
  │                          │                                     │
  │                          ▼                                     │
  │              ┌──── OIDC Provider ────┐                         │
  │              │  Claims : sub, email, │                         │
  │              │  name, groups         │                         │
  │              └───────────┬──────────┘                          │
  └──────────────────────────┼────────────────────────────────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
        ┌─────▼────┐  ┌─────▼────┐  ┌─────▼────┐
        │Mattermost│  │ Nextcloud│  │  ArgoCD  │  ...
        │(OIDC SSO)│  │(OIDC SSO)│  │(OIDC SSO)│
        └──────────┘  └──────────┘  └──────────┘
```

### Authentification : pas de mot de passe utilisateur

Les utilisateurs finaux **ne gerent aucun mot de passe applicatif**. Le flux est :

1. L'utilisateur accede a un service (ex: `chat.<domain>`)
2. Envoy Gateway redirige vers le portail Authelia (`login.<domain>`)
3. L'utilisateur s'authentifie une seule fois (SSO)
4. Le cookie de session (`atlas_session`) est partage sur `*.<domain>`
5. Les services recoivent les headers `Remote-User`, `Remote-Groups`, `Remote-Email`

Les services qui utilisent OIDC (Mattermost, Nextcloud, ArgoCD, ECRIN) recoivent un token JWT signe par Authelia contenant les claims `sub`, `email`, `groups`.

Les services en mode proxy auth (Gitea, Grafana) font confiance aux headers injectes par Authelia et creent automatiquement le compte utilisateur au premier acces.

### Sessions et politique de mots de passe

```text
  Session
  ├── Cookie         : atlas_session
  ├── Domaine        : *.<domain> (partage entre services)
  ├── Duree          : 1 heure
  ├── Inactivite     : 5 minutes (deconnexion auto)
  ├── Remember me    : 1 mois
  └── Stockage       : Redis (HA) ou memoire (local)

  Politique de mot de passe (Authelia)
  ├── Longueur min   : 12 caracteres
  ├── Majuscule      : obligatoire
  ├── Minuscule      : obligatoire
  ├── Chiffre        : obligatoire
  ├── Special        : obligatoire
  └── Hachage        : Argon2id (m=64Mo, t=3, p=4)

  Protection brute force
  ├── Tentatives max : 3
  ├── Fenetre        : 2 minutes
  └── Ban            : 5 minutes
```

### Second facteur (MFA)

| Methode  | Protocole    | Usage                                              |
| -------- | ------------ | -------------------------------------------------- |
| TOTP     | RFC 6238     | Application (Google Auth, Authy) — periode 30s     |
| WebAuthn | FIDO2/Passkeys| Clef physique (YubiKey) ou biometrie (Touch ID)   |

Le MFA est **obligatoire** pour les services critiques (Vault, ArgoCD, REDCap) et optionnel pour les autres.

---

## Secrets applicatifs

### Vue d'ensemble : aucun mot de passe utilisateur, que des secrets machines

```text
  ┌──────────────────────────────────────────────────────────────────────┐
  │                                                                      │
  │     Utilisateurs ──► Authelia SSO (un seul mot de passe + MFA)       │
  │                                                                      │
  │     Applications ──► Secrets machines geres par Vault + ESO :        │
  │                      ● Mots de passe BDD (generes, uniques)          │
  │                      ● Clefs OIDC / JWT (generes, RSA 4096)          │
  │                      ● Tokens admin (generes, non partages)          │
  │                                                                      │
  └──────────────────────────────────────────────────────────────────────┘
```

### Circuit des secrets

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

### Inventaire des secrets par service

```text
┌───────────────┬──────────────────────┬──────────────────────────────────────┐
│   Service     │   Secret BDD         │   Autres secrets                     │
├───────────────┼──────────────────────┼──────────────────────────────────────┤
│               │                      │                                      │
│  Authelia     │  AUTHELIA_DB_PASSWORD │  JWT_SECRET                          │
│               │  (PostgreSQL)        │  SESSION_SECRET                      │
│               │                      │  OIDC_HMAC_SECRET                    │
│               │                      │  OIDC_PRIVATE_KEY (RSA 4096)         │
│               │                      │  STORAGE_ENCRYPTION_KEY              │
│               │                      │                                      │
│  Vault        │  VAULT_DB_PASSWORD   │  Root token + 5 unseal keys          │
│               │  (PostgreSQL)        │  (Shamir threshold 3/5)              │
│               │                      │                                      │
│  Mattermost   │  MATTERMOST_DB_PW   │  Admin password (initial)            │
│               │  (PostgreSQL)        │  OIDC client via Authelia            │
│               │                      │                                      │
│  Nextcloud    │  NEXTCLOUD_DB_PW     │  Admin password (initial)            │
│               │  (PostgreSQL)        │  OIDC client via Authelia            │
│               │                      │  SeaweedFS S3 access/secret key      │
│               │                      │                                      │
│  Gitea        │  GITEA_DB_PW        │  Admin password (initial)            │
│               │  (PostgreSQL)        │  Proxy auth headers (pas de secret)  │
│               │                      │                                      │
│  ArgoCD       │  —                   │  Admin password (initial)            │
│               │                      │  OIDC client via Authelia            │
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
│  ECRIN        │  —                   │  OIDC client secret (partage         │
│               │                      │  avec Authelia config)               │
│               │                      │                                      │
│  SeaweedFS    │  —                   │  S3_ACCESS_KEY + S3_SECRET_KEY       │
│               │                      │                                      │
│  PostgreSQL   │  SUPERUSER_PW       │  REPLICATION_PW                      │
│  MariaDB      │  ROOT_PW            │  REPLICATION_PW                      │
│  Redis        │  REDIS_PASSWORD      │  —                                   │
│               │                      │                                      │
└───────────────┴──────────────────────┴──────────────────────────────────────┘
```

### Privileges base de donnees

Chaque service dispose d'un utilisateur dedie avec le minimum de privileges :

```text
  vault_user      ──► ALL PRIVILEGES  (schema owner, migrations)
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

| Categorie               | Refresh interval | Secrets concernes                               |
| ------------------------ | ---------------- | ----------------------------------------------- |
| Credentials BDD         | **24 heures**    | PostgreSQL, MariaDB, Redis passwords            |
| Secrets plateforme       | **7 jours**      | Authelia JWT, session, OIDC keys                |
| Mots de passe admin     | **7 jours**      | Mattermost, Nextcloud, Gitea, ArgoCD, Grafana   |

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

| Issuer               | Type         | Environnement | Validite         |
| -------------------- | ------------ | ------------- | ---------------- |
| `selfsigned-issuer`  | Self-signed  | local         | N/A              |
| `letsencrypt-staging`| ACME staging | staging       | 90 jours (auto)  |
| `letsencrypt-prod`   | ACME prod    | production    | 90 jours (auto)  |

### Certificats emis

```text
  Certificats services (wildcard *.<domain>)
  ├── authelia-tls        (login.<domain>)
  ├── vault-tls           (vault.<domain>)
  ├── argocd-tls          (argocd.<domain>)
  ├── gitea-tls           (git.<domain>)
  ├── grafana-tls         (grafana.<domain>)
  ├── mattermost-tls      (chat.<domain>)
  ├── nextcloud-tls       (cloud.<domain>)
  ├── onlyoffice-tls      (office.<domain>)
  ├── redcap-tls          (redcap.<domain>)
  ├── ecrin-tls           (ecrin.<domain>)
  ├── flipt-tls           (flags.<domain>)
  └── hubble-tls          (hubble.<domain>)

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

### Clefs critiques a sauvegarder hors-cluster

| Clef                     | Emplacement                                    | Consequence si perdue                 |
| ------------------------ | ---------------------------------------------- | ------------------------------------- |
| Vault unseal keys (3/5)  | `/root/.vault-init-{timestamp}.yml`            | Vault inaccessible apres redemarrage  |
| Vault root token         | `/root/.vault-init-{timestamp}.yml`            | Plus d'acces admin a Vault            |
| etcd encryption key      | `/etc/rancher/k3s/encryption-config.yaml`      | Secrets K8s illisibles apres restore  |
| Longhorn crypto key      | Secret `longhorn-crypto`                       | Volumes PVC illisibles                |
| K3s cluster token        | Variable d'env `K3S_TOKEN`                     | Impossible d'ajouter des noeuds       |

---

## Architecture d'authentification

```text
                          INTERNET
                             │
                     ┌───────▼────────┐
                     │  Envoy Gateway │
                     │  (LoadBalancer)│
                     │  ports 80/443  │
                     └───────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
      ┌───────▼──────┐  ┌───▼───┐  ┌───────▼──────┐
      │  HTTPRoute   │  │ Auth  │  │  HTTPRoute   │
      │  (protege)   │  │ login │  │  (API/hook)  │
      │  PathPrefix /│  │ .dom  │  │  PathPrefix  │
      └───────┬──────┘  └───┬───┘  │  specifique  │
              │              │      └───────┬──────┘
     ┌────────▼────────┐    │              │
     │ SecurityPolicy  │    │              │
     │ ┌─────────────┐ │    │              │
     │ │  ext-authz   │◄────┘              │
     │ │  → Authelia  │ │                  │
     │ └─────────────┘ │                  │
     └────────┬────────┘                  │
              │                            │
              │  ✓ Authentifie             │ Token/HMAC
              ▼                            ▼
         ┌─────────┐                 ┌─────────┐
         │ Service │                 │ Service │
         │ Backend │                 │ Backend │
         └─────────┘                 └─────────┘
```

**Principe** : Toute requete passe par Envoy Gateway.
Les routes principales (`/`) sont protegees par une SecurityPolicy qui consulte Authelia.
Les routes API/webhook sont sur des HTTPRoutes separees sans SecurityPolicy —
elles utilisent l'authentification applicative (tokens, HMAC).

---

## Matrice de protection par service

```text
┌──────────────┬─────────────────┬──────────┬──────────────────────────────────┐
│   Service    │     Domaine     │   Auth   │       Chemins exemptes           │
├──────────────┼─────────────────┼──────────┼──────────────────────────────────┤
│              │                 │          │                                  │
│  Authelia    │  login.<dom>    │ provider │  (portail d'authentification)    │
│              │                 │          │                                  │
├──────────────┼─────────────────┼──────────┼──────────────────────────────────┤
│              │                 │          │                                  │
│  Vault       │  vault.<dom>    │ 2FA ●●   │  /v1/sys/health                  │
│              │                 │ adm+dev  │  /v1/auth/  /v1/secret/          │
│              │                 │          │  /v1/sys/                        │
│              │                 │          │                                  │
│  ArgoCD      │  argocd.<dom>   │ 2FA ●●   │  /api/webhook                    │
│              │                 │ adm+dev  │                                  │
│              │                 │          │                                  │
│  REDCap      │  redcap.<dom>   │ 2FA ●●   │  /surveys                        │
│              │                 │ rch+adm  │  (repondants non authentifies)   │
│              │                 │          │                                  │
├──────────────┼─────────────────┼──────────┼──────────────────────────────────┤
│              │                 │          │                                  │
│  Hubble UI   │  hubble.<dom>   │ 1FA ●    │  aucun                           │
│              │                 │ dev+adm  │                                  │
│              │                 │          │                                  │
│  ECRIN       │  ecrin.<dom>    │ 1FA ●    │  aucun                           │
│              │                 │ rch+adm  │                                  │
│              │                 │          │                                  │
│  Flipt       │  flags.<dom>    │ 1FA ●    │  aucun                           │
│              │                 │ dev+adm  │                                  │
│              │                 │          │                                  │
├──────────────┼─────────────────┼──────────┼──────────────────────────────────┤
│              │                 │          │                                  │
│  Grafana     │  grafana.<dom>  │ 1FA ●    │  /api/                           │
│              │                 │ tous     │                                  │
│              │                 │          │                                  │
│  Gitea       │  git.<dom>      │ 1FA ●    │  /api/v1/  /.well-known/         │
│              │                 │ tous     │                                  │
│              │                 │          │                                  │
│  Nextcloud   │  cloud.<dom>    │ 1FA ●    │  /remote.php/dav/  /ocs/         │
│              │                 │ tous     │  /.well-known/                   │
│              │                 │          │                                  │
│  Mattermost  │  chat.<dom>     │ 1FA ●    │  /api/v4/  /plugins/  /hooks/    │
│              │                 │ tous     │                                  │
│              │                 │          │                                  │
│  OnlyOffice  │  office.<dom>   │ 1FA ●    │  /coauthoring/                   │
│              │                 │ tous     │                                  │
│              │                 │          │                                  │
└──────────────┴─────────────────┴──────────┴──────────────────────────────────┘

Legende :  2FA ●● = mot de passe + TOTP/WebAuthn
           1FA ●  = mot de passe
           adm = admins   dev = devops   rch = researchers   tous = all authenticated
```

---

## Couches de securite

```text
     Couche                 Composant               Environnement
    ─────────────────────────────────────────────────────────────────

  7  Application     Authelia Forward Auth          local/staging/prod
                     (SecurityPolicy par route)
                     ● SSO, OIDC, MFA
                     ● Groupes : admins/devops/
                       researchers/users

  6  Rate Limiting   Cilium + Envoy Gateway         staging/prod
                     ● Par service (ex: 50 RPS)
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

---

## Flux reseau par namespace

```text
                    ┌─────────────────────────────────────────┐
                    │            envoy-gateway-system          │
                    │  ┌────────────────────────────────────┐  │
  INTERNET ────────►│  │     Envoy Gateway (LB 80/443)     │  │
                    │  └──────────────┬─────────────────────┘  │
                    └─────────────────┼────────────────────────┘
                                      │
         ┌───────────────┬────────────┼────────────┬───────────────┐
         │               │            │            │               │
         ▼               ▼            ▼            ▼               ▼
  ┌─────────────┐ ┌───────────┐ ┌─────────┐ ┌──────────┐ ┌──────────┐
  │  authelia   │ │ mattermost│ │nextcloud│ │  gitea   │ │ argocd   │
  │  port 9091  │ │ port 8065 │ │port 8080│ │port 3000 │ │ port 80  │
  └──────┬──────┘ └─────┬─────┘ └────┬────┘ └────┬─────┘ └────┬─────┘
         │              │            │            │            │
         │              │            │            │            │
         ▼              ▼            ▼            ▼            ▼
  ┌─────────────────────────────────────────────────────────────────┐
  │                        postgresql (5432)                        │
  │  authelia_db │ mattermost_db │ nextcloud_db │ gitea_db │ ...   │
  │  (L7 isolation : chaque service → sa base uniquement)          │
  └─────────────────────────────────────────────────────────────────┘
         │
         ▼
  ┌─────────────┐     ┌──────────────┐
  │ redis (6379)│     │ vault (8200) │
  │ sessions    │     │ secrets      │
  └─────────────┘     └──────────────┘
```

---

## Mecanisme Forward Auth (detail)

```text
  Navigateur                  Envoy Gateway          Authelia            Service
      │                            │                    │                   │
      │  GET https://chat.<dom>/   │                    │                   │
      ├───────────────────────────►│                    │                   │
      │                            │                    │                   │
      │                  SecurityPolicy                 │                   │
      │                  ext-authz check                │                   │
      │                            ├───────────────────►│                   │
      │                            │  GET /api/authz/   │                   │
      │                            │  ext-authz         │                   │
      │                            │  + cookies         │                   │
      │                            │                    │                   │
      │                            │◄───────────────────┤                   │
      │                            │  401 Unauthorized  │                   │
      │                            │  + redirect URL    │                   │
      │                            │                    │                   │
      │◄───────────────────────────┤                    │                   │
      │  302 → login.<dom>/?rd=... │                    │                   │
      │                            │                    │                   │
      │  ══════ Utilisateur se connecte (1FA/2FA) ═════ │                   │
      │                            │                    │                   │
      │  GET https://chat.<dom>/   │                    │                   │
      │  + cookie atlas_session    │                    │                   │
      ├───────────────────────────►│                    │                   │
      │                            ├───────────────────►│                   │
      │                            │  GET /api/authz/   │                   │
      │                            │  + cookie valid    │                   │
      │                            │                    │                   │
      │                            │◄───────────────────┤                   │
      │                            │  200 OK            │                   │
      │                            │  + Remote-User     │                   │
      │                            │  + Remote-Groups   │                   │
      │                            │  + Remote-Email    │                   │
      │                            │                    │                   │
      │                            ├────────────────────────────────────────►
      │                            │  Requete + headers │                   │
      │                            │                    │                   │
      │◄───────────────────────────┤◄───────────────────────────────────────┤
      │  200 OK (page Mattermost)  │                    │                   │
```

---

## Controle d'acces par groupe

```text
  ┌─────────┐   ┌─────────┐   ┌────────────┐   ┌─────────┐
  │ admins  │   │ devops  │   │researchers │   │  users  │
  └────┬────┘   └────┬────┘   └─────┬──────┘   └────┬────┘
       │             │              │                │
       ├─── Vault (2FA) ◄───┘              │                │
       ├─── ArgoCD (2FA) ◄──┘              │                │
       ├─── REDCap (2FA) ◄────────────────┘                │
       │                                                    │
       ├─── Hubble UI (1FA) ◄───┘              │                │
       ├─── Flipt (1FA) ◄───────┘              │                │
       ├─── ECRIN (1FA) ◄──────────────────────┘                │
       │                                                        │
       ├─── Grafana (1FA) ◄──────────◄──────────◄──────────────┘
       ├─── Gitea (1FA) ◄────────────◄──────────◄──────────────┘
       ├─── Nextcloud (1FA) ◄────────◄──────────◄──────────────┘
       ├─── Mattermost (1FA) ◄───────◄──────────◄──────────────┘
       └─── OnlyOffice (1FA) ◄───────◄──────────◄──────────────┘
```

| Groupe       | Services accessibles                                                         |
| ------------ | ---------------------------------------------------------------------------- |
| `admins`     | Tous les services (2FA pour Vault, ArgoCD, REDCap)                          |
| `devops`     | Vault, ArgoCD, Hubble, Flipt + services generaux (Grafana, Gitea, etc.)    |
| `researchers`| REDCap, ECRIN + services generaux                                           |
| `users`      | Services generaux : Grafana, Gitea, Nextcloud, Mattermost, OnlyOffice      |

---

## Rollback & desactivation

Chaque service dispose d'une variable `*_forward_auth_enabled` dans son `defaults/main.yml` :

```bash
# Desactiver le forward auth pour un service specifique
# 1. Modifier la variable dans group_vars ou via extra-vars
ansible-playbook playbooks/phase-05-services.yml --tags mattermost \
  -e mattermost_forward_auth_enabled=false

# 2. Ou editer defaults/main.yml et redeployer
```

| Variable                        | Fichier                                               |
| ------------------------------- | ----------------------------------------------------- |
| `vault_forward_auth_enabled`    | `roles/platform/vault/defaults/main.yml`              |
| `argocd_forward_auth_enabled`   | `roles/devops/argocd/defaults/main.yml`               |
| `gitea_forward_auth_enabled`    | `roles/devops/gitea/defaults/main.yml`                |
| `grafana_forward_auth_enabled`  | `roles/monitoring/kube_prometheus/defaults/main.yml`   |
| `redcap_forward_auth_enabled`   | `roles/services/redcap/defaults/main.yml`             |
| `nextcloud_forward_auth_enabled`| `roles/services/nextcloud/defaults/main.yml`          |
| `mattermost_forward_auth_enabled`| `roles/services/mattermost/defaults/main.yml`        |
| `ecrin_forward_auth_enabled`    | `roles/services/ecrin/defaults/main.yml`              |
| `flipt_forward_auth_enabled`    | `roles/services/flipt/defaults/main.yml`              |
| `onlyoffice_forward_auth_enabled`| `roles/services/onlyoffice/defaults/main.yml`        |
| `hubble_ui_forward_auth_enabled`| `roles/monitoring/hubble_ui/defaults/main.yml`        |
