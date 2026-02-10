# Authentification et gestion des utilisateurs

**Date** : 2026-02-10

Gestion des identites, fournisseurs SSO et methodes d'authentification par application.

---

## Fournisseurs d'identite

La plateforme utilise un fournisseur SSO conditionnel selon l'environnement :

| Environnement | Fournisseur | URL | Description |
|---------------|-------------|-----|-------------|
| **Local** | Authelia | `login.<domain>` | Fichier YAML, comptes de test, pas de base externe |
| **Staging** | Keycloak | `login.<domain>` | IAM complet, auto-enregistrement, console admin |
| **Production** | Keycloak | `login.<domain>` | IAM complet, HA (2 replicas), MFA obligatoire |

Le basculement est pilote par la variable `keycloak_enabled` :

```text
  local       → keycloak_enabled: false  → Authelia
  staging     → keycloak_enabled: true   → Keycloak
  production  → keycloak_enabled: true   → Keycloak
```

---

## Keycloak (staging / production)

### Fonctionnalites

- **SSO via OIDC** : fournisseur OpenID Connect pour toutes les applications
- **Console d'administration** : gestion des utilisateurs, groupes, roles via interface web
- **Auto-enregistrement** : les nouveaux utilisateurs creent leur compte eux-memes
- **Verification email** : adresse email verifiee avant activation du compte
- **Restriction domaine** : limitation optionnelle aux domaines email autorises (ex: `univ-lehavre.fr`)
- **MFA** : TOTP (Google Authenticator, Authy) et WebAuthn (YubiKey, Touch ID)
- **Reset password** : reinitialisation par email sans intervention administrateur

### Realm

```text
  Realm : atlas
  ├── Host           : login.<domain>
  ├── Groupes        : admins, devops, researchers, users
  ├── Groupe defaut  : users (auto-assigne a l'inscription)
  ├── SMTP           : verification email + reset password
  └── Password policy: 12 car. min, majuscule, chiffre, special
```

### Clients OIDC configures

| Client | Application | Redirect URIs |
|--------|-------------|---------------|
| `ecrin` | ECRIN MDR Portal | `https://ecrin.<domain>/signin-oidc`, `/callback`, `/auth/callback` |
| `mattermost` | Mattermost | `https://chat.<domain>/signup/gitlab/complete`, `/login/gitlab/complete` |
| `nextcloud` | Nextcloud | `https://cloud.<domain>/apps/oidc_login/oidc` |

Les secrets clients sont generes automatiquement au deploiement et stockes dans Vault.

### Auto-enregistrement

```text
  Utilisateur
       │
       ├─► Accede a login.<domain>
       ├─► Clic "Creer un compte"
       ├─► Saisit nom, email, mot de passe
       │
       ├─► [Si restriction domaine active]
       │   └─► Keycloak verifie que le domaine email
       │       est dans keycloak_allowed_email_domains
       │
       ├─► Email de verification envoye
       ├─► Utilisateur confirme son email
       ├─► Compte active, groupe "users" assigne
       └─► Acces aux services autorises pour le groupe "users"
```

### Configuration

```text
  Fichier                                                Variable
  ─────────────────────────────────────────────────────────────────────
  roles/platform/keycloak/defaults/main.yml
    ├── keycloak_registration_enabled                     true
    ├── keycloak_email_verification_required               true
    ├── keycloak_allowed_email_domains                     [] (configurable)
    ├── keycloak_default_group                             users
    ├── keycloak_oidc_clients                              [ecrin, mattermost, nextcloud]
    └── keycloak_groups                                    [admins, devops, researchers, users]

  inventories/staging/group_vars/all.yml
    ├── keycloak_enabled                                   true
    └── keycloak_allowed_email_domains                     [] (a configurer)

  inventories/production/group_vars/all.yml
    └── (idem staging)
```

---

## Authelia (local)

### Fonctionnalites

- **Forward Auth** : verification d'authentification sur chaque requete via Envoy Gateway SecurityPolicy
- **OIDC Provider** : fournisseur OpenID Connect pour ECRIN
- **Fichier utilisateurs** : comptes de test pre-configures, pas de base externe
- **MFA** : TOTP et WebAuthn disponibles

### Comptes de test (local uniquement)

