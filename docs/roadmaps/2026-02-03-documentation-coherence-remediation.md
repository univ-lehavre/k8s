# Roadmap : Correction des Incohérences Documentation/Code

**Date** : 2026-02-03
**Source** : Audit `docs/audits/2026-02-03-code-documentation-coherence.md`
**Objectif** : Aligner le code et la documentation à 100%

---

## Vue d'Ensemble

| Tâche | Priorité | Effort | Impact |
|-------|----------|--------|--------|
| Supprimer Authentik | Haute | Moyen | Élevé |
| Corriger noms bases de données | Moyenne | Faible | Moyen |
| Ajouter namespaces manquants | Moyenne | Faible | Faible |
| Centraliser versions Helm | Basse | Faible | Moyen |

---

## Phase 1 : Suppression d'Authentik (Priorité Haute)

### 1.1 Contexte

Authentik et Authelia sont deux solutions d'authentification déployées en parallèle. La documentation officielle ne mentionne qu'Authelia. Authentik doit être supprimé pour :

- Réduire la complexité
- Économiser les ressources (CPU, mémoire, stockage)
- Éliminer la confusion

### 1.2 Fichiers à Modifier

#### Code Ansible

| Fichier | Action |
|---------|--------|
| `ansible/playbooks/phase-05-services.yml` | Supprimer le play "Phase 5 - Authentik" (lignes 15-24) |
| `ansible/roles/platform/authentik/` | Supprimer le répertoire complet |
| `ansible/vars/helm_versions.yml` | Supprimer `authentik: "2024.2.0"` |
| `ansible/inventories/local/group_vars/all.yml` | Supprimer `authentik_url`, `replicas.authentik_*`, `namespaces.authentik` |
| `ansible/inventories/staging/group_vars/all.yml` | Supprimer références authentik |
| `ansible/inventories/production/group_vars/all.yml` | Supprimer références authentik |
| `ansible/vars/secrets_mapping.yml` | Supprimer `AUTHENTIK_*` |

#### Network Policies

| Fichier | Action |
|---------|--------|
| `ansible/roles/security/network_policies/defaults/main.yml` | Supprimer `authentik` de `network_policies_namespaces` |
| `ansible/roles/security/network_policies/defaults/main.yml` | Supprimer entrée `authentik` de `postgresql_l7_policies` |

#### Documentation

| Fichier | Action |
|---------|--------|
| `ansible/README.md` | Supprimer ligne Authentik de la table Service URLs |
| `docs/audits/documentation-drift-audit.md` | Mettre à jour si nécessaire |

### 1.3 Étapes de Migration

```bash
# 1. Vérifier qu'aucun service n'utilise Authentik pour l'auth
kubectl get pods -n authentik

# 2. Supprimer le namespace Authentik du cluster (si déployé)
kubectl delete namespace authentik

# 3. Supprimer le rôle Ansible
rm -rf ansible/roles/platform/authentik/

# 4. Mettre à jour les fichiers (voir liste ci-dessus)

# 5. Valider la syntaxe
ansible-playbook ansible/playbooks/phase-05-services.yml --syntax-check

# 6. Lancer le linting
task lint
```

### 1.4 Checklist

- [ ] Backup de la configuration Authentik (si données à migrer)
- [ ] Vérifier qu'aucun service n'utilise Authentik OIDC
- [ ] Supprimer le namespace Kubernetes
- [ ] Supprimer le rôle Ansible
- [ ] Mettre à jour les playbooks
- [ ] Mettre à jour les inventaires
- [ ] Mettre à jour helm_versions.yml
- [ ] Mettre à jour secrets_mapping.yml
- [ ] Mettre à jour network_policies
- [ ] Mettre à jour la documentation
- [ ] Valider avec `task lint`
- [ ] Tester le déploiement en local

---

## Phase 2 : Correction des Noms de Bases de Données (Priorité Moyenne)

### 2.1 Contexte

