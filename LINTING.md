# Guide de Linting Ansible

Ce projet utilise plusieurs outils de linting pour garantir la qualité du code Ansible.

## Outils installés

- **ansible-lint** : Linter principal pour Ansible (équivalent ESLint)
- **yamllint** : Validation de la syntaxe YAML
- **lefthook** : Gestionnaire de git hooks (plus rapide que pre-commit)

## Installation rapide

```bash
# Installer Task (gestionnaire de tâches)
brew install go-task
# Ou: go install github.com/go-task/task/v3/cmd/task@latest

# Installer les dépendances avec Task
task install:deps

# Ou manuellement
pip install ansible-lint yamllint
lefthook install
```

## Utilisation

### Commandes Task (recommandé)

```bash
task                   # Afficher toutes les commandes disponibles
task lint              # Linter le projet
task lint-fix          # Linter et corriger automatiquement
task syntax-check      # Vérifier la syntaxe des playbooks
task check             # Lancer tous les checks
task format            # Formater automatiquement
task info              # Afficher les infos de l'environnement
```

### Commandes directes

```bash
# Linter tout le projet
ansible-lint

# Linter avec auto-fix
ansible-lint --fix

# Linter un fichier spécifique
ansible-lint ansible/roles/devops/gitea/tasks/main.yml

# Linter avec un profil spécifique
ansible-lint --profile=production  # Le plus strict
ansible-lint --profile=safety      # Recommandé
ansible-lint --profile=basic       # Moins strict

# Lister toutes les règles
ansible-lint -L

# Afficher les détails d'une règle
ansible-lint -T var-naming
```

### Git Hooks avec Lefthook

Les hooks sont **automatiquement exécutés** lors de :

#### Pre-commit
- `ansible-lint` sur les fichiers modifiés
- `yamllint` sur les fichiers YAML (si installé)
- Vérification des trailing whitespaces
- Vérification des marqueurs de merge conflicts

#### Pre-push
- Lint complet du projet
- Protection contre les push accidentels sur main/master

#### Post-checkout
- Rappel pour installer les dépendances si nécessaire

#### Post-merge
- Notification si `requirements.yml` a changé

### Bypasser les hooks temporairement

```bash
# Bypasser tous les hooks
LEFTHOOK=0 git commit -m "message"

# Bypasser un hook spécifique
LEFTHOOK_EXCLUDE=ansible-lint git commit -m "message"

# Push sans hooks
git push --no-verify
```

## Configuration

### .ansible-lint

Fichier de configuration principal pour ansible-lint :
- Profil : `production` (le plus strict)
- Exclusions : `.cache/`, `.github/`, `molecule/`, `venv/`
- Rules personnalisables via `skip_list`

### .yamllint

Configuration pour yamllint :
- Longueur de ligne max : 120 caractères
- Indentation : 2 espaces
- Support des templates Jinja2

### lefthook.yml

Configuration des git hooks :
- Exécution parallèle pour la vitesse
- Hooks configurables par phase (pre-commit, pre-push, etc.)
- Support de l'auto-fix avec `stage_fixed: true`

## Règles communes

### Violations fréquentes

1. **var-naming[no-role-prefix]** : Les variables dans les rôles doivent avoir un préfixe
   ```yaml
   # ❌ Mauvais
   register: gitea_db_create

   # ✅ Bon
   register: devops_gitea_db_create
   ```

2. **yaml[line-length]** : Ligne trop longue (> 120 caractères)
   ```yaml
   # ❌ Mauvais
   - name: Une très longue description qui dépasse la limite de 120 caractères et devrait être raccourcie

   # ✅ Bon
   - name: Description plus courte
   ```

3. **name[casing]** : Casse incorrecte dans les noms de tasks
   ```yaml
   # ❌ Mauvais
   - name: install gitea

   # ✅ Bon
   - name: Install Gitea
   ```

4. **risky-file-permissions** : Permissions de fichiers risquées
   ```yaml
   # ❌ Mauvais
   mode: '0777'

   # ✅ Bon
   mode: '0644'
   ```

## Intégration CI/CD

### GitHub Actions

Créez `.github/workflows/lint.yml` :

```yaml
name: Ansible Lint

on: [push, pull_request]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install ansible-lint yamllint

      - name: Run ansible-lint
        run: ansible-lint --profile=production

      - name: Run yamllint
        run: yamllint -c .yamllint --strict .
```

### GitLab CI

Ajoutez dans `.gitlab-ci.yml` :

```yaml
ansible-lint:
  stage: test
  image: python:3.11
  script:
    - pip install ansible-lint yamllint
    - ansible-lint --profile=production
    - yamllint -c .yamllint --strict .
```

## Ignorer des règles

### Fichier complet (à éviter)

```yaml
# .ansible-lint
skip_list:
  - yaml[line-length]
  - name[casing]
```

### Ligne spécifique

```yaml
- name: Exception justifiée  # noqa: var-naming[no-role-prefix]
  ansible.builtin.debug:
    var: my_var
```

### Tâche complète

```yaml
- name: Task with exception
  tags:
    - skip_ansible_lint
  ansible.builtin.command: /bin/true
```

## Ressources

- [Documentation ansible-lint](https://ansible.readthedocs.io/projects/lint/)
- [Règles ansible-lint](https://ansible.readthedocs.io/projects/lint/rules/)
- [Documentation yamllint](https://yamllint.readthedocs.io/)
- [Documentation lefthook](https://github.com/evilmartians/lefthook)
- [Profiles ansible-lint](https://ansible.readthedocs.io/projects/lint/profiles/)

## Troubleshooting

### "No module named 'ansible_collections.kubernetes'"

C'est un warning, pas une erreur. Installez les collections :
```bash
ansible-galaxy collection install kubernetes.core
```

### Lefthook ne se déclenche pas

```bash
# Réinstaller les hooks
lefthook install

# Vérifier l'installation
ls -la .git/hooks/
```

### Performance lente

```bash
# Utiliser lefthook au lieu de pre-commit (plus rapide)
# Activer l'exécution parallèle (déjà configuré dans lefthook.yml)
# Limiter le scope aux fichiers modifiés seulement
```
