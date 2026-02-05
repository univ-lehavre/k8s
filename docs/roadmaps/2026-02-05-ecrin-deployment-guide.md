# Guide de Déploiement ECRIN - Premier Jalon

**Date** : 2026-02-05
**Objectif** : Mettre en ligne l'application ECRIN (MDR Portal) en environnement local et staging
**Prérequis** : Aucun cluster Kubernetes existant

---

## Vue d'Ensemble

### Architecture Minimale

```
┌─────────────────────────────────────────────────────────────────┐
│                        Utilisateur                               │
│                            │                                     │
│                            ▼                                     │
│                   https://ecrin.atlas.localhost                  │
│                            │                                     │
├────────────────────────────┼────────────────────────────────────┤
│  Phase 2 - Infrastructure  │                                     │
│  ┌─────────────────────────┼──────────────────────────────────┐ │
│  │     Envoy Gateway       │                                   │ │
│  │         │               │                                   │ │
│  │         ▼               ▼                                   │ │
│  │    HTTPRoute ──► Cert-Manager (TLS)                        │ │
│  │         │                                                   │ │
│  │         ▼                                                   │ │
│  │      Cilium (CNI)                                          │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                            │                                     │
├────────────────────────────┼────────────────────────────────────┤
│  Phase 5 - Services        │                                     │
│  ┌─────────────────────────┼──────────────────────────────────┐ │
│  │                         ▼                                   │ │
│  │    ┌──────────┐    ┌──────────┐                            │ │
│  │    │  ECRIN   │◄───│ Authelia │ (OIDC)                     │ │
│  │    │ :80/http │    │ :9091    │                            │ │
│  │    └──────────┘    └──────────┘                            │ │
│  │     namespace:      namespace:                              │ │
│  │       ecrin          authelia                               │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│                     K3s / K3D Cluster                           │
└─────────────────────────────────────────────────────────────────┘
```

### Composants Déployés

| Composant | Phase | Rôle | Namespace |
|-----------|-------|------|-----------|
| K3D (local) / K3s (staging) | 2 | Cluster Kubernetes | - |
| Cilium | 2 | CNI (réseau) | kube-system |
| Envoy Gateway | 2 | Gateway API / Ingress | envoy-gateway-system |
| Cert-Manager | 2 | Certificats TLS | cert-manager |
| Local Path Provisioner | 2 | Stockage (local) | local-path-storage |
| Authelia | 5 | Authentification OIDC | authelia |
| ECRIN | 5 | Application | ecrin |

---

## Partie 1 : Déploiement Local (macOS)

### 1.1 Prérequis macOS

```bash
# Homebrew (si non installé)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Outils requis
brew install docker
brew install --cask docker  # Docker Desktop
brew install kubectl
brew install helm
brew install k3d
brew install ansible
brew install task  # Taskfile runner

# Python et dépendances Ansible
pip3 install kubernetes
pip3 install openshift
ansible-galaxy collection install kubernetes.core
```

### 1.2 Configuration Docker Desktop

1. Ouvrir Docker Desktop
2. Preferences → Resources → Advanced :
   - CPUs : 4 minimum
   - Memory : 8 GB minimum
   - Swap : 2 GB
3. Appliquer et redémarrer Docker

### 1.3 Configuration DNS Local

Ajouter les entrées DNS dans `/etc/hosts` :

```bash
sudo tee -a /etc/hosts << 'EOF'
# ATLAS Platform - Local Development
127.0.0.1 atlas.localhost
127.0.0.1 login.atlas.localhost
127.0.0.1 ecrin.atlas.localhost
EOF
```

### 1.4 Structure du Projet

```bash
cd /path/to/k8s
tree -L 2 ansible/
# ansible/
# ├── inventories/
# │   ├── local/
# │   │   ├── hosts.yml
# │   │   └── group_vars/all.yml
# │   └── staging/
# ├── playbooks/
# │   ├── phase-02-k3s-core.yml
# │   └── phase-05-services.yml
# ├── roles/
# └── vars/
#     ├── helm_versions.yml
#     └── secrets_mapping.yml
```

### 1.5 Déploiement Local

#### Étape 1 : Créer le cluster K3D et l'infrastructure

```bash
cd ansible

# Déployer la Phase 2 (K3D + Infrastructure)
ansible-playbook -i inventories/local/hosts.yml playbooks/phase-02-k3s-core.yml

# Vérifier le cluster
kubectl cluster-info
kubectl get nodes
kubectl get pods -A
```

