# Flux de donnees reseau

**Date** : 2026-02-10

Architecture reseau, routage, communication inter-services, politiques reseau et chiffrement.

---

## Vue d'ensemble

```text
                              INTERNET
                                 │
                         ┌───────▼────────┐
                         │  Envoy Gateway │  ports 80/443
                         │  (atlas-gateway)│  namespace: envoy-gateway-system
                         └───────┬────────┘
                                 │
               ┌─────── HTTPRoutes ────────┐
               │         (par service)     │
               │                           │
        ┌──────▼───────┐          ┌────────▼────────┐
        │ Route protegee│         │ Route libre      │
        │ SecurityPolicy│         │ (API, webhooks)  │
        │ OIDC / extAuth│         │ auth applicative │
        └──────┬───────┘          └────────┬────────┘
               │                           │
               ▼                           ▼
        ┌─────────────────────────────────────────┐
        │            Services applicatifs          │
        ├──────────┬───────────┬──────────────────┤
        │          │           │                  │
        ▼          ▼           ▼                  ▼
   PostgreSQL    Redis     MariaDB           SeaweedFS
   port 5432    port 6379  port 3306         port 8333
```

---

## Gateway — point d'entree unique

### Listeners

| Listener | Port | Protocole | Hostname     | Comportement                           |
| -------- | ---- | --------- | ------------ | -------------------------------------- |
| HTTP     | 80   | HTTP      | `*.<domain>` | Redirection 301 vers HTTPS             |
| HTTPS    | 443  | HTTPS     | `*.<domain>` | Terminaison TLS, routage vers backends |

### Certificat TLS

```text
  Certificat wildcard
  ├── Noms        : *.<domain>, <domain>
  ├── Secret      : wildcard-tls (ns: envoy-gateway-system)
  ├── Issuer      : ClusterIssuer (Let's Encrypt staging/prod, self-signed local)
  ├── Duree       : 90 jours
  └── Renouvellement : automatique, 15 jours avant expiration
```

### Ressources Gateway

```text
  atlas-gateway
  ├── GatewayClass    : envoy
  ├── Namespace       : envoy-gateway-system
  ├── Replicas        : 1 (local) / 2 (HA)
  ├── Rate limiting   : active
  └── External auth   : active (pour SecurityPolicy)
```

---

## Routage — HTTPRoutes par service

Chaque service est expose via un ou plusieurs HTTPRoutes. Les routes protegees
ont une SecurityPolicy attachee ; les routes libres utilisent l'authentification
applicative (tokens, HMAC, app passwords).

### Services applicatifs

| Service        | Hostname          | Routes protegees | Routes libres                                | Backend                   | Port |
| -------------- | ----------------- | ---------------- | -------------------------------------------- | ------------------------- | ---- |
| **Nextcloud**  | `cloud.<domain>`  | `/`              | `/remote.php/dav/`, `/ocs/`, `/.well-known/` | nextcloud                 | 8080 |
| **Mattermost** | `chat.<domain>`   | `/`              | `/api/v4/`, `/plugins/`, `/hooks/`           | mattermost-team-edition   | 8065 |
| **ECRIN**      | `ecrin.<domain>`  | `/`              | —                                            | ecrin                     | 80   |
| **REDCap**     | `redcap.<domain>` | `/`              | `/surveys`                                   | redcap                    | 80   |
| **OnlyOffice** | `office.<domain>` | `/`              | `/coauthoring/`                              | onlyoffice-documentserver | 80   |
| **Flipt**      | `flags.<domain>`  | `/`              | —                                            | flipt                     | 8080 |

### Outils DevOps

| Service    | Hostname          | Routes protegees | Routes libres               | Backend       | Port |
| ---------- | ----------------- | ---------------- | --------------------------- | ------------- | ---- |
| **ArgoCD** | `argocd.<domain>` | `/`              | `/api/webhook`              | argocd-server | 80   |
| **Gitea**  | `git.<domain>`    | `/`              | `/api/v1/`, `/.well-known/` | gitea-http    | 3000 |

### Monitoring

| Service       | Hostname           | Routes protegees | Routes libres | Backend   | Port |
| ------------- | ------------------ | ---------------- | ------------- | --------- | ---- |
| **Grafana**   | `grafana.<domain>` | `/`              | `/api/`       | grafana   | 3000 |
| **Hubble UI** | `hubble.<domain>`  | `/`              | —             | hubble-ui | 80   |

### Plateforme

| Service      | Hostname         | Routes                         | Backend       | Port |
| ------------ | ---------------- | ------------------------------ | ------------- | ---- |
| **Keycloak** | `login.<domain>` | `/` (non protege)              | keycloak-http | 8080 |
| **Authelia** | `login.<domain>` | `/` (non protege)              | authelia      | 9091 |
| **Vault**    | `vault.<domain>` | `/` (protege), `/v1/*` (libre) | vault         | 8200 |

