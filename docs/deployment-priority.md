# Guide de Deploiement Priorise - ATLAS Platform

**Date** : 2026-02-10
**Branche** : `feature/ansible-atlas-platform`

Ce guide structure le deploiement de la plateforme en **jalons** orientes valeur metier.
Chaque jalon produit un resultat utilisable et constitue un point de validation
avant de passer au suivant.

> **Gestion des secrets SSO** : lorsque Vault est disponible (staging/production),
> les secrets de Keycloak (admin password, OIDC client secrets) et d'Authelia (JWT, session, OIDC HMAC, cle privee RSA)
> sont generes au premier deploiement, stockes dans Vault et synchronises vers Kubernetes via External Secrets Operator.
> En local (sans Vault), les secrets sont generes directement par Ansible (fallback).

---

## Deploiement automatique avec resolution de dependances

Chaque composant declare ses dependances dans `ansible/vars/dependency_graph.yml`.
Le playbook `deploy.yml` resout l'arbre complet, verifie quels composants sont deja
operationnels dans le cluster, et ne deploie que les manquants dans l'ordre topologique.

### Usage

```bash
# Deployer un composant (+ toutes ses dependances manquantes)
task deploy -- mattermost

# Lister les composants disponibles
task deploy-list

# Voir la chaine de dependances sans rien deployer
task deploy-deps -- mattermost
```

### Exemple : `task deploy -- mattermost`

Le systeme resout la chaine complete :

```text
k3s → cilium → envoy_gateway → longhorn → cert_manager → vault → external_secrets → postgresql → redis → keycloak/authelia → mattermost
```

Puis verifie chaque composant via l'API Kubernetes. Si K3s, Cilium et Vault sont deja operationnels, seuls les composants manquants sont deployes.

> **Note** : les playbooks par phase (`site.yml`, `phase-*.yml`) restent disponibles et inchanges pour le deploiement manuel ou sequentiel.

---

## Vue d'ensemble des jalons

```text
Jalon 0   Infrastructure         Cluster K8s, secrets, PostgreSQL, Redis, Keycloak/Authelia (SSO)
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
ansible-playbook playbooks/phase-05-services.yml --tags keycloak,authelia
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
| 11.1  | Keycloak         | 26.0         | IAM, SSO, OIDC, MFA (staging/prod)  | PostgreSQL, ESO          |
| 11.2  | Authelia         | 0.9.0        | Forward Auth, OIDC, MFA (local)      | PostgreSQL, Redis, ESO   |

### Critere de validation

- [ ] `kubectl get nodes` → tous Ready
- [ ] `cilium status` → OK
- [ ] `vault status` → Initialized, Unsealed
- [ ] PostgreSQL : `\l` liste les 5 databases
- [ ] `https://login.<domain>` → portail SSO (Keycloak ou Authelia) accessible, connexion test OK

### Bases de donnees creees

**PostgreSQL** (`postgresql.postgresql.svc.cluster.local:5432`) :

| Database     | Service    | Utilisateur       | Utilise par |
| ------------ | ---------- | ----------------- | ----------- |
| `keycloak`   | Keycloak   | `keycloak_user`   | Jalon 0     |
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
task deploy -- mattermost
# ou manuellement :
ansible-playbook playbooks/phase-05-services.yml --tags mattermost
```

### Composants deployes

| Composant  | Version | Namespace    | URL                     | Depend de                   |
| ---------- | ------- | ------------ | ----------------------- | --------------------------- |
| Mattermost | 9.11    | `mattermost` | `https://chat.<domain>` | PostgreSQL, SSO (OIDC) |

### Critere de validation

- [ ] `https://chat.<domain>` → page de connexion
- [ ] Connexion via SSO (bouton "Login with Keycloak/Authelia")
- [ ] Creation d'un canal, envoi d'un message

### Resultat

Les utilisateurs peuvent se connecter via SSO et communiquer par messagerie instantanee (canaux, messages directs, fils de discussion).

---

## Jalon 2 : Collaboration

**Objectif** : l'equipe peut stocker, partager et editer des documents en ligne.

**Prerequis** : Jalon 0 complet.

### Commandes

```bash
task deploy -- nextcloud    # deploie aussi seaweedfs si absent
task deploy -- onlyoffice
# ou manuellement :
ansible-playbook playbooks/phase-05-services.yml --tags seaweedfs,nextcloud,onlyoffice
```

### Composants deployes (dans cet ordre)

| Ordre | Composant  | Version | Namespace    | URL                       | Depend de                       |
| ----- | ---------- | ------- | ------------ | ------------------------- | ------------------------------- |
| 1     | SeaweedFS  | 3.67.0  | `seaweedfs`  | interne                   | Vault, Longhorn                 |
| 2     | Nextcloud  | 29      | `nextcloud`  | `https://cloud.<domain>`  | SSO, PostgreSQL, SeaweedFS |
| 3     | OnlyOffice | 8.0.1   | `onlyoffice` | `https://office.<domain>` | SSO                        |

**Ordre important** : SeaweedFS fournit le stockage S3 pour Nextcloud. OnlyOffice s'integre dans Nextcloud pour l'edition de documents.

### Critere de validation

