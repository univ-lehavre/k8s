# 🔍 Linting Ansible - Guide Rapide

## TL;DR

```bash
# Installation
brew install go-task ansible-lint
task install-deps

# Utilisation quotidienne
task lint              # Vérifier le code
task lint-fix          # Corriger automatiquement
task check             # Vérification complète

# Les hooks Git sont automatiques après install-deps
```

## 🛠️ Stack de Linting

| Outil | Rôle | Équivalent JavaScript |
|-------|------|----------------------|
| **ansible-lint** | Linter principal pour Ansible | ESLint |
| **yamllint** | Validation YAML stricte | - |
| **lefthook** | Gestionnaire de git hooks | Husky |
| **go-task** | Task runner moderne | npm scripts / Make |

## 📦 Installation

### Option 1 : Avec Task (recommandé)

```bash
# Installer Task
brew install go-task

# Installer tout
task install-deps
```

### Option 2 : Manuel

```bash
# Outils de linting
brew install ansible-lint  # ou: pip install ansible-lint
pip install yamllint

# Git hooks
brew install lefthook
lefthook install
```

## 🚀 Commandes Principales

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

### Profils de Lint

```bash
task lint-min                # Minimal
task lint-basic              # Basique
task lint-safety             # Recommandé
task lint-production         # Le plus strict (défaut)
```

### Utilitaires

```bash
task info                    # Infos environnement
task info-rules              # Liste des règles
task clean                   # Nettoyer les fichiers temp
task hooks-test              # Tester les hooks
```

## 🪝 Git Hooks (Automatiques)

Les hooks s'exécutent automatiquement :

- **pre-commit** : Lint des fichiers modifiés
- **pre-push** : Lint complet + protection main/master
- **post-merge** : Notification si requirements.yml change

### Bypass temporaire

```bash
# Tout bypasser
LEFTHOOK=0 git commit -m "WIP"

# Bypasser ansible-lint seulement
LEFTHOOK_EXCLUDE=ansible-lint git commit -m "message"
```

## 📋 Règles Communes

### Variables dans les rôles

```yaml
# ❌ Mauvais
register: gitea_db

# ✅ Bon (préfixe du namespace du rôle)
register: devops_gitea_db
```

### Longueur de ligne

```yaml
# ❌ Trop long (> 120 chars)
- name: Une description beaucoup trop longue qui dépasse la limite...

# ✅ OK
- name: Description concise
```

### Noms de tasks

```yaml
# ❌ Mauvais
- name: install package

# ✅ Bon
- name: Install required packages
```

## 🔧 Configuration

- [`.ansible-lint`](.ansible-lint) - Config ansible-lint
- [`.yamllint`](.yamllint) - Config yamllint
- [`lefthook.yml`](lefthook.yml) - Config git hooks
- [`Taskfile.yml`](Taskfile.yml) - Toutes les commandes

## 📚 Documentation Complète

Voir [LINTING.md](LINTING.md) pour :

- Détails de configuration
- Intégration CI/CD
- Troubleshooting
- Exemples avancés

## 🔗 Ressources

- [ansible-lint docs](https://ansible.readthedocs.io/projects/lint/)
- [Taskfile docs](https://taskfile.dev)
- [lefthook docs](https://github.com/evilmartians/lefthook)

---

**Questions ?** Lancer `task` pour voir toutes les commandes disponibles.