### Timeouts specifiques

| Service   | Timeout       | Raison                        |
| --------- | ------------- | ----------------------------- |
| Nextcloud | 600s (10 min) | Upload de fichiers volumineux |
| Gitea     | 300s (5 min)  | Push de gros repositories     |

---

## Communication inter-services

### Carte des flux internes

```text
  ┌──────────────┐    OIDC     ┌──────────────┐
  │  Nextcloud   │◄───────────►│  Keycloak/   │
  │  cloud:8080  │             │  Authelia    │
  └──────┬───────┘             │  login:9091  │
         │                     └──────▲───────┘
         │ HTTPS (WOPI/JWT)           │ OIDC
         ▼                            │
  ┌──────────────┐             ┌──────┴───────┐
  │  OnlyOffice  │             │  Mattermost  │
  │ office:80    │             │  chat:8065   │
  └──────────────┘             └──────────────┘

  ┌──────────────┐  webhooks   ┌──────────────┐
  │   Gitea      │◄───────────►│   ArgoCD     │
  │  git:3000/22 │             │ argocd:80    │
  └──────────────┘             └──────────────┘

  ┌──────────────┐    S3       ┌──────────────┐
  │  Nextcloud   │────────────►│  SeaweedFS   │
  │              │  port 8333  │  (S3 API)    │
  └──────────────┘             └──────────────┘
```

### Detail des communications service-a-service

| Source     | Destination      | Protocole          | Port     | Usage                                    |
| ---------- | ---------------- | ------------------ | -------- | ---------------------------------------- |
| Nextcloud  | OnlyOffice       | HTTPS (public URL) | 443      | Edition collaborative (WOPI + JWT)       |
| OnlyOffice | Nextcloud        | HTTPS (callback)   | 443      | Callbacks co-edition via `/coauthoring/` |
| ArgoCD     | Gitea            | HTTP / SSH         | 3000, 22 | Synchronisation repositories Git         |
| Nextcloud  | SeaweedFS        | HTTP (S3)          | 8333     | Stockage objet primaire                  |
| ESO        | Vault            | HTTP               | 8200     | Synchronisation secrets Vault → K8s      |
| ECRIN      | REDCap (externe) | HTTPS              | 443      | Integration REDCap (URL configurable)    |

---

## Connexions aux bases de donnees

### PostgreSQL

**DNS** : `postgresql.postgresql.svc.cluster.local:5432`
**HA** : `postgresql-postgresql-ha-pgpool.postgresql.svc.cluster.local:5432`

```text
  ┌─────────────────────────────────────────────────────────────────┐
  │                    PostgreSQL (port 5432)                       │
  │                                                                 │
  │  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐      │
  │  │  vault    │ │ mattermost│ │ nextcloud │ │   gitea   │      │
  │  │  vault_   │ │ mattermost│ │ nextcloud_│ │  gitea_   │      │
  │  │  user     │ │ _user     │ │ user      │ │  user     │      │
  │  └─────▲─────┘ └─────▲─────┘ └─────▲─────┘ └─────▲─────┘      │
  │        │              │              │              │            │
  │  ┌─────┼──────┐ ┌─────┼──────┐ ┌─────┼──────┐ ┌─────┼──────┐  │
  │  │  flipt    │ │ authelia  │ │ keycloak  │ │            │  │
  │  │  flipt_   │ │ authelia_ │ │ keycloak_ │ │            │  │
  │  │  user     │ │ user      │ │ user      │ │            │  │
  │  └───────────┘ └───────────┘ └───────────┘ └────────────┘  │
  │                                                                 │
  │  Isolation L7 : chaque service ne peut acceder qu'a sa base    │
  │  TLS : sslmode=require (staging/production)                    │
  └─────────────────────────────────────────────────────────────────┘
```

| Service    | Base       | Utilisateur     | Privileges                  | TLS |
| ---------- | ---------- | --------------- | --------------------------- | --- |
| Vault      | vault      | vault_user      | ALL PRIVILEGES (migrations) | Oui |
| Keycloak   | keycloak   | keycloak_user   | ALL PRIVILEGES (migrations) | Oui |
| Mattermost | mattermost | mattermost_user | CRUD                        | Oui |
| Nextcloud  | nextcloud  | nextcloud_user  | CRUD                        | Oui |
| Gitea      | gitea      | gitea_user      | CRUD                        | Oui |
| Flipt      | flipt      | flipt_user      | CRUD                        | Oui |
| Authelia   | authelia   | authelia_user   | CRUD                        | Oui |

