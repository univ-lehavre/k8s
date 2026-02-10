# Autorisations et controle d'acces

**Date** : 2026-02-10

Regles d'acces par groupe, roles applicatifs, quotas et politique de securite par service.

---

## Groupes utilisateurs

Quatre groupes definis de maniere identique dans Keycloak et Authelia :

| Groupe        | Vocation                              | Affectation                                   |
| ------------- | ------------------------------------- | --------------------------------------------- |
| `admins`      | Administration plateforme             | Manuelle                                      |
| `devops`      | Operations, deploiement, CI/CD        | Manuelle                                      |
| `researchers` | Chercheurs, utilisateurs REDCap/ECRIN | Manuelle                                      |
| `users`       | Utilisateurs standard                 | Automatique (defaut a l'inscription Keycloak) |

Un utilisateur peut appartenir a plusieurs groupes.

---

## Politique d'acces par defaut

```text
  ┌─────────────────────────────────────────────────────────────┐
  │  Politique par defaut : DENY                                 │
  │                                                              │
  │  Toute requete non couverte par une regle explicite          │
  │  est refusee. L'utilisateur est redirige vers la page        │
  │  de login.                                                   │
  │                                                              │
  │  Configuration : authelia_default_policy: deny               │
  └─────────────────────────────────────────────────────────────┘
```

---

## Matrice d'acces par service et groupe

### Niveaux d'authentification

- **2FA** : mot de passe + second facteur (TOTP ou WebAuthn)
- **1FA** : mot de passe uniquement
- **bypass** : acces sans authentification

### Vue synthetique

```text
                        admins    devops    researchers    users
                        ──────    ──────    ───────────    ─────
  Vault (2FA)             ✓         ✓
  ArgoCD (2FA)            ✓         ✓
  REDCap (2FA)            ✓                    ✓
  ─────────────────────────────────────────────────────────────
  Hubble UI (1FA)         ✓         ✓
  Flipt (1FA)             ✓         ✓
  ECRIN (1FA)             ✓                    ✓
  ─────────────────────────────────────────────────────────────
  Grafana (1FA)           ✓         ✓          ✓            ✓
  Gitea (1FA)             ✓         ✓          ✓            ✓
  Nextcloud (1FA)         ✓         ✓          ✓            ✓
  Mattermost (1FA)        ✓         ✓          ✓            ✓
  OnlyOffice (1FA)        ✓         ✓          ✓            ✓
```

> **Note** : en mode Keycloak, le niveau d'authentification (1FA/2FA) est gere
> par les Required Actions du realm. En mode Authelia, il est defini dans les
> `authelia_access_rules`.

---

## Regles d'acces Authelia (local)

Definies dans `roles/platform/authelia/defaults/main.yml` :

| Domaine            | Politique  | Groupes             | Ressources exclues    |
| ------------------ | ---------- | ------------------- | --------------------- |
| `login.<domain>`   | two_factor | admins              | —                     |
| `vault.<domain>`   | two_factor | admins, devops      | —                     |
| `redcap.<domain>`  | bypass     | —                   | `^/surveys([/?].*)?$` |
| `redcap.<domain>`  | two_factor | researchers, admins | —                     |
| `argocd.<domain>`  | two_factor | devops, admins      | —                     |
| `hubble.<domain>`  | one_factor | devops, admins      | —                     |
| `ecrin.<domain>`   | one_factor | researchers, admins | —                     |
| `flags.<domain>`   | one_factor | devops, admins      | —                     |
| `grafana.<domain>` | one_factor | _(tous)_            | —                     |
| `git.<domain>`     | one_factor | _(tous)_            | —                     |
| `cloud.<domain>`   | one_factor | _(tous)_            | —                     |
| `chat.<domain>`    | one_factor | _(tous)_            | —                     |
| `office.<domain>`  | one_factor | _(tous)_            | —                     |

Les regles sont evaluees dans l'ordre. La premiere regle correspondante s'applique.

---

## Roles applicatifs par service

Au-dela du controle d'acces au niveau gateway, certaines applications definissent
des roles internes mappes depuis les groupes OIDC.

### ArgoCD

| Groupe OIDC   | Role ArgoCD      | Permissions                                               |
| ------------- | ---------------- | --------------------------------------------------------- |
| `admins`      | `role:admin`     | Acces complet (CRUD applications, clusters, projets)      |
| `devops`      | `role:admin`     | Acces complet                                             |
| `developers`  | `role:developer` | Voir et synchroniser les applications, consulter les logs |
| `researchers` | `role:readonly`  | Lecture seule                                             |
| _(autres)_    | `role:readonly`  | Lecture seule (politique par defaut)                      |

```text
  Configuration : roles/devops/argocd/defaults/main.yml
    argocd_rbac_default_policy: role:readonly
    argocd_rbac_scopes: "[groups]"
    argocd_rbac_policy: |
      g, admins, role:admin
      g, devops, role:admin
      p, role:developer, applications, get, *, allow
      p, role:developer, applications, sync, *, allow
      p, role:developer, logs, get, *, allow
      g, developers, role:developer
      g, researchers, role:readonly
```

### Mattermost

| Groupe OIDC | Role Mattermost | Permissions                        |
| ----------- | --------------- | ---------------------------------- |
| `admins`    | System Admin    | Administration complete du serveur |
| `devops`    | Team Admin      | Gestion des equipes et canaux      |
| _(autres)_  | Team User       | Participation aux canaux           |

```text
  Configuration : roles/services/mattermost/defaults/main.yml
    mattermost_role_mapping:
      system_admin_groups: [admins]
      team_admin_groups: [devops]

    mattermost_group_sync_enabled: true
    mattermost_group_attribute: groups
```

Les groupes sont synchronises automatiquement depuis les claims OIDC.
L'equipe par defaut (`atlas`) est creee pour tous les utilisateurs.

### Nextcloud

| Groupe OIDC   | Groupe Nextcloud | Droits specifiques                       |
| ------------- | ---------------- | ---------------------------------------- |
| `admins`      | admin            | Administration Nextcloud, quota illimite |
| `devops`      | staff            | Quota illimite                           |
| `researchers` | researchers      | Quota 100 Go                             |
| `users`       | users            | Quota 10 Go                              |

```text
  Configuration : roles/services/nextcloud/defaults/main.yml
    nextcloud_group_mapping:
      admins: admin
      devops: staff
      researchers: researchers
      users: users

    nextcloud_admin_groups: [admins]

    nextcloud_group_quotas:
      admin: 0                # illimite
      staff: 0                # illimite
      researchers: 107374182400  # 100 Go
      users: 10737418240         # 10 Go
```

### Gitea

| Groupe OIDC | Role Gitea   | Permissions                                         |
| ----------- | ------------ | --------------------------------------------------- |
| `admins`    | Site Admin   | Administration complete (utilisateurs, orgs, repos) |
| `devops`    | Org Creator  | Peut creer des organisations                        |
| `admins`    | Org Creator  | Peut creer des organisations                        |
| _(autres)_  | Regular User | Peut creer des repos personnels                     |

```text
  Configuration : roles/devops/gitea/defaults/main.yml
    gitea_role_mapping:
      admin_groups: [admins]
      org_creator_groups: [devops, admins]
      restricted_groups: []
```

Auto-registration activee : le compte Gitea est cree automatiquement au premier
acces via les headers proxy auth.

### Grafana

| Groupe OIDC   | Role Grafana | Permissions                                       |
| ------------- | ------------ | ------------------------------------------------- |
| `admins`      | Admin        | Configuration, datasources, alertes, utilisateurs |
| `devops`      | Editor       | Creation/modification de dashboards               |
| `developers`  | Editor       | Creation/modification de dashboards               |
| `researchers` | Viewer       | Consultation des dashboards                       |
| `users`       | Viewer       | Consultation des dashboards                       |
| _(autres)_    | Viewer       | Role par defaut                                   |

```text
  Configuration : roles/monitoring/kube_prometheus/defaults/main.yml
    grafana_role_mapping:
      admin_groups: [admins]
      editor_groups: [devops, developers]
      viewer_groups: [researchers, users]
      default_role: Viewer
```

Le mapping est realise via JMESPath dans la configuration Grafana :

```text
  role_attribute_path:
    contains(groups[*], 'admins') && 'Admin' ||
    contains(groups[*], 'devops') && 'Editor' ||
    'Viewer'
```

### REDCap

Pas de mapping de groupes interne. L'acces est controle uniquement au niveau gateway :

- Chercheurs et admins : acces complet (2FA)
- Route `/surveys` : acces public (bypass) pour les repondants externes

### OnlyOffice

Pas de mapping de groupes interne. L'acces est controle uniquement au niveau gateway.
La communication avec Nextcloud est securisee par JWT (secret partage).

### Flipt

Auth interne par token (`flipt_auth_required: true`). L'acces au dashboard est
controle au niveau gateway (devops + admins).

### Vault

Acces UI controle au niveau gateway (admins + devops, 2FA).
L'API utilise des tokens Vault dedies, independants du SSO :

```text
  vault_forward_auth_enabled: true    (UI protegee)
  Routes API sans auth gateway :
    /v1/sys/health     (health check)
    /v1/auth/           (authentification token)
    /v1/secret/         (lecture/ecriture secrets)
    /v1/sys/            (administration)
```

### Hubble UI

Pas de mapping de groupes interne. Acces restreint aux groupes devops et admins
au niveau gateway.

---

## Schema d'acces par groupe

```text
  ┌─────────┐
  │ admins  │─── Vault (2FA) ── ArgoCD (2FA) ── REDCap (2FA)
  │         │─── Hubble ── Flipt ── ECRIN
  │         │─── Grafana (Admin) ── Gitea (Site Admin)
  │         │─── Nextcloud (admin, illimite) ── Mattermost (System Admin)
  │         │─── OnlyOffice
  └─────────┘

  ┌─────────┐
  │ devops  │─── Vault (2FA) ── ArgoCD (2FA)
  │         │─── Hubble ── Flipt
  │         │─── Grafana (Editor) ── Gitea (Org Creator)
  │         │─── Nextcloud (staff, illimite) ── Mattermost (Team Admin)
  │         │─── OnlyOffice
  └─────────┘

  ┌────────────┐
  │researchers │─── REDCap (2FA) ── ECRIN
  │            │─── Grafana (Viewer) ── Gitea ── Nextcloud (100 Go)
  │            │─── Mattermost ── OnlyOffice
  └────────────┘

  ┌─────────┐
  │  users  │─── Grafana (Viewer) ── Gitea ── Nextcloud (10 Go)
  │         │─── Mattermost ── OnlyOffice
  └─────────┘
```

---

## Personnalisation des regles

### Modifier l'acces a un service existant

Les regles d'acces Authelia se modifient dans `roles/platform/authelia/defaults/main.yml`
sous `authelia_access_rules`, ou en surchargeant dans `inventories/<env>/group_vars/all.yml`.

Exemple — rendre Flipt accessible aux chercheurs :

```yaml
# inventories/staging/group_vars/all.yml
authelia_access_rules:
  # ... regles existantes ...
  - domain: "flags.{{ domain }}"
    policy: one_factor
    subject:
      - "group:devops"
      - "group:admins"
      - "group:researchers" # ajoute
```

### Ajouter un nouveau service

1. Creer le role Ansible avec `*_forward_auth_enabled: true` dans les defaults
2. Ajouter un template `httproute.yml.j2` avec le bloc SecurityPolicy conditionnel
3. Ajouter la regle Authelia dans `authelia_access_rules`
4. Si Keycloak OIDC est necessaire, ajouter le client dans `keycloak_oidc_clients`

### Modifier les quotas Nextcloud

```yaml
# inventories/production/group_vars/all.yml
nextcloud_group_quotas:
  admin: 0
  staff: 0
  researchers: 214748364800 # 200 Go
  users: 21474836480 # 20 Go
```

### Modifier les roles ArgoCD

```yaml
# inventories/staging/group_vars/all.yml
argocd_rbac_policy: |
  g, admins, role:admin
  g, devops, role:admin
  g, researchers, role:readonly
  # Ajouter un nouveau role
  p, role:deployer, applications, sync, */production, allow
  g, deployers, role:deployer
```
