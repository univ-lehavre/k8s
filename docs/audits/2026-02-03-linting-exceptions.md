# Rapport des exceptions de qualité du code

Ce document recense les exceptions configurées pour les outils de linting du projet.

## Ansible-lint

**Fichier de configuration:** [.ansible-lint](../../.ansible-lint)

**Profil utilisé:** `production` (le plus strict)

### Règles ignorées (skip_list)

| Règle | Raison |
|-------|--------|
| `var-naming[no-role-prefix]` | Garder les noms de variables actuels sans préfixe de rôle |
| `command-instead-of-module` | `curl \| sh` est la méthode recommandée pour l'installation de K3s/K3D |
| `role-name[path]` | Organisation des rôles en namespaces (common/, platform/, etc.) |

### Répertoires et fichiers exclus

- `.cache/`
- `.github/`
- `.git/`
- `molecule/`
- `venv/`
- `*.retry`
- `lefthook.yml`
- `.pre-commit-config.yaml`

### Règles en mode warning

- `experimental` - Les règles expérimentales génèrent des warnings au lieu d'erreurs

## Yamllint

**Fichier de configuration:** [.yamllint](../../.yamllint)

### Exceptions et configurations permissives

| Règle | Configuration | Justification |
|-------|---------------|---------------|
| `line-length` | max: 180, level: warning | Limite étendue, seulement en warning |
| `comments-indentation` | disable | Flexibilité sur l'indentation des commentaires |
| `document-start` | disable | Le marqueur `---` n'est pas obligatoire |
| `truthy` | `true`, `false`, `yes`, `no` | Valeurs YAML classiques autorisées |
| `check-multi-line-strings` | false | Pas de vérification des chaînes multi-lignes |

### Répertoires ignorés

- `.cache/`
- `.github/`
- `venv/`
- `molecule/`

## Markdownlint

**Fichier de configuration:** [.markdownlint.yaml](../../.markdownlint.yaml)

### Règles désactivées

| Règle | Description | Justification |
|-------|-------------|---------------|
| MD040 | Fenced code blocks without language | Blocs de code sans langage autorisés |
| MD060 | Table column style | Trop strict pour les tables compactes |

### Règles avec configuration permissive

| Règle | Configuration | Justification |
|-------|---------------|---------------|
| MD013 (line-length) | 180 caractères, tables exclues | Limite étendue pour les longues lignes |
| MD033 (inline HTML) | `<br>`, `<sub>`, `<sup>` autorisés | Éléments HTML courants pour le formatage |
| MD024 (duplicate headings) | siblings_only: true | Titres dupliqués autorisés entre sections |
| MD026 (trailing punctuation) | `.,;:!` interdits | Le `?` est autorisé dans les titres |

## Bypass des hooks Git

Les hooks peuvent être contournés temporairement dans des cas justifiés :

```bash
# Bypass tous les hooks
LEFTHOOK=0 git commit -m "message"

# Bypass un hook spécifique
LEFTHOOK_EXCLUDE=ansible-lint git commit -m "message"

# Push sans hooks
git push --no-verify
```

## Ignorer des règles ponctuellement

### Dans le code Ansible

```yaml
# Ignorer une règle sur une ligne
- name: Exception justifiée  # noqa: var-naming[no-role-prefix]
  ansible.builtin.debug:
    var: my_var

# Ignorer une tâche complète
- name: Task avec exception
  tags:
    - skip_ansible_lint
  ansible.builtin.command: /bin/true
```

### Dans les fichiers Markdown

```markdown
<!-- markdownlint-disable MD013 -->
Ligne très longue qui dépasse la limite configurée
<!-- markdownlint-enable MD013 -->
```

## Recommandations

1. **Minimiser les exceptions** - Chaque exception doit être justifiée
2. **Documenter les raisons** - Utiliser des commentaires pour expliquer les `noqa`
3. **Revoir périodiquement** - Les exceptions peuvent devenir obsolètes
4. **Préférer les corrections** - Une exception temporaire vaut mieux qu'une permanente