### MariaDB

**DNS** : `mariadb.mariadb.svc.cluster.local:3306`

| Service | Base   | Utilisateur | TLS |
| ------- | ------ | ----------- | --- |
| REDCap  | redcap | redcap_user | Oui |

### Redis

**DNS** : `redis-master.redis.svc.cluster.local:6379`

| Service   | Usage                                       | Database |
| --------- | ------------------------------------------- | -------- |
| Authelia  | Sessions                                    | —        |
| Nextcloud | Sessions, cache                             | —        |
| Gitea     | Cache (`/0`), sessions (`/1`), queue (`/2`) | 0, 1, 2  |

---

## Acces SSH (Gitea)

```text
  Utilisateur
      │
      │  git clone ssh://git@git.<domain>:22/user/repo.git
      │
      ▼
  Noeud K8s (NodePort 30022)
      │
      ▼
  Service gitea-ssh-nodeport
      │  port 22 → targetPort 22
      ▼
  Pod Gitea (port 22)
```

Le NodePort 30022 est expose sur tous les noeuds du cluster.

---

## Politiques reseau (Cilium)

### Principe : default deny

Chaque namespace applique une politique `default-deny` qui bloque tout trafic
entrant et sortant. Seuls les flux explicitement autorises sont ouverts.

```text
  Politique par defaut (appliquee a tous les namespaces proteges) :

  1. default-deny         Bloque tout ingress et egress
  2. allow-dns            Autorise DNS vers kube-system:53
  3. allow-prometheus      Autorise scraping Prometheus depuis monitoring
```

### Namespaces proteges

vault, postgresql, mariadb, redis, authelia, keycloak, mattermost, nextcloud,
onlyoffice, seaweedfs, redcap, ecrin, flipt, gitea, argocd, monitoring

### Politiques d'ingress (entrant)

| Namespace  | Source autorisee           | Port(s)    | Raison                    |
| ---------- | -------------------------- | ---------- | ------------------------- |
| authelia   | envoy-gateway-system       | 9091       | Portail login + ext-authz |
| keycloak   | envoy-gateway-system       | 8080       | Console admin + OIDC      |
| vault      | envoy-gateway-system       | 8200       | UI Vault                  |
| vault      | external-secrets           | 8200       | ESO → Vault API           |
| mattermost | envoy-gateway-system       | 8065       | Trafic web                |
| nextcloud  | envoy-gateway-system       | 8080       | Trafic web                |
| gitea      | envoy-gateway-system       | 3000, 22   | HTTP + SSH                |
| argocd     | envoy-gateway-system       | 80, 443    | Trafic web                |
| redis      | authelia, nextcloud, gitea | 6379       | Sessions, cache           |
| seaweedfs  | nextcloud                  | 8333, 8888 | S3 API + Filer            |
| postgresql | _services applicatifs_     | 5432       | Connexions BDD (L7)       |
| mariadb    | redcap                     | 3306       | Connexion BDD (L7)        |

### Politiques d'egress (sortant)

| Namespace  | Destination | Port(s)  | Raison               |
| ---------- | ----------- | -------- | -------------------- |
| authelia   | redis       | 6379     | Sessions             |
| authelia   | postgresql  | 5432     | Stockage             |
| mattermost | postgresql  | 5432     | BDD                  |
| nextcloud  | postgresql  | 5432     | BDD                  |
| nextcloud  | redis       | 6379     | Cache/sessions       |
| nextcloud  | seaweedfs   | 8333     | Stockage objet       |
| gitea      | postgresql  | 5432     | BDD                  |
| gitea      | redis       | 6379     | Cache/sessions/queue |
| vault      | postgresql  | 5432     | BDD                  |
| flipt      | postgresql  | 5432     | BDD                  |
| keycloak   | postgresql  | 5432     | BDD                  |
| redcap     | mariadb     | 3306     | BDD                  |
| argocd     | gitea       | 3000, 22 | Git sync             |
| argocd     | 0.0.0.0/0   | 443, 22  | Repos Git externes   |

### Isolation L7 PostgreSQL

Cilium applique un filtrage au niveau applicatif (L7) sur les connexions PostgreSQL.
Chaque service est restreint a sa propre base de donnees :

```text
  CiliumNetworkPolicy (L7 PostgreSQL)
  ├── vault       → peut uniquement acceder a la base "vault"
  ├── mattermost  → peut uniquement acceder a la base "mattermost"
  ├── nextcloud   → peut uniquement acceder a la base "nextcloud"
  ├── gitea       → peut uniquement acceder a la base "gitea"
  ├── flipt       → peut uniquement acceder a la base "flipt"
  └── authelia    → peut uniquement acceder a la base "authelia"
```

