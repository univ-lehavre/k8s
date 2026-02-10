# Guide du Développeur

## Installation rapide

```bash
# Installer Task (gestionnaire de tâches)
brew install go-task

# Installer les dépendances
task install:deps

# Ou manuellement
pip install ansible-lint yamllint
brew install lefthook
lefthook install
```

## Commandes principales

### Linting

```bash
task lint                    # Linter tout le projet
task lint-fix                # Auto-fix les problèmes
task lint-file -- path.yml   # Linter un fichier
task lint-role -- gitea      # Linter un rôle
```

### Validation

```bash
task check                   # Tous les checks
task check-quick             # Lint seulement (rapide)
task syntax-check            # Syntaxe Ansible
task yaml-lint               # Validation YAML
```

### Profils de lint

```bash
task lint-min                # Minimal
task lint-basic              # Basique
task lint-safety             # Recommandé
task lint-production         # Le plus strict (défaut)
```

### Commandes directes

```bash
ansible-lint                              # Linter tout le projet
ansible-lint --fix                        # Corriger automatiquement
ansible-lint ansible/roles/devops/gitea/  # Linter un rôle
ansible-lint -L                           # Lister toutes les règles
```

## Git hooks (Lefthook)

Les hooks s'exécutent automatiquement :

| Hook | Action |
|------|--------|
| **pre-commit** | `ansible-lint` + `yamllint` sur les fichiers modifiés, trailing whitespace, merge conflicts |
| **pre-push** | Lint complet (`--profile=production`) + protection main/master |
| **post-checkout** | Rappel si `requirements.yml` existe |
| **post-merge** | Notification si `requirements.yml` a changé |

### Bypass temporaire

```bash
LEFTHOOK=0 git commit -m "message"                    # Tous les hooks
LEFTHOOK_EXCLUDE=ansible-lint git commit -m "message"  # Un hook spécifique
git push --no-verify                                   # Pre-push
```

## Configuration des outils

| Outil | Fichier | Rôle |
|-------|---------|------|
| ansible-lint | [`.ansible-lint`](../.ansible-lint) | Linter Ansible (profil `production`) |
| yamllint | [`.yamllint`](../.yamllint) | Validation YAML stricte |
| lefthook | [`lefthook.yml`](../lefthook.yml) | Gestionnaire de git hooks |
| go-task | [`Taskfile.yml`](../Taskfile.yml) | Task runner |
| markdownlint | [`.markdownlint.yaml`](../.markdownlint.yaml) | Validation Markdown |

## Exceptions de linting

### ansible-lint

**Profil :** `production` (le plus strict)

Règles ignorées (`skip_list`) :

| Règle | Raison |
|-------|--------|
| `var-naming[no-role-prefix]` | Garder les noms de variables actuels sans préfixe de rôle |
| `command-instead-of-module` | `curl \| sh` est la méthode recommandée pour l'installation de K3s/K3D |
| `role-name[path]` | Organisation des rôles en namespaces (`common/`, `platform/`, etc.) |

Répertoires exclus : `.cache/`, `.github/`, `.git/`, `molecule/`, `venv/`, `*.retry`, `lefthook.yml`

### yamllint

| Règle | Configuration | Justification |
|-------|---------------|---------------|
| `line-length` | max: 180, level: warning | Limite étendue, seulement en warning |
| `comments-indentation` | disable | Flexibilité sur l'indentation des commentaires |
| `document-start` | disable | Le marqueur `---` n'est pas obligatoire |
| `truthy` | `true`, `false`, `yes`, `no` | Valeurs YAML classiques autorisées |

### markdownlint

| Règle | Configuration | Justification |
|-------|---------------|---------------|
| MD013 (line-length) | 180 caractères, tables exclues | Limite étendue |
| MD033 (inline HTML) | `<br>`, `<sub>`, `<sup>` autorisés | Formatage courant |
| MD040 | disable | Blocs de code sans langage autorisés |

## Violations fréquentes

1. **var-naming[no-role-prefix]** : Les variables dans les rôles doivent avoir un préfixe

   ```yaml
   # Mauvais
   register: gitea_db_create

   # Bon
   register: devops_gitea_db_create
   ```

2. **yaml[line-length]** : Ligne trop longue (> 180 caractères)

3. **name[casing]** : Les noms de tasks doivent commencer par une majuscule

   ```yaml
   # Mauvais
   - name: install gitea

   # Bon
   - name: Install Gitea
   ```

### Ignorer une règle ponctuellement

```yaml
# Sur une ligne
- name: Exception justifiée  # noqa: var-naming[no-role-prefix]
  ansible.builtin.debug:
    var: my_var

# Sur une tâche complète
- name: Task avec exception
  tags:
    - skip_ansible_lint
  ansible.builtin.command: /bin/true
```

## Intégration CI/CD

### GitHub Actions

```yaml
name: Ansible Lint
on: [push, pull_request]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - run: pip install ansible-lint yamllint
      - run: ansible-lint --profile=production
      - run: yamllint -c .yamllint --strict .
```

## Troubleshooting

### "No module named 'ansible_collections.kubernetes'"

Warning, pas une erreur. Installer les collections :

```bash
ansible-galaxy collection install kubernetes.core
```

### Lefthook ne se déclenche pas

```bash
lefthook install
ls -la .git/hooks/
```

## Ressources

- [Documentation ansible-lint](https://ansible.readthedocs.io/projects/lint/)
- [Règles ansible-lint](https://ansible.readthedocs.io/projects/lint/rules/)
- [Profiles ansible-lint](https://ansible.readthedocs.io/projects/lint/profiles/)
- [Documentation yamllint](https://yamllint.readthedocs.io/)
- [Documentation lefthook](https://github.com/evilmartians/lefthook)
- [Taskfile docs](https://taskfile.dev)
