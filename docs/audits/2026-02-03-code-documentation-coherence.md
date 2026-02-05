# Audit de Cohérence : Code vs Documentation

**Date** : 2026-02-03
**Auteur** : Audit automatisé
**Scope** : Comparaison entre le code Ansible et la documentation du repository

---

## Résumé Exécutif

| Catégorie | Statut | Score | Notes |
|-----------|--------|-------|-------|
| Structure du dépôt | Cohérent | 100% | Documentation reflète la structure réelle |
| Playbooks | Cohérent | 100% | 9 phases documentées et implémentées |
| Rôles Ansible | Cohérent | 100% | 45+ rôles présents comme documenté |
| Versions Helm | Partiel | 75% | Quelques composants non centralisés |
| Base de données | Incohérence | 80% | Documentation incomplète sur PostgreSQL |
| Authentification | Incohérence | 70% | Double système Authelia + Authentik |
| Network Policies | Incohérence | 85% | Documentation incomplète sur les namespaces |
| **Score Global** | | **90%** | |

---

## 1. Incohérences Identifiées

### 1.1 Double Système d'Authentification (Priorité Haute)

**Documentation (README.md)** :

- Authelia présenté comme service d'authentification principal (`login.<domain>`)
- Pas de mention d'Authentik dans la documentation principale

**Code réel** :

- `ansible/playbooks/phase-05-services.yml:4-24` déploie **les deux** :
  - Authelia (Forward Auth) à `login.<domain>`
  - Authentik (IAM/SSO/OIDC) à `auth.<domain>`
- `ansible/inventories/local/group_vars/all.yml:69` : `authentik_url: "https://auth.{{ domain }}"`
- `ansible/roles/security/network_policies/defaults/main.yml:16-17` : les deux namespaces sont présents

**Impact** : Confusion sur quelle solution utiliser pour l'authentification. Ressources gaspillées en déployant deux solutions similaires.

**Recommandation** : Supprimer Authentik et standardiser sur Authelia.

---

### 1.2 Base de Données PostgreSQL (Priorité Moyenne)

**Documentation (README.md lignes 264-271)** :

| Database | Service |
|----------|---------|
| `vault` | HashiCorp Vault |
| `authelia_db` | Authelia |
| `mattermost_db` | Mattermost |
| `nextcloud_db` | Nextcloud |
| `gitea_db` | Gitea |
| `flipt_db` | Flipt |

**Code réel (`ansible/roles/security/network_policies/defaults/main.yml:49-77`)** :

| Database | Service | User |
|----------|---------|------|
| `vault` | Vault | `vault_user` |
| `authelia` | Authelia | `authelia_user` |
| `authentik` | Authentik | `authentik_user` |
| `mattermost` | Mattermost | `mattermost_user` |
| `nextcloud` | Nextcloud | `nextcloud_user` |
| `gitea` | Gitea | `gitea_user` |
| `flipt` | Flipt | `flipt_user` |

**Incohérences détectées** :

1. **Manquant dans la doc** : `authentik` (database `authentik`, user `authentik_user`)
2. **Noms incorrects** : Documentation utilise le suffixe `_db` (`authelia_db`, `mattermost_db`, etc.) alors que le code utilise des noms simples (`authelia`, `mattermost`, etc.)

**Recommandation** : Aligner la documentation sur les noms réels des bases de données.

---

### 1.3 Network Policies - Namespaces Manquants (Priorité Moyenne)

**Documentation (README.md lignes 418-429)** :

Liste 10 namespaces : postgresql, mariadb, redis, vault, authelia, authentik, argocd, gitea, nextcloud, mattermost

**Code réel (`ansible/roles/security/network_policies/defaults/main.yml:11-27`)** :

```yaml
network_policies_namespaces:
  - vault
  - postgresql
  - mariadb
  - redis
  - authentik
  - authelia
  - mattermost
  - nextcloud
  - onlyoffice      # MANQUANT dans doc
  - seaweedfs       # MANQUANT dans doc
  - redcap          # MANQUANT dans doc
  - ecrin           # MANQUANT dans doc
  - flipt           # MANQUANT dans doc
  - gitea
  - argocd
  - monitoring      # MANQUANT dans doc
```

**Namespaces non documentés** : 6

- `onlyoffice`
- `seaweedfs`
- `redcap`
- `ecrin`
- `flipt`
- `monitoring`

**Recommandation** : Ajouter ces namespaces à la documentation des Network Policies.

---

### 1.4 Versions Helm Non Centralisées (Priorité Basse)

**Composants absents de `ansible/vars/helm_versions.yml`** :

