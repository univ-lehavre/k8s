# Authentification et gestion des utilisateurs

**Date** : 2026-02-10

Gestion des identites, fournisseur SSO et methodes d'authentification par application.

---

## Fournisseur d'identite

La plateforme utilise Keycloak comme fournisseur SSO unique pour tous les environnements :

| Environnement  | Fournisseur | URL              | Description                                        |
| -------------- | ----------- | ---------------- | -------------------------------------------------- |
| **Local**      | Keycloak    | `login.<domain>` | Mode dev, comptes de test                          |
| **Staging**    | Keycloak    | `login.<domain>` | IAM complet, auto-enregistrement, console admin    |
| **Production** | Keycloak    | `login.<domain>` | IAM complet, HA (2 replicas), MFA obligatoire      |

---

## Keycloak

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

| Client       | Application      | Redirect URIs                                                            |
| ------------ | ---------------- | ------------------------------------------------------------------------ |
| `ecrin`      | ECRIN MDR Portal | `https://ecrin.<domain>/signin-oidc`, `/callback`, `/auth/callback`      |
| `mattermost` | Mattermost       | `https://chat.<domain>/signup/gitlab/complete`, `/login/gitlab/complete` |
| `nextcloud`  | Nextcloud        | `https://cloud.<domain>/apps/oidc_login/oidc`                            |

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
    └── keycloak_allowed_email_domains                     [] (a configurer)

  inventories/production/group_vars/all.yml
    └── (idem staging)
```

---

## Second facteur (MFA)

| Methode  | Protocole      | Usage                                           | Disponibilite |
| -------- | -------------- | ----------------------------------------------- | ------------- |
| TOTP     | RFC 6238       | Application (Google Auth, Authy) — periode 30s  | Keycloak      |
| WebAuthn | FIDO2/Passkeys | Clef physique (YubiKey) ou biometrie (Touch ID) | Keycloak      |

---

## Politique de mots de passe

| Regle                    | Valeur        |
| ------------------------ | ------------- |
| Longueur minimale        | 12 caracteres |
| Majuscule requise        | Oui           |
| Chiffre requis           | Oui           |
| Caractere special requis | Oui           |

---

## Methodes d'authentification par application

Chaque application utilise une ou plusieurs methodes d'authentification.
Trois mecanismes coexistent sur la plateforme :

### 1. SecurityPolicy (Gateway-level)

Toute requete entrante passe par Envoy Gateway. Une `SecurityPolicy` est attachee aux routes protegees :

- **OIDC** : `spec.oidc` — redirection native vers Keycloak, validation du token par Envoy

### 2. OIDC applicatif

Certaines applications integrent directement le protocole OIDC pour obtenir des claims utilisateur (groupes, email, nom).

### 3. Proxy Auth (headers)

Certaines applications font confiance aux headers HTTP injectes par le forward auth et creent automatiquement le compte utilisateur au premier acces.

---

## Matrice d'authentification par service

### Services applicatifs

| Service        | URL               | SecurityPolicy | OIDC applicatif | Proxy Auth | Details                                       |
| -------------- | ----------------- | :------------: | :-------------: | :--------: | --------------------------------------------- |
| **Nextcloud**  | `cloud.<domain>`  |      Oui       |       Oui       |     —      | OIDC pour groupes et quotas                   |
| **Mattermost** | `chat.<domain>`   |      Oui       |       Oui       |     —      | OIDC via discovery endpoint (provider GitLab) |
| **ECRIN**      | `ecrin.<domain>`  |      Oui       |       Oui       |     —      | OIDC authority + client secret                |
| **REDCap**     | `redcap.<domain>` |      Oui       |        —        |     —      | Forward auth uniquement                       |
| **OnlyOffice** | `office.<domain>` |      Oui       |        —        |     —      | Forward auth + JWT inter-service (Nextcloud)  |
| **Flipt**      | `flags.<domain>`  |      Oui       |        —        |     —      | Forward auth + token interne                  |

### Outils DevOps

| Service    | URL               | SecurityPolicy | OIDC applicatif | Proxy Auth | Details                                           |
| ---------- | ----------------- | :------------: | :-------------: | :--------: | ------------------------------------------------- |
| **ArgoCD** | `argocd.<domain>` |      Oui       |       Oui       |     —      | OIDC pour RBAC (groupes → roles)                  |
| **Gitea**  | `git.<domain>`    |      Oui       |        —        |    Oui     | Headers `Remote-User/Email/Groups`, auto-register |

### Monitoring

| Service       | URL                | SecurityPolicy | OIDC applicatif | Proxy Auth | Details                                         |
| ------------- | ------------------ | :------------: | :-------------: | :--------: | ----------------------------------------------- |
| **Grafana**   | `grafana.<domain>` |      Oui       |        —        |    Oui     | Headers `Remote-User/Email/Groups`, auto-signup |
| **Hubble UI** | `hubble.<domain>`  |      Oui       |        —        |     —      | Forward auth uniquement                         |

### Plateforme

| Service      | URL              | SecurityPolicy | Details                                                 |
| ------------ | ---------------- | :------------: | ------------------------------------------------------- |
| **Keycloak** | `login.<domain>` |       —        | Fournisseur d'identite (pas de protection sur lui-meme) |
| **Vault**    | `vault.<domain>` |      Oui       | Forward auth UI + token API                             |

---

## Detail par application

### Nextcloud

```text
  Authentification
  ├── SecurityPolicy    : OIDC (Keycloak)
  ├── OIDC applicatif   : oui (oidc_login plugin)
  │   ├── Provider URL  : https://login.<domain>/realms/atlas
  │   ├── Client ID     : nextcloud
  │   └── Scopes        : openid, profile, email, groups
  └── Auto-creation     : compte cree au premier login OIDC

  Configuration : roles/services/nextcloud/defaults/main.yml
    ├── nextcloud_oidc_enabled          : true
    ├── nextcloud_oidc_provider_url     : https://login.<domain>/realms/atlas
    └── nextcloud_oidc_client_id        : nextcloud