| Utilisateur | Groupes | Email |
|-------------|---------|-------|
| `admin` | admins, devops | `admin@<domain>` |
| `developer` | devops | `dev@<domain>` |
| `researcher` | researchers | `researcher@<domain>` |

### Sessions

```text
  Cookie           : atlas_session
  Domaine          : *.<domain> (partage entre services)
  Duree            : 1 heure
  Inactivite       : 5 minutes
  Remember me      : 1 mois
  Stockage         : memoire (local) / Redis (staging)
```

### Configuration

```text
  Fichier                                                Variable
  ─────────────────────────────────────────────────────────────────────
  roles/platform/authelia/defaults/main.yml
    ├── authelia_default_users_enabled                     true (local)
    ├── authelia_default_users                              [admin, developer, researcher]
    ├── authelia_oidc_enabled                               true
    ├── authelia_oidc_clients                               [ecrin]
    └── authelia_groups                                     [admins, devops, researchers, users]
```

---

## Second facteur (MFA)

| Methode | Protocole | Usage | Disponibilite |
|---------|-----------|-------|---------------|
| TOTP | RFC 6238 | Application (Google Auth, Authy) — periode 30s | Keycloak + Authelia |
| WebAuthn | FIDO2/Passkeys | Clef physique (YubiKey) ou biometrie (Touch ID) | Keycloak + Authelia |

---

## Politique de mots de passe

Identique sur Keycloak et Authelia :

| Regle | Valeur |
|-------|--------|
| Longueur minimale | 12 caracteres |
| Majuscule requise | Oui |
| Chiffre requis | Oui |
| Caractere special requis | Oui |
| Hachage (Authelia) | Argon2id (m=64Mo, t=3, p=4) |

---

## Methodes d'authentification par application

Chaque application utilise une ou plusieurs methodes d'authentification.
Trois mecanismes coexistent sur la plateforme :

### 1. SecurityPolicy (Gateway-level)

Toute requete entrante passe par Envoy Gateway. Une `SecurityPolicy` est attachee aux routes protegees :

- **Mode Keycloak** (`keycloak_enabled: true`) : `spec.oidc` — redirection native vers Keycloak, validation du token par Envoy
- **Mode Authelia** (`keycloak_enabled: false`) : `spec.extAuth` — Envoy consulte Authelia qui retourne les headers `Remote-User`, `Remote-Groups`, `Remote-Email`

### 2. OIDC applicatif

Certaines applications integrent directement le protocole OIDC pour obtenir des claims utilisateur (groupes, email, nom).

### 3. Proxy Auth (headers)

Certaines applications font confiance aux headers HTTP injectes par le forward auth et creent automatiquement le compte utilisateur au premier acces.

---

## Matrice d'authentification par service

### Services applicatifs

| Service | URL | SecurityPolicy | OIDC applicatif | Proxy Auth | Details |
|---------|-----|:-:|:-:|:-:|---------|
| **Nextcloud** | `cloud.<domain>` | Oui | Oui | — | OIDC pour groupes et quotas |
| **Mattermost** | `chat.<domain>` | Oui | Oui | — | OIDC via discovery endpoint (provider GitLab) |
| **ECRIN** | `ecrin.<domain>` | Oui | Oui | — | OIDC authority + client secret |
| **REDCap** | `redcap.<domain>` | Oui | — | — | Forward auth uniquement |
| **OnlyOffice** | `office.<domain>` | Oui | — | — | Forward auth + JWT inter-service (Nextcloud) |
| **Flipt** | `flags.<domain>` | Oui | — | — | Forward auth + token interne |

### Outils DevOps

| Service | URL | SecurityPolicy | OIDC applicatif | Proxy Auth | Details |
|---------|-----|:-:|:-:|:-:|---------|
| **ArgoCD** | `argocd.<domain>` | Oui | Oui | — | OIDC pour RBAC (groupes → roles) |
| **Gitea** | `git.<domain>` | Oui | — | Oui | Headers `Remote-User/Email/Groups`, auto-register |

### Monitoring

| Service | URL | SecurityPolicy | OIDC applicatif | Proxy Auth | Details |
|---------|-----|:-:|:-:|:-:|---------|
| **Grafana** | `grafana.<domain>` | Oui | — | Oui | Headers `Remote-User/Email/Groups`, auto-signup |
| **Hubble UI** | `hubble.<domain>` | Oui | — | — | Forward auth uniquement |

### Plateforme

