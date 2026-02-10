# Audit de maturité production — ATLAS Platform

> Date : 2026-02-10
> Score : 7.5 / 10 — Prêt pour staging avancé / production pilote

## Points traités dans cette release

| # | Amélioration | Statut |
|---|-------------|--------|
| 1 | Vault auto-unseal (AWS KMS / GCP / Azure) | Déjà implémenté |
| 2 | PodDisruptionBudgets (PostgreSQL, Redis, Keycloak, ArgoCD, Kyverno, Vault, Envoy) | Fait |
| 3 | Centralized logging (Loki + Alloy) | Fait |
| 4 | HorizontalPodAutoscaler (Mattermost, Nextcloud, Flipt, ECRIN) | Fait |
| 5 | SMTP via Brevo (Keycloak, Mattermost, Nextcloud, Gitea) | Fait |
| 9 | Health probes manquants (Mattermost, Nextcloud, Gitea, Vault) | Fait |
| 10 | Progressive delivery (Argo Rollouts) | Fait |

## Points non traités — Backlog de durcissement

### Priorité haute

#### CI/CD automatisé des déploiements

- **Problème** : Les déploiements sont manuels via `ansible-playbook`. Pas d'audit trail automatisé, pas de rollback natif.
- **Recommandation** : Migrer les manifests Helm vers des repos Git dédiés, piloter les déploiements via ArgoCD ApplicationSets. Réserver Ansible au provisioning initial (phases 0-2).
- **Effort estimé** : 2-3 semaines

#### Gating Trivy — Bloquer les images vulnérables

- **Problème** : Trivy Operator scanne les images mais ne bloque pas le déploiement d'images avec des CVE critiques.
- **Recommandation** : Ajouter une ClusterPolicy Kyverno `verify-image-scan` qui refuse les pods dont l'image a des vulnérabilités HIGH/CRITICAL non corrigées.
- **Fichiers concernés** : `roles/security/kyverno/templates/policies/`
- **Effort estimé** : 1-2 jours

#### Disaster Recovery runbook

- **Problème** : Les backups Velero sont configurés mais aucun RTO/RPO n'est défini. Les procédures de restauration ne sont pas documentées ni testées.
- **Recommandation** :
  - Définir RTO < 4h, RPO < 1h
  - Documenter les procédures de restauration par composant
  - Automatiser un test de restauration mensuel en staging
  - Créer un playbook `playbooks/disaster-recovery.yml`
- **Effort estimé** : 1 semaine

### Priorité moyenne

#### Tests de restauration backup automatisés

- **Problème** : Aucune validation que les backups sont restaurables.
- **Recommandation** : CronJob Kubernetes qui restaure un backup dans un namespace éphémère, vérifie l'intégrité, puis supprime.
- **Effort estimé** : 3-5 jours

#### Rotation du mot de passe admin Keycloak

- **Problème** : Le mot de passe admin est défini au déploiement et n'est pas rotable automatiquement.
- **Recommandation** : Ajouter une tâche Ansible de rotation (90 jours) qui met à jour le secret Kubernetes et Vault.
- **Effort estimé** : 1-2 jours

#### Alertmanager HA

- **Problème** : Alertmanager tourne avec 1 seul replica. Risque de perte d'alertes lors des maintenances.
- **Recommandation** : Passer à 3 replicas en production dans `kube_prometheus/defaults/main.yml`.
- **Effort estimé** : 1 heure

### Priorité basse

#### Custom Grafana dashboards

- **Problème** : Seuls les dashboards par défaut de kube-prometheus-stack sont disponibles.
- **Recommandation** : Créer des ConfigMaps avec des dashboards JSON pour : overview applicatif, logs Loki, métriques Keycloak, santé PostgreSQL.
- **Effort estimé** : 2-3 jours

#### SLO/SLI

- **Problème** : Aucun objectif de niveau de service défini.
- **Recommandation** : Définir des SLI (latence p99, taux d'erreur, disponibilité) et des SLO par service. Implémenter via Prometheus recording rules + alertes.
- **Effort estimé** : 1 semaine

#### Documentation en anglais

- **Problème** : La documentation est principalement en français, ce qui limite l'adoption internationale.
- **Recommandation** : Traduire les pages VitePress critiques (quickstart, architecture, secrets) en anglais.
- **Effort estimé** : 2-3 jours