- [ ] `https://cloud.<domain>` → connexion Nextcloud via SSO
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
task deploy -- redcap     # deploie aussi mariadb si absent
task deploy -- ecrin
# ou manuellement :
ansible-playbook playbooks/phase-04-databases.yml --tags mariadb
ansible-playbook playbooks/phase-05-services.yml --tags redcap,ecrin
```

### Composants deployes

| Ordre | Composant | Version | Namespace | URL                       | Depend de                           |
| ----- | --------- | ------- | --------- | ------------------------- | ----------------------------------- |
| 1     | MariaDB   | 18.2.2  | `mariadb` | interne                   | Vault, Longhorn                     |
| 2     | REDCap    | 14.0.0  | `redcap`  | `https://redcap.<domain>` | MariaDB, SSO (Forward Auth)    |
| 3     | ECRIN     | 1.0.0   | `ecrin`   | `https://ecrin.<domain>`  | SSO (OIDC), REDCap (optionnel) |

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
task deploy -- flipt
task deploy -- gitea
task deploy -- argocd
# ou manuellement :
ansible-playbook playbooks/phase-05-services.yml --tags flipt
ansible-playbook playbooks/phase-06-devops.yml
```

### Composants deployes (dans cet ordre)

| Ordre | Composant | Chart version | Namespace | URL                       | Depend de                          |
| ----- | --------- | ------------- | --------- | ------------------------- | ---------------------------------- |
| 1     | Flipt     | 1.35.0        | `flipt`   | `https://flags.<domain>`  | SSO, PostgreSQL               |
| 2     | Gitea     | 10.1.1        | `gitea`   | `https://git.<domain>`    | SSO, PostgreSQL               |
| 3     | ArgoCD    | 6.4.0         | `argocd`  | `https://argocd.<domain>` | SSO (OIDC), Gitea (optionnel) |

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
task deploy -- kube_prometheus
task deploy -- hubble_ui
# ou manuellement :
ansible-playbook playbooks/phase-07-monitoring.yml
```

### Composants deployes

| Composant             | Chart version      | Namespace     | URL                        | Depend de                                 |
| --------------------- | ------------------ | ------------- | -------------------------- | ----------------------------------------- |
| Kube Prometheus Stack | 56.21.1            | `monitoring`  | `https://grafana.<domain>` | SSO (proxy auth), Envoy GW, Longhorn |
| Hubble UI             | inclus dans Cilium | `kube-system` | `https://hubble.<domain>`  | Cilium (Deployment), SSO, Envoy GW   |

Le stack Prometheus inclut : Prometheus (collecte, 50Gi, retention 15j), Grafana (dashboards, proxy auth SSO), Alertmanager (alertes).

**Grafana** utilise le SSO en proxy auth : les headers `Remote-User`, `Remote-Email`, `Remote-Groups` sont mappes vers les roles Grafana (admins→Admin, devops→Editor, users→Viewer).

**Hubble UI** est deploye par Cilium ; ce role ne cree que l'HTTPRoute et la SecurityPolicy (forward auth SSO).

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
task deploy -- kyverno
task deploy -- network_policies
task deploy -- pod_security
task deploy -- rate_limiting
task deploy -- secret_rotation
task deploy -- image_scanning
task deploy -- backup_offsite
# ou manuellement :
ansible-playbook playbooks/phase-08-security.yml
```

### Composants deployes

| Composant              | Version | Fonction                                                       | Depend de                 |
| ---------------------- | ------- | -------------------------------------------------------------- | ------------------------- |
| Kyverno                | 3.3.0   | 8 policies de securite (Audit en local, Enforce en production) | K3s                       |
| Network Policies       | -       | Default deny + regles explicites par namespace                 | Cilium                    |
| Pod Security Standards | -       | Baseline (staging) / Restricted (production)                   | K3s                       |
| Rate Limiting          | -       | Protection des endpoints publics                               | Cilium, Envoy GW          |
| Secret Rotation        | -       | Rotation automatique via ESO (production)                      | Vault, External Secrets   |
| Trivy Operator         | 0.19.0  | Scan d'images, alertes Prometheus                              | Kube Prometheus (alertes) |
| Velero                 | 1.13.0  | Backups chiffres off-site (production)                         | Longhorn                  |

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
                    │ Keycloak/  │◄──────────── Jalon 0
                    │ Authelia   │
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
                           │
              ┌────────────┴────────────┐
              │                         │
       ┌──────▼──────┐          ┌───────▼─────┐
       │  Grafana    │          │  Hubble UI  │
       │ (Prometheus)│          │  (Cilium)   │
       └──────┬──────┘          └─────────────┘
              │                   Jalon 5
       ┌──────▼──────┐
       │Trivy (scans)│
       └─────────────┘

  ┌─────────┐ ┌──────────┐ ┌──────────┐ ┌─────────┐ ┌──────────┐ ┌──────┐
  │ Kyverno │ │ Network  │ │   Pod    │ │  Rate   │ │  Secret  │ │Velero│
  │ (K3s)   │ │ Policies │ │ Security │ │Limiting │ │ Rotation │ │(Long)│
  └─────────┘ │ (Cilium) │ │  (K3s)   │ │(Cil+EG) │ │(Vlt+ESO) │ └──────┘
              └──────────┘ └──────────┘ └─────────┘ └──────────┘  Jalon 6
```

---

## Recapitulatif des URLs par jalon

| Jalon | Service    | URL                        |
| ----- | ---------- | -------------------------- |
| 0     | Keycloak/Authelia | `https://login.<domain>`   |
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
