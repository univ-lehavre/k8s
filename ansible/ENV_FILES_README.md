# Configuration des environnements

Ce projet utilise des fichiers `.env` séparés par environnement pour une meilleure sécurité et clarté.

## Structure

```
ansible/
├── .smtp.env.example       → Template SMTP (partagé)
├── .prod.env.example       → Template Production
├── .staging.env.example    → Template Staging
├── .backup.env.example     → Template Backup (optionnel)
│
├── .smtp.env              → Config SMTP (à créer)
├── .prod.env              → Config Production (à créer)
├── .staging.env           → Config Staging (à créer)
├── .backup.env            → Config Backup (à créer, optionnel)
│
├── .env.local             → Généré automatiquement
├── .env.staging           → Généré automatiquement
└── .env.production        → Généré automatiquement
```

## Configuration initiale

### 1. Créer vos fichiers de configuration

```bash
cd ansible

# SMTP (partagé entre tous les environnements)
cp .smtp.env.example .smtp.env
vim .smtp.env  # Remplir vos credentials SMTP

# Staging
cp .staging.env.example .staging.env
vim .staging.env  # Remplir votre domaine et IP staging

# Production
cp .prod.env.example .prod.env
vim .prod.env  # Remplir vos domaines et IPs production

# Backup (optionnel)
cp .backup.env.example .backup.env
vim .backup.env  # Configurer S3 pour backups off-site
```

### 2. Générer les fichiers .env avec secrets

```bash
# Les fichiers .env.* sont générés automatiquement par le Taskfile
# Mais vous pouvez aussi les générer manuellement :

./generate-env.sh local       # → .env.local
./generate-env.sh staging     # → .env.staging
./generate-env.sh production  # → .env.production
```

## Déploiement

### Avec Task (recommandé)

```bash
# Le fichier .env est généré automatiquement s'il n'existe pas
task deploy:local -- mattermost
task deploy:staging -- mattermost
task deploy:production -- mattermost
```

### Manuellement

```bash
# 1. Générer le .env si nécessaire
./ansible/generate-env.sh staging

# 2. Sourcer le .env
source ansible/.env.staging

# 3. Déployer
ansible-playbook -i inventories/staging/ playbooks/deploy.yml -e target=mattermost
```

## Avantages de cette approche

✅ **Sécurité** : Fichiers séparés par environnement, pas de risque de mélange
✅ **Clarté** : On voit explicitement quel environnement est ciblé
✅ **Automatique** : Les `.env.*` sont générés automatiquement avec des secrets aléatoires
✅ **DRY** : Les configs (SMTP, domaines) sont dans des fichiers séparés, faciles à maintenir
✅ **Git-safe** : Les `.env.*` sont ignorés, seuls les `.example` sont versionnés

## Regeneration de secrets

⚠️ **ATTENTION** : Régénérer un `.env` écrase tous les secrets !

```bash
# Forcer la régénération (écrase le fichier existant)
./generate-env.sh staging --force

# Backup recommandé avant régénération
cp .env.staging .env.staging.backup
./generate-env.sh staging --force
```

## Configuration de Vault

Après le bootstrap, vous devez initialiser Vault :

```bash
# 1. Initialiser Vault (première fois uniquement)
kubectl exec -n vault vault-0 -- vault operator init

# 2. Copier les clés dans votre .env
vim ansible/.env.staging

# Remplir :
export VAULT_ROOT_TOKEN="s.xyz..."
export VAULT_UNSEAL_KEYS='["key1", "key2", "key3", "key4", "key5"]'

# 3. Unsealer Vault (à chaque redémarrage)
kubectl exec -n vault vault-0 -- vault operator unseal <key1>
kubectl exec -n vault vault-0 -- vault operator unseal <key2>
kubectl exec -n vault vault-0 -- vault operator unseal <key3>
```

## Fichiers à sauvegarder

🔐 **CRITIQUE** - Sauvegardez ces fichiers dans un gestionnaire de mots de passe :

- `.env.local`
- `.env.staging`
- `.env.production`
- `.smtp.env`
- `.prod.env`
- `.staging.env`
- `.backup.env`

Ces fichiers contiennent tous les secrets du système et **ne peuvent pas être régénérés** sans perdre l'accès aux données.