La documentation utilise le suffixe `_db` pour les noms de bases de données, mais le code utilise des noms simples.

### 2.2 État Actuel vs Attendu

| Documentation actuelle | Code réel | Action |
|------------------------|-----------|--------|
| `authelia_db` | `authelia` | Corriger doc |
| `mattermost_db` | `mattermost` | Corriger doc |
| `nextcloud_db` | `nextcloud` | Corriger doc |
| `gitea_db` | `gitea` | Corriger doc |
| `flipt_db` | `flipt` | Corriger doc |
| (manquant) | `authentik` | Supprimer (Phase 1) |

### 2.3 Fichiers à Modifier

| Fichier | Section | Action |
|---------|---------|--------|
| `README.md` | "Bases de Données > PostgreSQL" (lignes 264-271) | Corriger les noms |
| `README.md` | "Isolation des Bases de Données (L7)" (lignes 436-444) | Corriger les noms |

### 2.4 Nouveau Contenu

```markdown
### PostgreSQL

| Database    | Service         |
| ----------- | --------------- |
| `vault`     | HashiCorp Vault |
| `authelia`  | Authelia        |
| `mattermost`| Mattermost      |
| `nextcloud` | Nextcloud       |
| `gitea`     | Gitea           |
| `flipt`     | Flipt           |
```

### 2.5 Checklist

- [ ] Mettre à jour README.md section PostgreSQL
- [ ] Mettre à jour README.md section Isolation L7
- [ ] Vérifier cohérence avec network_policies/defaults/main.yml

---

## Phase 3 : Ajout des Namespaces Manquants (Priorité Moyenne)

### 3.1 Contexte

La section Network Policies du README ne liste pas tous les namespaces configurés dans le code.

### 3.2 Namespaces à Ajouter

| Namespace | Service | Ingress autorisé | Egress autorisé |
|-----------|---------|------------------|-----------------|
| `onlyoffice` | OnlyOffice | nextcloud, mattermost | - |
| `seaweedfs` | SeaweedFS S3 | nextcloud | - |
| `redcap` | REDCap | envoy-gateway | mariadb |
| `ecrin` | ECRIN | envoy-gateway | authelia (OIDC) |
| `flipt` | Flipt | envoy-gateway | postgresql |
| `monitoring` | Prometheus/Grafana | envoy-gateway | tous (scraping) |

### 3.3 Fichiers à Modifier

| Fichier | Section | Action |
|---------|---------|--------|
| `README.md` | "Network Policies par Namespace" (lignes 418-429) | Ajouter les 6 namespaces |

### 3.4 Nouveau Contenu

```markdown
### Network Policies par Namespace

| Namespace   | Ingress autorisé depuis                                        | Egress autorisé vers         |
| ----------- | -------------------------------------------------------------- | ---------------------------- |
| postgresql  | vault, authelia, mattermost, nextcloud, gitea, flipt           | -                            |
| mariadb     | redcap                                                         | -                            |
| redis       | authelia, nextcloud, gitea                                     | -                            |
| vault       | external-secrets, envoy-gateway                                | postgresql                   |
| authelia    | envoy-gateway                                                  | redis, postgresql            |
| argocd      | envoy-gateway                                                  | gitea, external (HTTPS, SSH) |
| gitea       | envoy-gateway, argocd                                          | postgresql, redis            |
| nextcloud   | envoy-gateway                                                  | postgresql, redis, seaweedfs |
| mattermost  | envoy-gateway                                                  | postgresql, redis            |
| onlyoffice  | nextcloud, mattermost                                          | -                            |
| seaweedfs   | nextcloud                                                      | -                            |
| redcap      | envoy-gateway                                                  | mariadb                      |
| ecrin       | envoy-gateway                                                  | authelia (OIDC)              |
| flipt       | envoy-gateway                                                  | postgresql                   |
| monitoring  | envoy-gateway                                                  | tous (scraping)              |
```

### 3.5 Checklist

- [ ] Mettre à jour README.md section Network Policies
- [ ] Vérifier cohérence avec network_policies/defaults/main.yml