**Temps estimé** : 5-10 minutes

**Sortie attendue** :
```
PLAY RECAP *********************************************************************
localhost : ok=25   changed=15   unreachable=0    failed=0    skipped=5
```

#### Étape 2 : Vérifier l'infrastructure

```bash
# Vérifier Cilium
kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium

# Vérifier Envoy Gateway
kubectl get pods -n envoy-gateway-system

# Vérifier Cert-Manager
kubectl get pods -n cert-manager

# Vérifier le Gateway
kubectl get gateway -A
```

#### Étape 3 : Déployer Authelia et ECRIN

```bash
# Déployer uniquement Authelia et ECRIN
ansible-playbook -i inventories/local/hosts.yml playbooks/phase-05-services.yml \
  --tags "authelia,ecrin"
```

**Temps estimé** : 3-5 minutes

#### Étape 4 : Vérifier le déploiement

```bash
# Vérifier les pods
kubectl get pods -n authelia
kubectl get pods -n ecrin

# Vérifier les services
kubectl get svc -n authelia
kubectl get svc -n ecrin

# Vérifier les HTTPRoutes
kubectl get httproute -A

# Vérifier les certificats TLS
kubectl get certificates -A
```

### 1.6 Accès à l'Application

#### URLs

| Service | URL | Description |
|---------|-----|-------------|
| ECRIN | https://ecrin.atlas.localhost | Application principale |
| Authelia | https://login.atlas.localhost | Portail d'authentification |

#### Certificat Auto-signé

Le navigateur affichera un avertissement de sécurité car le certificat est auto-signé.

**Chrome/Edge** : Cliquer sur "Avancé" → "Continuer vers le site"
**Firefox** : Cliquer sur "Avancé" → "Accepter le risque et continuer"
**Safari** : Cliquer sur "Afficher les détails" → "Visiter ce site web"

#### Utilisateurs de Test

| Username | Groupes | Mot de passe initial |
|----------|---------|----------------------|
| admin | admins, devops | À définir au 1er login |
| developer | devops | À définir au 1er login |
| researcher | researchers | À définir au 1er login |

**Note** : Au premier accès, Authelia demandera de configurer la 2FA (TOTP).

### 1.7 Dépannage Local

#### Le cluster ne démarre pas

```bash
# Vérifier Docker
docker ps

# Recréer le cluster
k3d cluster delete atlas-local
ansible-playbook -i inventories/local/hosts.yml playbooks/phase-02-k3s-core.yml
```

#### Les pods sont en CrashLoopBackOff

```bash
# Voir les logs
kubectl logs -n ecrin deployment/ecrin
kubectl logs -n authelia deployment/authelia

# Décrire le pod
kubectl describe pod -n ecrin -l app=ecrin
```

#### Le certificat n'est pas émis

```bash
# Vérifier le ClusterIssuer
kubectl get clusterissuer

# Vérifier les événements du certificat
kubectl describe certificate -n ecrin ecrin-tls
```

#### DNS ne résout pas

```bash
# Vérifier /etc/hosts
cat /etc/hosts | grep atlas

# Tester la résolution
ping ecrin.atlas.localhost
```

### 1.8 Nettoyage Local

```bash
# Supprimer le cluster K3D
k3d cluster delete atlas-local

# Supprimer les entrées DNS (optionnel)
sudo sed -i '' '/atlas.localhost/d' /etc/hosts
```

---

## Partie 2 : Déploiement Staging (VM Ubuntu)

### 2.1 Prérequis VM

#### Spécifications Minimales

| Ressource | Minimum | Recommandé |
|-----------|---------|------------|
| CPU | 2 vCPU | 4 vCPU |
| RAM | 4 GB | 8 GB |
| Disque | 40 GB SSD | 80 GB SSD |
| OS | Ubuntu 22.04 LTS | Ubuntu 24.04 LTS |
| Réseau | IP publique | IP publique + DNS |

#### Ports à Ouvrir (Firewall)

| Port | Protocole | Usage |
|------|-----------|-------|
| 22 | TCP | SSH |
| 80 | TCP | HTTP (redirection) |
| 443 | TCP | HTTPS |
| 6443 | TCP | K3s API (admin seulement) |

### 2.2 Préparation de la VM

