# Makefile pour le projet k8s
# Commandes de linting et validation Ansible

.PHONY: help lint lint-fix syntax-check format install-hooks install-deps

# Couleurs pour l'affichage
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
NC     := \033[0m # No Color

help: ## Afficher cette aide
	@echo "$(GREEN)Commandes disponibles:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'

install-deps: ## Installer toutes les dépendances
	@echo "$(GREEN)Installation des dépendances...$(NC)"
	pip install ansible-lint yamllint
	ansible-galaxy install -r ansible/requirements.yml
	lefthook install

install-hooks: ## Installer les git hooks avec lefthook
	@echo "$(GREEN)Installation des git hooks...$(NC)"
	lefthook install
	@echo "$(GREEN)✓ Git hooks installés$(NC)"

lint: ## Linter le projet Ansible
	@echo "$(GREEN)Linting du projet...$(NC)"
	ansible-lint --profile=production

lint-fix: ## Linter et corriger automatiquement
	@echo "$(GREEN)Linting avec auto-fix...$(NC)"
	ansible-lint --fix --profile=production

lint-report: ## Générer un rapport de linting
	@echo "$(GREEN)Génération du rapport...$(NC)"
	ansible-lint --format=codeclimate > ansible-lint-report.json
	@echo "$(GREEN)✓ Rapport généré: ansible-lint-report.json$(NC)"

syntax-check: ## Vérifier la syntaxe des playbooks
	@echo "$(GREEN)Vérification de la syntaxe...$(NC)"
	@for playbook in ansible/*.yml; do \
		echo "Checking $$playbook..."; \
		ansible-playbook --syntax-check $$playbook || exit 1; \
	done
	@echo "$(GREEN)✓ Syntaxe correcte$(NC)"

yamllint: ## Linter les fichiers YAML
	@echo "$(GREEN)Validation YAML...$(NC)"
	yamllint -c .yamllint --strict .

format: lint-fix ## Alias pour lint-fix

check: lint yamllint ## Lancer tous les checks (lint + yamllint)

pre-commit: ## Tester les hooks pre-commit sur tous les fichiers
	@echo "$(GREEN)Test des hooks pre-commit...$(NC)"
	lefthook run pre-commit --all-files

# Commandes Ansible
galaxy-install: ## Installer les collections et rôles Ansible
	@echo "$(GREEN)Installation des collections Ansible...$(NC)"
	ansible-galaxy install -r ansible/requirements.yml

galaxy-update: ## Mettre à jour les collections et rôles
	@echo "$(GREEN)Mise à jour des collections...$(NC)"
	ansible-galaxy install -r ansible/requirements.yml --force

# Nettoyage
clean: ## Nettoyer les fichiers temporaires
	@echo "$(GREEN)Nettoyage...$(NC)"
	find . -type f -name '*.retry' -delete
	find . -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name '.pytest_cache' -exec rm -rf {} + 2>/dev/null || true
	rm -f ansible-lint-report.json
	@echo "$(GREEN)✓ Nettoyage terminé$(NC)"

# CI/CD
ci: install-deps lint syntax-check ## Commande CI complète

.DEFAULT_GOAL := help