| Service | URL | SecurityPolicy | Details |
|---------|-----|:-:|---------|
| **Keycloak** | `login.<domain>` | — | Fournisseur d'identite (pas de protection sur lui-meme) |
| **Authelia** | `login.<domain>` | — | Fournisseur d'identite (local) |
| **Vault** | `vault.<domain>` | Oui | Forward auth UI + token API |

---

## Detail par application

### Nextcloud

```text
  Authentification
  ├── SecurityPolicy    : OIDC (Keycloak) ou extAuth (Authelia)
  ├── OIDC applicatif   : oui (oidc_login plugin)
  │   ├── Provider URL  : https://login.<domain>/realms/atlas (Keycloak)
  │   │                   https://login.<domain> (Authelia)
  │   ├── Client ID     : nextcloud
  │   └── Scopes        : openid, profile, email, groups
  └── Auto-creation     : compte cree au premier login OIDC

  Configuration : roles/services/nextcloud/defaults/main.yml
    ├── nextcloud_oidc_enabled          : true
    ├── nextcloud_oidc_provider_url     : conditionnel Keycloak/Authelia
    └── nextcloud_oidc_client_id        : nextcloud
```

### Mattermost

```text
  Authentification
  ├── SecurityPolicy    : OIDC (Keycloak) ou extAuth (Authelia)
  ├── OIDC applicatif   : oui (provider GitLab dans Mattermost)
  │   ├── Discovery     : https://login.<domain>/realms/atlas/.well-known/openid-configuration (Keycloak)
  │   │                   https://login.<domain>/.well-known/openid-configuration (Authelia)
  │   ├── Client ID     : mattermost
  │   ├── Bouton login  : "Login with Keycloak" ou "Login with Authelia"
  │   └── Scopes        : openid, profile, email, groups
  └── Group sync        : oui (attribut "groups")

  Configuration : roles/services/mattermost/defaults/main.yml
    ├── mattermost_oidc_enabled                 : true
    ├── mattermost_oidc_discovery_endpoint      : conditionnel Keycloak/Authelia
    ├── mattermost_oidc_button_text             : conditionnel
    ├── mattermost_group_sync_enabled           : true
    └── mattermost_group_attribute              : groups
```

### ECRIN

```text
  Authentification
  ├── SecurityPolicy    : OIDC (Keycloak) ou extAuth (Authelia)
  ├── OIDC applicatif   : oui (SvelteKit OIDC)
  │   ├── Authority     : https://login.<domain>/realms/atlas (Keycloak)
  │   │                   https://login.<domain> (Authelia)
  │   ├── Client ID     : ecrin
  │   ├── Client secret : depuis Vault (Keycloak) ou Authelia config
  │   └── Redirect URI  : https://ecrin.<domain>/auth/callback
  └── Scopes            : openid, profile, email, groups

  Configuration : roles/services/ecrin/defaults/main.yml
    ├── ecrin_oidc_enabled          : true
    ├── ecrin_oidc_authority         : conditionnel Keycloak/Authelia
    ├── ecrin_oidc_client_id         : ecrin
    └── ecrin_oidc_client_secret     : conditionnel Keycloak/Authelia
```

### ArgoCD

```text
  Authentification
  ├── SecurityPolicy    : OIDC (Keycloak) ou extAuth (Authelia)
  ├── OIDC applicatif   : oui (config native ArgoCD)
  │   ├── Issuer        : https://login.<domain>
  │   ├── Client ID     : argocd
  │   └── Scopes        : openid, profile, email, groups
  └── RBAC interne      : groupes OIDC → roles ArgoCD

  Configuration : roles/devops/argocd/defaults/main.yml
    ├── argocd_oidc_enabled          : true
    ├── argocd_oidc_issuer            : https://login.<domain>
    ├── argocd_oidc_client_id         : argocd
    └── argocd_rbac_policy            : mapping groupes → roles
```

### Gitea

```text
  Authentification
  ├── SecurityPolicy    : OIDC (Keycloak) ou extAuth (Authelia)
  ├── Mode par defaut   : proxy (headers)
  │   ├── Header user   : Remote-User
  │   ├── Header email  : Remote-Email
  │   ├── Header groups : Remote-Groups
  │   └── Auto-register : oui
  └── Mode alternatif   : OIDC (gitea_auth_mode: oidc)

  Configuration : roles/devops/gitea/defaults/main.yml
    ├── gitea_auth_mode                 : proxy
    ├── gitea_proxy_auth_enabled        : true
    ├── gitea_proxy_header_name         : Remote-User
    ├── gitea_proxy_header_email        : Remote-Email
    ├── gitea_proxy_header_groups       : Remote-Groups
    └── gitea_proxy_auto_register       : true
```