#### Connexion SSH

```bash
# Depuis votre machine locale
ssh ubuntu@<IP_VM>
```

#### Mise à jour système

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git apt-transport-https ca-certificates
```

#### Configuration du Firewall

```bash
# UFW (si utilisé)
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow from <VOTRE_IP_ADMIN> to any port 6443
sudo ufw enable
```

### 2.3 Configuration DNS

Configurer un enregistrement DNS A chez votre fournisseur :

```
*.atlas.chasset.net  →  <IP_VM>
```

Ou au minimum :
```
login.atlas.chasset.net  →  <IP_VM>
ecrin.atlas.chasset.net  →  <IP_VM>
```

### 2.4 Configuration Ansible (Machine Locale)

#### Créer le fichier .env

```bash
cd ansible
cp .env.example .env
```

#### Éditer .env avec vos valeurs

```bash
# ansible/.env

# === STAGING ===
export STAGING_DOMAIN="atlas.chasset.net"
export STAGING_HOST="<IP_DE_VOTRE_VM>"
export STAGING_SSH_KEY="~/.ssh/staging_key"

# === SECRETS (générer avec: openssl rand -hex 32) ===
export K3S_TOKEN="$(openssl rand -hex 32)"

# === Let's Encrypt ===
export LETSENCRYPT_EMAIL="admin@example.com"

# === IP Admin pour API K3s ===
export ADMIN_IP="<VOTRE_IP_PUBLIQUE>/32"
```

#### Vérifier la connexion SSH

```bash
ssh -i ~/.ssh/staging_key ubuntu@<IP_VM> "hostname"
```

### 2.5 Déploiement Staging

#### Charger les variables d'environnement

```bash
cd ansible
source .env
```

#### Étape 1 : Déployer K3s et l'infrastructure

```bash
# Phase 2 : K3s + Cilium + Envoy + Cert-Manager + Longhorn
ansible-playbook -i inventories/staging/hosts.yml playbooks/phase-02-k3s-core.yml
```

**Temps estimé** : 10-15 minutes

#### Étape 2 : Récupérer le kubeconfig

```bash
# Copier le kubeconfig depuis la VM
scp -i ~/.ssh/staging_key ubuntu@<IP_VM>:/etc/rancher/k3s/k3s.yaml ~/.kube/staging-config

# Modifier l'adresse du serveur
sed -i '' "s/127.0.0.1/<IP_VM>/g" ~/.kube/staging-config

# Utiliser ce kubeconfig
export KUBECONFIG=~/.kube/staging-config

# Vérifier
kubectl get nodes
```

#### Étape 3 : Déployer Authelia et ECRIN

```bash
ansible-playbook -i inventories/staging/hosts.yml playbooks/phase-05-services.yml \
  --tags "authelia,ecrin"
```

**Temps estimé** : 5-10 minutes

#### Étape 4 : Vérifier le déploiement

```bash
# Pods
kubectl get pods -n authelia
kubectl get pods -n ecrin

# Certificats Let's Encrypt
kubectl get certificates -A
kubectl describe certificate -n ecrin ecrin-tls

# HTTPRoutes
kubectl get httproute -A
```

### 2.6 Accès à l'Application Staging

#### URLs

| Service | URL |
|---------|-----|
| ECRIN | https://ecrin.atlas.chasset.net |
| Authelia | https://login.atlas.chasset.net |

#### Vérifier les certificats TLS

```bash
# Vérifier le certificat depuis le terminal
openssl s_client -connect ecrin.atlas.chasset.net:443 -servername ecrin.atlas.chasset.net </dev/null 2>/dev/null | openssl x509 -noout -issuer -dates
```

Le certificat devrait être émis par "Let's Encrypt" (issuer contient "R3" ou "E1").

### 2.7 Dépannage Staging

#### Le certificat reste en "Pending"

```bash
# Vérifier l'état de la demande
kubectl describe certificaterequest -n ecrin

# Vérifier les challenges ACME
kubectl get challenges -A
kubectl describe challenge -n ecrin

# Vérifier que le port 80 est accessible
curl -I http://ecrin.atlas.chasset.net/.well-known/acme-challenge/test
```

**Causes fréquentes** :
- DNS non propagé (attendre 5-10 min)
- Port 80 bloqué par le firewall
- Rate limit Let's Encrypt atteint

#### K3s ne démarre pas

```bash
# Sur la VM
sudo systemctl status k3s
sudo journalctl -xeu k3s

