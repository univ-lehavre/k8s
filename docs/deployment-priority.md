# Guide de Deploiement Priorise - ATLAS Platform

**Date** : 2026-02-10
**Branche** : `feature/ansible-atlas-platform`

Ce guide structure le deploiement de la plateforme en **jalons** orientes valeur metier. Chaque jalon produit un resultat utilisable et constitue un point de validation avant de passer au suivant.

> **Gestion des secrets Authelia** : lorsque Vault est disponible (staging/production), les secrets d'Authelia (JWT, session, OIDC HMAC, cle privee RSA, cle de chiffrement storage) sont generes au premier deploiement, stockes dans Vault (`secret/platform/authelia`) et synchronises vers Kubernetes via External Secrets Operator. En local (sans Vault), les secrets sont generes directement par Ansible (fallback).

---

## Vue d'ensemble des jalons

```text
Jalon 0   Infrastructure         Cluster K8s, secrets, PostgreSQL, Redis, Authelia
Jalon 1   Communication          Mattermost (chat d'equipe)                        ─┐
Jalon 2   Collaboration          Nextcloud + OnlyOffice (fichiers, edition)         ─┤ independants
Jalon 3   Recherche              REDCap + ECRIN (capture de donnees)                ─┤ (ordre libre)
Jalon 4   DevOps                 Gitea + ArgoCD + Flipt (forge, CD, feature flags)  ─┘
Jalon 5   Observabilite          Monitoring, dashboards, flux reseau
Jalon 6   Securite Applicative   Policies Kyverno, Network Policies, backups, scans
```

---

## Jalon 0 : Infrastructure

Socle technique requis par tous les jalons suivants. Pas de valeur utilisateur directe, mais rien ne fonctionne sans.

### Commandes

```bash
ansible-playbook playbooks/phase-00-hardening.yml   # staging/production uniquement
ansible-playbook playbooks/phase-01-preparation.yml
ansible-playbook playbooks/phase-02-k3s-core.yml
ansible-playbook playbooks/phase-03-vault.yml
ansible-playbook playbooks/phase-04-databases.yml --tags postgresql,redis
ansible-playbook playbooks/phase-05-services.yml --tags authelia
```

### Composants deployes