### Grafana

```text
  Authentification
  ├── SecurityPolicy    : OIDC (Keycloak) ou extAuth (Authelia)
  ├── Mode par defaut   : proxy (headers)
  │   ├── Header user   : Remote-User
  │   ├── Header email  : Remote-Email
  │   ├── Header groups : Remote-Groups
  │   └── Auto-signup   : oui
  └── Mode alternatif   : OIDC (grafana_auth_mode: oidc)

  Configuration : roles/monitoring/kube_prometheus/defaults/main.yml
    ├── grafana_auth_mode               : proxy
    ├── grafana_proxy_auth_enabled      : true
    ├── grafana_proxy_header_name       : Remote-User
    └── grafana_proxy_auto_sign_up      : true
```

### REDCap

```text
  Authentification
  ├── SecurityPolicy    : OIDC (Keycloak) ou extAuth (Authelia)
  └── Pas d'OIDC/proxy  : forward auth uniquement

  Configuration : roles/services/redcap/defaults/main.yml
    └── redcap_forward_auth_enabled     : true
```

### OnlyOffice

```text
  Authentification
  ├── SecurityPolicy    : OIDC (Keycloak) ou extAuth (Authelia)
  ├── JWT inter-service : pour la communication avec Nextcloud
  │   ├── JWT_ENABLED   : true
  │   ├── JWT_SECRET    : depuis Vault
  │   └── JWT_HEADER    : Authorization
  └── WOPI             : protocole d'integration Nextcloud

  Configuration : roles/services/onlyoffice/defaults/main.yml
    ├── onlyoffice_forward_auth_enabled : true
    ├── onlyoffice_jwt_enabled          : true
    └── onlyoffice_wopi_enabled         : true
```

### Flipt

```text
  Authentification
  ├── SecurityPolicy    : OIDC (Keycloak) ou extAuth (Authelia)
  └── Auth interne      : token-based (flipt_auth_required: true)

  Configuration : roles/services/flipt/defaults/main.yml
    ├── flipt_forward_auth_enabled      : true
    ├── flipt_auth_enabled              : true
    └── flipt_auth_required             : true
```

### Vault

```text
  Authentification
  ├── SecurityPolicy    : OIDC (Keycloak) ou extAuth (Authelia)
  │   └── Protege       : UI (/)
  └── API               : token-based (pas de SecurityPolicy)
      └── Routes libres : /v1/sys/health, /v1/auth/, /v1/secret/, /v1/sys/

  Configuration : roles/platform/vault/defaults/main.yml
    └── vault_forward_auth_enabled      : true
```

### Hubble UI

```text
  Authentification
  ├── SecurityPolicy    : OIDC (Keycloak) ou extAuth (Authelia)
  └── Pas d'auth interne : forward auth uniquement

  Configuration : roles/monitoring/hubble_ui/defaults/main.yml
    └── hubble_ui_forward_auth_enabled  : true
```

---

## Routes non protegees

Certaines routes sont exclues de la SecurityPolicy car elles necessitent un acces sans session navigateur (clients API, webhooks, protocoles machine-a-machine) :

| Service | Chemins non proteges | Raison |
|---------|---------------------|--------|
| Mattermost | `/api/v4/`, `/plugins/`, `/hooks/` | Bots, webhooks, plugins |
| Nextcloud | `/remote.php/dav/`, `/ocs/`, `/.well-known/` | Clients WebDAV/CalDAV avec app passwords |
| REDCap | `/surveys` | Formulaires publics pour repondants externes |
| OnlyOffice | `/coauthoring/` | Callbacks de co-edition depuis Nextcloud |
| ArgoCD | `/api/webhook` | Webhooks Git depuis Gitea |
| Gitea | `/api/v1/`, `/.well-known/` | Operations Git (clone, push), OIDC discovery |
| Grafana | `/api/` | Acces API par token |
| Vault | `/v1/sys/health`, `/v1/auth/`, `/v1/secret/`, `/v1/sys/` | API avec token (ESO, CLI) |