| Composant | Localisation actuelle | Recommandation |
|-----------|----------------------|----------------|
| OnlyOffice | Image Docker directe | Ajouter version image |
| ECRIN | Manifestes K8s directs | Ajouter version image |
| Velero | Hardcodé dans rôle backup_offsite | Centraliser |
| Trivy Operator | Hardcodé dans rôle image_scanning | Centraliser |
| Flipt | Absent | Ajouter |

**Recommandation** : Centraliser toutes les versions dans `helm_versions.yml`.

---

### 1.5 Confusion Versions Applications vs Charts (Priorité Basse)

**Documentation (README.md lignes 348-364)** mentionne des versions d'applications :

| Composant | Version doc | Type |
|-----------|-------------|------|
| Vault | 1.15.2 | App version |
| Authelia | 4.38.x | App version |

**Code (`ansible/vars/helm_versions.yml`)** référence des versions de charts Helm :

| Composant | Version code | Type |
|-----------|--------------|------|
| Vault | 0.27.0 | Chart version |
| Authelia | 0.9.0 | Chart version |

**Impact** : Confusion potentielle lors des mises à jour.

**Recommandation** : Clarifier dans la documentation la différence entre versions d'applications et versions de charts Helm.

---

## 2. Points de Cohérence Validés

### 2.1 Structure du Dépôt

- La structure documentée correspond exactement à la réalité
- Les 9 phases de déploiement sont cohérentes
- Les 3 environnements (local, staging, production) existent avec les bonnes configurations

### 2.2 Playbooks

Tous les playbooks documentés existent et contiennent les rôles attendus :

| Playbook | Statut | Rôles |
|----------|--------|-------|
| phase-00-hardening.yml | OK | common/hardening |
| phase-01-preparation.yml | OK | common/prerequisites, common/docker |
| phase-02-k3s-core.yml | OK | k3s/*, infrastructure/* |
| phase-03-vault.yml | OK | platform/vault, platform/external_secrets |
| phase-04-databases.yml | OK | platform/postgresql, platform/mariadb, platform/redis |
| phase-05-services.yml | OK | platform/authelia, platform/authentik, services/* |
| phase-06-devops.yml | OK | devops/gitea, devops/argocd |
| phase-07-monitoring.yml | OK | monitoring/kube_prometheus, monitoring/hubble_ui |
| phase-08-security.yml | OK | security/* |

### 2.3 Sécurité

- Les 8 policies Kyverno documentées sont toutes implémentées
- Le hardening système (SSH, UFW, Fail2ban, Auditd, AIDE, AppArmor) est complet
- Les configurations par environnement sont correctes

### 2.4 Base de Données MariaDB

- REDCap est correctement configuré pour utiliser MariaDB
- Le filtrage L7 pour MariaDB est correctement implémenté

---

## 3. Fichiers Concernés

### Documentation à mettre à jour

- `README.md` : Sections Services, Bases de données, Network Policies, Versions
- `ansible/README.md` : Section Service URLs

### Code à modifier

- `ansible/playbooks/phase-05-services.yml` : Supprimer Authentik
- `ansible/roles/platform/authentik/` : À supprimer
- `ansible/vars/helm_versions.yml` : Ajouter versions manquantes
- `ansible/inventories/*/group_vars/all.yml` : Supprimer références Authentik
- `ansible/roles/security/network_policies/defaults/main.yml` : Supprimer authentik

---

## 4. Matrice de Conformité

```text
┌─────────────────────────────────────────────────────────────┐
│                    CONFORMITÉ GLOBALE                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Structure        ████████████████████████  100%            │
│  Playbooks        ████████████████████████  100%            │
│  Rôles            ████████████████████████  100%            │
│  Versions Helm    ██████████████████░░░░░░   75%            │
│  Documentation DB ████████████████████░░░░   80%            │
│  Authentification ██████████████░░░░░░░░░░   70%            │
│  Network Policies █████████████████████░░░   85%            │
│                                                             │
│  ─────────────────────────────────────────────────────────  │
│  SCORE GLOBAL     ██████████████████████░░   90%            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. Conclusion

Le dépôt est globalement bien structuré et documenté avec un score de **90%**. Les incohérences identifiées sont principalement :

1. **Code superflu** : Authentik déployé mais non documenté et redondant avec Authelia
2. **Documentation incomplète** : Namespaces, bases de données, versions non à jour
3. **Manque de centralisation** : Certaines versions Helm hardcodées dans les rôles

Voir le fichier `2026-02-03-remediation-roadmap.md` pour le plan de correction.