| Ordre | Composant        | Version      | Fonction                                   | Depend de                    |
| ----- | ---------------- | ------------ | ------------------------------------------ | ---------------------------- |
| 1     | Hardening        | -            | SSH, UFW, Fail2ban, Auditd, AIDE, AppArmor | -                            |
| 2     | K3s/K3D          | v1.29.2+k3s1 | Cluster Kubernetes                         | Hardening                    |
| 3     | Cilium           | 1.16.5       | CNI, Network Policies, Hubble              | K3s                          |
| 4     | Envoy Gateway    | 1.2.0        | Gateway API, ingress HTTPS                 | Cilium                       |
| 5     | Longhorn         | 1.6.0        | Stockage distribue chiffre                 | Cilium                       |
| 6     | Cert-Manager     | 1.14.3       | Certificats TLS (Let's Encrypt)            | Cilium                       |
| 7     | Vault            | 0.27.0       | Coffre-fort de secrets                     | Envoy GW, Cert-Mgr, Longhorn |
| 8     | External Secrets | 0.9.12       | Sync secrets vers Kubernetes               | Vault                        |
| 9     | PostgreSQL HA    | 14.0.4       | BDD principale (5 databases)               | Vault, Longhorn              |
| 10    | Redis            | 18.12.1      | Sessions, cache, rate-limiting             | Vault, Longhorn              |
| 11    | Authelia         | 0.9.0        | Authentification, OIDC, MFA                | PostgreSQL, Redis            |

### Critere de validation

- [ ] `kubectl get nodes` → tous Ready
- [ ] `cilium status` → OK
- [ ] `vault status` → Initialized, Unsealed
- [ ] PostgreSQL : `\l` liste les 5 databases
- [ ] `https://login.<domain>` → portail Authelia accessible, connexion test OK

### Bases de donnees creees

**PostgreSQL** (`postgresql.postgresql.svc.cluster.local:5432`) :

| Database     | Service    | Utilisateur       | Utilise par |
| ------------ | ---------- | ----------------- | ----------- |
| `authelia`   | Authelia   | `authelia_user`   | Jalon 0     |
| `mattermost` | Mattermost | `mattermost_user` | Jalon 1     |
| `nextcloud`  | Nextcloud  | `nextcloud_user`  | Jalon 2     |
| `gitea`      | Gitea      | `gitea_user`      | Jalon 4     |
| `flipt`      | Flipt      | `flipt_user`      | Jalon 4     |

> **Note** : les 5 databases sont creees en Jalon 0 car PostgreSQL est deploye une seule fois. Les services qui les utilisent sont deployes dans les jalons suivants.

**MariaDB** : non deployee en Jalon 0. Voir Jalon 3 (deploye avec REDCap).

---

## Jalon 1 : Communication

**Objectif** : l'equipe dispose d'un chat interne operationnel.

**Prerequis** : Jalon 0 complet.

### Commandes

```bash
ansible-playbook playbooks/phase-05-services.yml --tags mattermost
```

### Composants deployes

| Composant  | Version | Namespace    | URL                     | Depend de                   |
| ---------- | ------- | ------------ | ----------------------- | --------------------------- |
| Mattermost | 9.11    | `mattermost` | `https://chat.<domain>` | PostgreSQL, Authelia (OIDC) |

### Critere de validation

- [ ] `https://chat.<domain>` → page de connexion
- [ ] Connexion via Authelia (bouton "Login with Authelia")
- [ ] Creation d'un canal, envoi d'un message

### Resultat

Les utilisateurs peuvent se connecter via SSO et communiquer par messagerie instantanee (canaux, messages directs, fils de discussion).

---

## Jalon 2 : Collaboration

**Objectif** : l'equipe peut stocker, partager et editer des documents en ligne.

**Prerequis** : Jalon 0 complet.

### Commandes

```bash
ansible-playbook playbooks/phase-05-services.yml --tags seaweedfs,nextcloud,onlyoffice
```

### Composants deployes (dans cet ordre)

| Ordre | Composant  | Version | Namespace    | URL                       | Depend de                                     |
| ----- | ---------- | ------- | ------------ | ------------------------- | --------------------------------------------- |
| 1     | SeaweedFS  | 3.67.0  | `seaweedfs`  | interne                   | Longhorn                                      |
| 2     | Nextcloud  | 29      | `nextcloud`  | `https://cloud.<domain>`  | PostgreSQL, Redis, SeaweedFS, Authelia (OIDC) |
| 3     | OnlyOffice | 8.0.1   | `onlyoffice` | `https://office.<domain>` | Nextcloud                                     |

**Ordre important** : SeaweedFS fournit le stockage S3 pour Nextcloud. OnlyOffice s'integre dans Nextcloud pour l'edition de documents.

### Critere de validation

- [ ] `https://cloud.<domain>` → connexion Nextcloud via Authelia
- [ ] Upload d'un fichier → stocke dans SeaweedFS (S3)
- [ ] Ouverture d'un .docx → edition dans OnlyOffice
- [ ] Partage d'un fichier entre deux utilisateurs

### Resultat

Les utilisateurs disposent d'un espace de fichiers partage avec edition collaborative de documents (Word, Excel, PowerPoint) directement dans le navigateur.

---

## Jalon 3 : Recherche

**Objectif** : les chercheurs peuvent capturer des donnees cliniques et collaborer sur des projets de recherche.

**Prerequis** : Jalon 0 complet.

### Commandes

```bash
ansible-playbook playbooks/phase-04-databases.yml --tags mariadb
ansible-playbook playbooks/phase-05-services.yml --tags redcap,ecrin
```

### Composants deployes

| Ordre | Composant | Version | Namespace | URL                       | Depend de                           |
| ----- | --------- | ------- | --------- | ------------------------- | ----------------------------------- |
| 1     | MariaDB   | 18.2.2  | `mariadb` | interne                   | Vault (secrets)                     |
| 2     | REDCap    | 14.0.0  | `redcap`  | `https://redcap.<domain>` | MariaDB, Authelia (Forward Auth)    |
| 3     | ECRIN     | 1.0.0   | `ecrin`   | `https://ecrin.<domain>`  | Authelia (OIDC), REDCap (optionnel) |

**MariaDB** (`mariadb.mariadb.svc.cluster.local:3306`) : deployee ici car utilisee uniquement par REDCap. Base creee : `redcap` (utilisateur `redcap_user`).

### Critere de validation

- [ ] MariaDB : `SHOW DATABASES` liste `redcap`
- [ ] `https://redcap.<domain>` → acces via Forward Auth (groupes `researchers`, `admins`)
- [ ] Creation d'un projet REDCap, ajout d'un instrument
- [ ] `https://ecrin.<domain>` → connexion OIDC

### Resultat

Les chercheurs peuvent creer des formulaires de collecte de donnees (REDCap) et collaborer sur des protocoles de recherche (ECRIN).

---

## Jalon 4 : DevOps

**Objectif** : l'equipe dispose d'une forge Git et d'un deploiement continu GitOps.

**Prerequis** : Jalon 0 complet.

### Commandes

```bash
ansible-playbook playbooks/phase-05-services.yml --tags flipt
ansible-playbook playbooks/phase-06-devops.yml
```

### Composants deployes (dans cet ordre)

| Ordre | Composant | Chart version | Namespace | URL                       | Depend de                          |
| ----- | --------- | ------------- | --------- | ------------------------- | ---------------------------------- |
| 1     | Flipt     | 1.35.0        | `flipt`   | `https://flags.<domain>`  | PostgreSQL                         |
| 2     | Gitea     | 10.1.1        | `gitea`   | `https://git.<domain>`    | PostgreSQL, Redis, Authelia        |
| 3     | ArgoCD    | 6.4.0         | `argocd`  | `https://argocd.<domain>` | Authelia (OIDC), Gitea (optionnel) |

**Ordre important** : ArgoCD se connecte a Gitea pour le GitOps. Flipt est independant de Gitea/ArgoCD.

**Ports** :

- Gitea HTTP : via Envoy Gateway (443)
- Gitea SSH : NodePort `30022`

### Critere de validation

- [ ] `https://flags.<domain>` → interface Flipt accessible, creation d'un flag test
- [ ] `git clone ssh://git@<domain>:30022/org/repo.git` → clone fonctionne
- [ ] `https://git.<domain>` → interface Gitea accessible
- [ ] `https://argocd.<domain>` → connexion OIDC (two_factor)
- [ ] ArgoCD synchronise un repo Gitea

### Resultat

L'equipe peut heberger du code source, faire des revues de code, deployer automatiquement via GitOps et gerer les feature flags.

---

## Jalon 5 : Observabilite

**Objectif** : visibilite sur l'etat de sante du cluster, des applications et du reseau.

**Prerequis** : Jalon 0 complet (idealement apres les jalons 1-4 pour avoir des metriques a observer).

### Commandes

```bash
ansible-playbook playbooks/phase-07-monitoring.yml
```

### Composants deployes

| Composant             | Chart version      | Namespace     | URL                        | Depend de                       |
| --------------------- | ------------------ | ------------- | -------------------------- | ------------------------------- |
| Kube Prometheus Stack | 56.21.1            | `monitoring`  | `https://grafana.<domain>` | Authelia (OIDC)                 |
| Hubble UI             | inclus dans Cilium | `kube-system` | `https://hubble.<domain>`  | Cilium, Authelia (Forward Auth) |

Le stack Prometheus inclut : Prometheus (collecte), Grafana (dashboards), Alertmanager (alertes).

### Critere de validation

- [ ] `https://grafana.<domain>` → connexion OIDC, dashboards pre-configures
- [ ] Metriques CPU/memoire/reseau des pods visibles
- [ ] `https://hubble.<domain>` → flux reseau entre namespaces visibles
- [ ] Alertmanager → regles d'alerte actives

### Resultat

L'equipe operations peut surveiller l'infrastructure, identifier les problemes de performance et visualiser les flux reseau.

---

## Jalon 6 : Securite Applicative

**Objectif** : appliquer les politiques de securite et les sauvegardes. Deploye en dernier pour ne pas bloquer les jalons precedents.

**Prerequis** : tous les jalons precedents completes.

### Commandes

```bash
ansible-playbook playbooks/phase-08-security.yml
```

### Composants deployes

| Composant              | Version | Fonction                                                       |
| ---------------------- | ------- | -------------------------------------------------------------- |
| Kyverno                | 3.3.0   | 8 policies de securite (Audit en local, Enforce en production) |
| Network Policies       | -       | Default deny + regles explicites par namespace                 |
| Pod Security Standards | -       | Baseline (staging) / Restricted (production)                   |
| Rate Limiting          | -       | Protection des endpoints publics                               |
| Secret Rotation        | -       | Rotation automatique via ESO                                   |
| Trivy Operator         | 0.19.0  | Scan d'images en continu                                       |
| Velero                 | 1.13.0  | Backups chiffres off-site                                      |

### Policies Kyverno

| Policy                   | Local | Production |
| ------------------------ | ----- | ---------- |
| disallow-privileged      | Audit | Enforce    |
| disallow-host-namespaces | Audit | Enforce    |
| disallow-host-path       | Audit | Enforce    |
| disallow-latest-tag      | Audit | Enforce    |
| restrict-registries      | Audit | Enforce    |
| require-labels           | Audit | Enforce    |
| require-resource-limits  | Audit | Enforce    |
| require-probes           | -     | Enforce    |

### Critere de validation

- [ ] `kubectl get clusterpolicies` → toutes Ready
- [ ] `kubectl get networkpolicies -A` → policies presentes dans chaque namespace
- [ ] `velero backup create test-backup` → backup reussi
- [ ] Trivy → scan des images en cours, rapport accessible

### Resultat

Le cluster est durci : isolation reseau entre namespaces, contraintes de securite sur les pods, backups automatiques et scan de vulnerabilites.

---

## Graphe de dependances

```text
                    ┌─────────────┐
                    │   K3s/K3D   │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │   Cilium    │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
       ┌──────▼──────┐ ┌──▼───┐ ┌──────▼──────┐
       │Envoy Gateway│ │Cert- │ │  Longhorn   │
       └──────┬──────┘ │Mgr   │ └──────┬──────┘
              │        └──┬───┘        │
              └────────────┼────────────┘
                           │
                    ┌──────▼──────┐
                    │    Vault    │
                    │  + ExtSecr  │
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              │                         │
       ┌──────▼──────┐          ┌───────▼─────┐
       │ PostgreSQL  │          │    Redis    │
       └──────┬──────┘          └───────┬─────┘
              │                         │
              └────────────┬────────────┘
                           │
                    ┌──────▼──────┐
                    │  Authelia   │◄──────────── Jalon 0
                    └──────┬──────┘
                           │
    ┌─────────┬────────────┼────────────┬─────────┐
    │         │            │            │         │
┌───▼───┐ ┌──▼────────┐ ┌─▼────────┐ ┌▼─────┐ ┌─▼────┐
│SeaWeed│ │Mattermost │ │ MariaDB  │ │Flipt │ │Gitea │
│  FS   │ └───────────┘ └──┬───────┘ └──────┘ └──┬───┘
└───┬───┘   Jalon 1     ┌──▼─────┐   Jalon 4  ┌──▼───┐
┌───▼─────┐              │ REDCap │            │ArgoCD│
│Nextcloud│              └──┬─────┘            └──────┘
└───┬─────┘              ┌──▼──┐                Jalon 4
┌───▼──────┐             │ECRIN│
│OnlyOffice│             └─────┘
└──────────┘             Jalon 3
  Jalon 2
                   ┌──────────┐    ┌───────────────┐
                   │Monitoring│    │   Securite     │
                   └──────────┘    │  Applicative   │
                     Jalon 5       └───────────────┘
                                      Jalon 6
```

---

## Recapitulatif des URLs par jalon

| Jalon | Service    | URL                        |
| ----- | ---------- | -------------------------- |
| 0     | Authelia   | `https://login.<domain>`   |
| 1     | Mattermost | `https://chat.<domain>`    |
| 2     | Nextcloud  | `https://cloud.<domain>`   |
| 2     | OnlyOffice | `https://office.<domain>`  |
| 3     | REDCap     | `https://redcap.<domain>`  |
| 3     | ECRIN      | `https://ecrin.<domain>`   |
| 4     | Flipt      | `https://flags.<domain>`   |
| 4     | Gitea      | `https://git.<domain>`     |
| 4     | ArgoCD     | `https://argocd.<domain>`  |
| 5     | Grafana    | `https://grafana.<domain>` |
| 5     | Hubble     | `https://hubble.<domain>`  |