```

### Mattermost

```text
  Authentification
  ├── SecurityPolicy    : OIDC (Keycloak)
  ├── OIDC applicatif   : oui (provider GitLab dans Mattermost)
  │   ├── Discovery     : https://login.<domain>/realms/atlas/.well-known/openid-configuration
  │   ├── Client ID     : mattermost
  │   ├── Bouton login  : "Login with Keycloak"
  │   └── Scopes        : openid, profile, email, groups
  └── Group sync        : oui (attribut "groups")

  Configuration : roles/services/mattermost/defaults/main.yml
    ├── mattermost_oidc_enabled                 : true
    ├── mattermost_oidc_discovery_endpoint      : https://login.<domain>/realms/atlas/.well-known/openid-configuration
    ├── mattermost_oidc_button_text             : "Login with Keycloak"
    ├── mattermost_group_sync_enabled           : true
    └── mattermost_group_attribute              : groups
```

### ECRIN

```text
  Authentification
  ├── SecurityPolicy    : OIDC (Keycloak)
  ├── OIDC applicatif   : oui (SvelteKit OIDC)
  │   ├── Authority     : https://login.<domain>/realms/atlas
  │   ├── Client ID     : ecrin
  │   ├── Client secret : depuis Vault
  │   └── Redirect URI  : https://ecrin.<domain>/auth/callback
  └── Scopes            : openid, profile, email, groups

  Configuration : roles/services/ecrin/defaults/main.yml
    ├── ecrin_oidc_enabled          : true
    ├── ecrin_oidc_authority         : https://login.<domain>/realms/atlas
    ├── ecrin_oidc_client_id         : ecrin
    └── ecrin_oidc_client_secret     : depuis Vault
```

### ArgoCD

```text
  Authentification
  ├── SecurityPolicy    : OIDC (Keycloak)
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
  ├── SecurityPolicy    : OIDC (Keycloak)
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
  ├── SecurityPolicy    : OIDC (Keycloak)
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
  ├── SecurityPolicy    : OIDC (Keycloak)
  └── Pas d'OIDC/proxy  : forward auth uniquement

  Configuration : roles/services/redcap/defaults/main.yml
    └── redcap_forward_auth_enabled     : true