---

## Phase 4 : Centralisation des Versions Helm (Priorité Basse)

### 4.1 Contexte

Certaines versions de composants sont hardcodées dans les rôles au lieu d'être centralisées dans `helm_versions.yml`.

### 4.2 Versions à Ajouter

| Composant | Version | Source actuelle |
|-----------|---------|-----------------|
| `onlyoffice` | `8.0.1` | À déterminer depuis le rôle |
| `ecrin` | `1.0.0` | À déterminer depuis le rôle |
| `velero` | `1.13.0` | `roles/security/backup_offsite/defaults/main.yml` |
| `trivy_operator` | `0.19.0` | `roles/security/image_scanning/defaults/main.yml` |
| `flipt` | `1.35.0` | À déterminer depuis le rôle |

### 4.3 Fichiers à Modifier

| Fichier | Action |
|---------|--------|
| `ansible/vars/helm_versions.yml` | Ajouter les versions manquantes |
| `ansible/roles/security/backup_offsite/defaults/main.yml` | Utiliser `{{ helm_versions.velero }}` |
| `ansible/roles/security/image_scanning/defaults/main.yml` | Utiliser `{{ helm_versions.trivy_operator }}` |
| `ansible/roles/services/onlyoffice/defaults/main.yml` | Utiliser `{{ helm_versions.onlyoffice }}` |
| `ansible/roles/services/ecrin/defaults/main.yml` | Utiliser `{{ helm_versions.ecrin }}` |
| `ansible/roles/services/flipt/defaults/main.yml` | Utiliser `{{ helm_versions.flipt }}` |

### 4.4 Nouveau Contenu pour helm_versions.yml

```yaml
helm_versions:
  # ... versions existantes ...

  # Services (ajouts)
  onlyoffice: "8.0.1"
  ecrin: "1.0.0"
  flipt: "1.35.0"

  # Security (ajouts)
  velero: "1.13.0"
  trivy_operator: "0.19.0"
```

### 4.5 Checklist

- [ ] Identifier les versions actuelles dans chaque rôle
- [ ] Ajouter les versions à helm_versions.yml
- [ ] Modifier les rôles pour utiliser les variables centralisées
- [ ] Valider avec `task lint`
- [ ] Tester le déploiement

---

## Planning d'Exécution

### Semaine 1

| Jour | Tâche | Responsable |
|------|-------|-------------|
| J1 | Phase 1.1-1.2 : Audit utilisation Authentik | - |
| J2 | Phase 1.3 : Suppression code Authentik | - |
| J3 | Phase 1.4 : Validation et tests | - |

### Semaine 2

| Jour | Tâche | Responsable |
|------|-------|-------------|
| J1 | Phase 2 : Correction noms BDD | - |
| J2 | Phase 3 : Ajout namespaces | - |
| J3-J4 | Phase 4 : Centralisation versions | - |
| J5 | Revue globale et merge | - |

---

## Validation Finale

### Tests à Effectuer

```bash
# 1. Linting complet
task lint

# 2. Syntaxe playbooks
ansible-playbook ansible/playbooks/site.yml --syntax-check

# 3. Déploiement local
ansible-playbook ansible/playbooks/site.yml -i ansible/inventories/local

# 4. Vérification services
kubectl get pods -A
kubectl get svc -A

# 5. Test authentification Authelia
curl -I https://login.atlas.localhost
```

### Critères de Succès

- [ ] Score de cohérence documentation/code = 100%
- [ ] Aucune référence à Authentik dans le code
- [ ] Toutes les versions centralisées dans helm_versions.yml
- [ ] Documentation README.md à jour
- [ ] Tests de déploiement local passants
- [ ] Linting sans erreur

---

## Références

- Audit source : `docs/audits/2026-02-03-code-documentation-coherence.md`
- Documentation Authelia : https://www.authelia.com/
- Helm versions : `ansible/vars/helm_versions.yml`