Ces routes sont definies dans des HTTPRoutes separees, sans `SecurityPolicy` attachee.

---

## Flux d'authentification

### Avec Keycloak (staging/production)

```text
  Navigateur                  Envoy Gateway          Keycloak            Service
      │                            │                    │                   │
      │  GET https://chat.<dom>/   │                    │                   │
      ├───────────────────────────►│                    │                   │
      │                            │                    │                   │
      │                  SecurityPolicy OIDC            │                   │
      │                  (pas de token valide)          │                   │
      │                            │                    │                   │
      │◄───────────────────────────┤                    │                   │
      │  302 → login.<dom>/realms/atlas/protocol/       │                   │
      │        openid-connect/auth?client_id=...        │                   │
      │                            │                    │                   │
      │  ═══════ Utilisateur se connecte (ou s'inscrit) ═════               │
      │                            │                    │                   │
      │  302 → chat.<dom>/oauth2/callback?code=...      │                   │
      ├───────────────────────────►│                    │                   │
      │                            │  Token exchange    │                   │
      │                            ├───────────────────►│                   │
      │                            │◄───────────────────┤                   │
      │                            │  id_token (JWT)    │                   │
      │                            │                    │                   │
      │                            ├────────────────────────────────────────►
      │                            │  Requete + cookie de session           │
      │◄───────────────────────────┤◄───────────────────────────────────────┤
      │  200 OK                    │                    │                   │
```

### Avec Authelia (local)

```text
  Navigateur                  Envoy Gateway          Authelia            Service
      │                            │                    │                   │
      │  GET https://chat.<dom>/   │                    │                   │
      ├───────────────────────────►│                    │                   │
      │                            │                    │                   │
      │                  SecurityPolicy extAuth         │                   │
      │                            ├───────────────────►│                   │
      │                            │  GET /api/authz/   │                   │
      │                            │  ext-authz         │                   │
      │                            │◄───────────────────┤                   │
      │                            │  401 + redirect    │                   │
      │◄───────────────────────────┤                    │                   │
      │  302 → login.<dom>/?rd=... │                    │                   │
      │                            │                    │                   │
      │  ════ Utilisateur se connecte (1FA/2FA) ═══════ │                   │
      │                            │                    │                   │
      │  GET https://chat.<dom>/   │                    │                   │
      │  + cookie atlas_session    │                    │                   │
      ├───────────────────────────►│                    │                   │
      │                            ├───────────────────►│                   │
      │                            │  200 OK            │                   │
      │                            │  + Remote-User     │                   │
      │                            │  + Remote-Groups   │                   │
      │                            │  + Remote-Email    │                   │
      │                            │                    │                   │
      │                            ├────────────────────────────────────────►
      │◄───────────────────────────┤◄───────────────────────────────────────┤
      │  200 OK                    │                    │                   │
```

---

## Desactivation par service

Chaque service dispose d'une variable pour desactiver l'authentification :

| Variable | Fichier |
|----------|---------|
| `vault_forward_auth_enabled` | `roles/platform/vault/defaults/main.yml` |
| `argocd_forward_auth_enabled` | `roles/devops/argocd/defaults/main.yml` |
| `gitea_forward_auth_enabled` | `roles/devops/gitea/defaults/main.yml` |
| `grafana_forward_auth_enabled` | `roles/monitoring/kube_prometheus/defaults/main.yml` |
| `hubble_ui_forward_auth_enabled` | `roles/monitoring/hubble_ui/defaults/main.yml` |
| `redcap_forward_auth_enabled` | `roles/services/redcap/defaults/main.yml` |
| `nextcloud_forward_auth_enabled` | `roles/services/nextcloud/defaults/main.yml` |
| `mattermost_forward_auth_enabled` | `roles/services/mattermost/defaults/main.yml` |
| `ecrin_forward_auth_enabled` | `roles/services/ecrin/defaults/main.yml` |
| `flipt_forward_auth_enabled` | `roles/services/flipt/defaults/main.yml` |
| `onlyoffice_forward_auth_enabled` | `roles/services/onlyoffice/defaults/main.yml` |

```bash
# Desactiver le forward auth pour un service
ansible-playbook playbooks/phase-05-services.yml --tags mattermost \
  -e mattermost_forward_auth_enabled=false
```