# Vérifier les logs
sudo cat /var/log/syslog | grep k3s
```

#### Connexion refusée à l'API K3s

```bash
# Vérifier que le firewall autorise votre IP
sudo ufw status

# Vérifier que K3s écoute
sudo ss -tlnp | grep 6443
```

### 2.8 Maintenance Staging

#### Redémarrer les services

```bash
kubectl rollout restart deployment -n ecrin ecrin
kubectl rollout restart deployment -n authelia authelia
```

#### Voir les logs en temps réel

```bash
kubectl logs -n ecrin deployment/ecrin -f
kubectl logs -n authelia deployment/authelia -f
```

#### Mettre à jour les déploiements

```bash
# Après modification du code Ansible
ansible-playbook -i inventories/staging/hosts.yml playbooks/phase-05-services.yml \
  --tags "ecrin"
```

---

## Partie 3 : Validation du Déploiement

### 3.1 Checklist de Validation

#### Infrastructure (Phase 2)

- [ ] Cluster Kubernetes accessible (`kubectl get nodes`)
- [ ] Cilium opérationnel (`kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium`)
- [ ] Envoy Gateway opérationnel (`kubectl get pods -n envoy-gateway-system`)
- [ ] Cert-Manager opérationnel (`kubectl get pods -n cert-manager`)
- [ ] Gateway créée (`kubectl get gateway -A`)

#### Services (Phase 5)

- [ ] Authelia running (`kubectl get pods -n authelia`)
- [ ] ECRIN running (`kubectl get pods -n ecrin`)
- [ ] HTTPRoutes configurées (`kubectl get httproute -A`)
- [ ] Certificats émis (`kubectl get certificates -A`)

#### Accès Utilisateur

- [ ] Page de login Authelia accessible
- [ ] Connexion avec utilisateur de test
- [ ] Redirection vers ECRIN après authentification
- [ ] ECRIN affiche correctement son interface

### 3.2 Tests Fonctionnels

```bash
# Test de connectivité (local)
curl -k https://login.atlas.localhost/api/health
curl -k https://ecrin.atlas.localhost/health

# Test de connectivité (staging)
curl https://login.atlas.chasset.net/api/health
curl https://ecrin.atlas.chasset.net/health
```

### 3.3 Métriques de Succès

| Critère | Local | Staging |
|---------|-------|---------|
| Temps de déploiement total | < 15 min | < 25 min |
| Pods en Running | 100% | 100% |
| Certificat TLS valide | Auto-signé OK | Let's Encrypt OK |
| Authentification OIDC | Fonctionnelle | Fonctionnelle |
| Temps de réponse ECRIN | < 500ms | < 1s |

---

## Annexes

### A. Variables d'Environnement Complètes

```bash
# ansible/.env pour staging

# Staging
export STAGING_DOMAIN="atlas.chasset.net"
export STAGING_HOST="10.0.1.10"
export STAGING_SSH_KEY="~/.ssh/staging_key"

# Cluster
export K3S_TOKEN="votre-token-genere"

# TLS
export LETSENCRYPT_EMAIL="admin@example.com"

# Sécurité
export ADMIN_IP="203.0.113.50/32"

# Authelia OIDC (optionnel, généré auto sinon)
# export AUTHELIA_OIDC_ECRIN_SECRET="votre-secret"
```

### B. Commandes Utiles

```bash
# Voir tous les pods
kubectl get pods -A

# Voir les événements récents
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Exécuter un shell dans un pod
kubectl exec -it -n ecrin deployment/ecrin -- /bin/sh

# Port-forward pour debug local
kubectl port-forward -n ecrin svc/ecrin 8080:80

# Supprimer et recréer un déploiement
kubectl delete deployment -n ecrin ecrin
ansible-playbook -i inventories/local/hosts.yml playbooks/phase-05-services.yml --tags "ecrin"
```

### C. Références

- [Documentation Authelia](https://www.authelia.com/)
- [K3s Documentation](https://docs.k3s.io/)
- [Envoy Gateway](https://gateway.envoyproxy.io/)
- [Cert-Manager](https://cert-manager.io/docs/)

---

## Historique des Modifications

| Date | Version | Auteur | Description |
|------|---------|--------|-------------|
| 2026-02-05 | 1.0 | - | Création initiale |