```

### OnlyOffice

```text
  Authentification
  ├── SecurityPolicy    : OIDC (Keycloak)
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
  ├── SecurityPolicy    : OIDC (Keycloak)
  └── Auth interne      : token-based (flipt_auth_required: true)

  Configuration : roles/services/flipt/defaults/main.yml
    ├── flipt_forward_auth_enabled      : true
    ├── flipt_auth_enabled              : true
    └── flipt_auth_required             : true
```

### Vault

```text
  Authentification
  ├── SecurityPolicy    : OIDC (Keycloak)
  │   └── Protege       : UI (/)
  └── API               : token-based (pas de SecurityPolicy)
      └── Routes libres : /v1/sys/health, /v1/auth/, /v1/secret/, /v1/sys/

  Configuration : roles/platform/vault/defaults/main.yml
    └── vault_forward_auth_enabled      : true
```

### Hubble UI

```text
  Authentification
  ├── SecurityPolicy    : OIDC (Keycloak)
  └── Pas d'auth interne : forward auth uniquement

  Configuration : roles/monitoring/hubble_ui/defaults/main.yml
    └── hubble_ui_forward_auth_enabled  : true
```

---

## Routes non protegees

Certaines routes sont exclues de la SecurityPolicy car elles necessitent un acces sans session navigateur (clients API, webhooks, protocoles machine-a-machine) :

| Service    | Chemins non proteges                                     | Raison                                       |
| ---------- | -------------------------------------------------------- | -------------------------------------------- |
| Mattermost | `/api/v4/`, `/plugins/`, `/hooks/`                       | Bots, webhooks, plugins                      |
| Nextcloud  | `/remote.php/dav/`, `/ocs/`, `/.well-known/`             | Clients WebDAV/CalDAV avec app passwords     |
| REDCap     | `/surveys`                                               | Formulaires publics pour repondants externes |
| OnlyOffice | `/coauthoring/`                                          | Callbacks de co-edition depuis Nextcloud     |
| ArgoCD     | `/api/webhook`                                           | Webhooks Git depuis Gitea                    |
| Gitea      | `/api/v1/`, `/.well-known/`                              | Operations Git (clone, push), OIDC discovery |
| Grafana    | `/api/`                                                  | Acces API par token                          |
| Vault      | `/v1/sys/health`, `/v1/auth/`, `/v1/secret/`, `/v1/sys/` | API avec token (ESO, CLI)                    |

Ces routes sont definies dans des HTTPRoutes separees, sans `SecurityPolicy` attachee.

---

## Flux d'authentification

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

---

## Desactivation par service

Chaque service dispose d'une variable pour desactiver l'authentification :

| Variable                          | Fichier                                              |
| --------------------------------- | ---------------------------------------------------- |
| `vault_forward_auth_enabled`      | `roles/platform/vault/defaults/main.yml`             |
| `argocd_forward_auth_enabled`     | `roles/devops/argocd/defaults/main.yml`              |
| `gitea_forward_auth_enabled`      | `roles/devops/gitea/defaults/main.yml`               |
| `grafana_forward_auth_enabled`    | `roles/monitoring/kube_prometheus/defaults/main.yml` |
| `hubble_ui_forward_auth_enabled`  | `roles/monitoring/hubble_ui/defaults/main.yml`       |
| `redcap_forward_auth_enabled`     | `roles/services/redcap/defaults/main.yml`            |
| `nextcloud_forward_auth_enabled`  | `roles/services/nextcloud/defaults/main.yml`         |
| `mattermost_forward_auth_enabled` | `roles/services/mattermost/defaults/main.yml`        |
| `ecrin_forward_auth_enabled`      | `roles/services/ecrin/defaults/main.yml`             |
| `flipt_forward_auth_enabled`      | `roles/services/flipt/defaults/main.yml`             |
| `onlyoffice_forward_auth_enabled` | `roles/services/onlyoffice/defaults/main.yml`        |

```bash
# Desactiver le forward auth pour un service
ansible-playbook playbooks/phase-05-services.yml --tags mattermost \
  -e mattermost_forward_auth_enabled=false
```