Active uniquement en staging/production (`network_policy_l7_enabled`).

---

## Chiffrement reseau

### Couches de chiffrement

```text
  Couche                   Protocole          Environnement
  ──────────────────────────────────────────────────────────

  1. Client → Gateway      TLS 1.2+           Tous
     (HTTPS terminaison)   Let's Encrypt      (self-signed en local)

  2. Gateway → Service     HTTP clair          Tous
     (reseau interne)      (protege par 3+4)

  3. Service → BDD         TLS                 Staging/Production
     (PostgreSQL/MariaDB)  sslmode=require

  4. Node → Node           WireGuard           Staging/Production
     (pod-to-pod)          Curve25519
```

### WireGuard (inter-noeuds)

```text
  Cilium Agent
  ├── Mode              : wireguard
  ├── Protocole         : WireGuard (Curve25519)
  ├── Clefs             : generees automatiquement par noeud
  ├── Rotation          : automatique et transparente
  ├── Fallback userspace: active
  └── Environnement     : staging/production (desactive en local)
```

### TLS interne (bases de donnees)

| Service    | DNS SAN                                                                         | Secret         |
| ---------- | ------------------------------------------------------------------------------- | -------------- |
| PostgreSQL | `postgresql.postgresql.svc.cluster.local`, `*.postgresql-hl.*`                  | postgresql-tls |
| MariaDB    | `mariadb.mariadb.svc.cluster.local`, `mariadb-primary.*`, `mariadb-secondary.*` | mariadb-tls    |

---

## Noms DNS et ports internes

Reference complete des services Kubernetes et leurs coordonnees reseau :

### Plateforme

| Service  | DNS interne                                | Port | Namespace |
| -------- | ------------------------------------------ | ---- | --------- |
| Keycloak | `keycloak-http.keycloak.svc.cluster.local` | 8080 | keycloak  |
| Authelia | `authelia.authelia.svc.cluster.local`      | 9091 | authelia  |
| Vault    | `vault.vault.svc.cluster.local`            | 8200 | vault     |

### Donnees

| Service         | DNS interne                                                    | Port | Namespace  |
| --------------- | -------------------------------------------------------------- | ---- | ---------- |
| PostgreSQL      | `postgresql.postgresql.svc.cluster.local`                      | 5432 | postgresql |
| PostgreSQL HA   | `postgresql-postgresql-ha-pgpool.postgresql.svc.cluster.local` | 5432 | postgresql |
| MariaDB         | `mariadb.mariadb.svc.cluster.local`                            | 3306 | mariadb    |
| Redis           | `redis-master.redis.svc.cluster.local`                         | 6379 | redis      |
| SeaweedFS S3    | `seaweedfs-s3.seaweedfs.svc.cluster.local`                     | 8333 | seaweedfs  |
| SeaweedFS Filer | `seaweedfs-filer.seaweedfs.svc.cluster.local`                  | 8888 | seaweedfs  |

### Applications

| Service    | DNS interne                                              | Port | Namespace  |
| ---------- | -------------------------------------------------------- | ---- | ---------- |
| Nextcloud  | `nextcloud.nextcloud.svc.cluster.local`                  | 8080 | nextcloud  |
| Mattermost | `mattermost-team-edition.mattermost.svc.cluster.local`   | 8065 | mattermost |
| OnlyOffice | `onlyoffice-documentserver.onlyoffice.svc.cluster.local` | 80   | onlyoffice |
| REDCap     | `redcap.redcap.svc.cluster.local`                        | 80   | redcap     |
| ECRIN      | `ecrin.ecrin.svc.cluster.local`                          | 80   | ecrin      |
| Flipt      | `flipt.flipt.svc.cluster.local`                          | 8080 | flipt      |

### DevOps

| Service    | DNS interne                              | Port | Namespace |
| ---------- | ---------------------------------------- | ---- | --------- |
| Gitea HTTP | `gitea-http.gitea.svc.cluster.local`     | 3000 | gitea     |
| Gitea SSH  | `gitea-http.gitea.svc.cluster.local`     | 22   | gitea     |
| ArgoCD     | `argocd-server.argocd.svc.cluster.local` | 80   | argocd    |

### Monitoring

| Service    | DNS interne                               | Port | Namespace   |
| ---------- | ----------------------------------------- | ---- | ----------- |
| Grafana    | `grafana.monitoring.svc.cluster.local`    | 3000 | monitoring  |
| Prometheus | `prometheus.monitoring.svc.cluster.local` | 9090 | monitoring  |
| Hubble UI  | `hubble-ui.kube-system.svc.cluster.local` | 80   | kube-system |
