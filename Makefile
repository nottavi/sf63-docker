-include .env

_WARN := "\033[33m[%s]\033[0m %s\n"  # Yellow text for "printf"
_TITLE := "\033[32m[%s]\033[0m %s\n" # Green text for "printf"
_ERROR := "\033[31m[%s]\033[0m %s\n" # Red text for "printf"

SHELL=bash

DOCKER               ?= docker
DOCKER_COMPOSE       ?= docker compose
DOCKER_COMPOSE_EXEC  ?= $(DOCKER_COMPOSE) exec -T
DOCKER_COMPOSE_RUN   ?= $(DOCKER_COMPOSE) run --rm
DOCKER_COMPOSE_RUN_EP?= $(DOCKER_COMPOSE_RUN) --entrypoint=/bin/entrypoint

EXEC_IN_APP          ?= $(DOCKER_COMPOSE_EXEC) app /bin/entrypoint
EXEC_IN_DATABASE     ?= $(DOCKER_COMPOSE_EXEC) database

RUN_IN_APP           ?= $(DOCKER_COMPOSE_RUN_EP) --no-deps app
RUN_IN_APP_WITH_DEPS ?= $(DOCKER_COMPOSE_RUN_EP) app
EXEC_NODE            ?= $(DOCKER_COMPOSE_EXEC) node
RUN_NODE             ?= $(DOCKER_COMPOSE_RUN) node

PHP                  ?= $(EXEC_IN_APP) php
PHP_RUN              ?= $(RUN_IN_APP) php
COMPOSER             ?= $(RUN_IN_APP) composer
SF_CONSOLE           ?= $(PHP) ./bin/console
WEBPACK              ?= $(EXEC_IN_APP) ./node_modules/.bin/encore
YARN                 ?= $(EXEC_NODE) yarn
YARN_RUN             ?= $(RUN_NODE) yarn
MYSQL                ?= $(EXEC_IN_DATABASE) mysql

FAKE_WORDPRESS_DB    ?= 1602057293_gma_agence_differente_fr.sql

define main_title
	@{ \
    set -e ;\
    msg="Make $@";\
    printf "\033[34m$$msg\n" ;\
    for i in $$(seq 1 $${#msg}) ; do printf '=' ; done ;\
    printf "\033[0m\n" ;\
    }
endef

##@ Project

start: ## Start the project
start:
	$(call main_title,)
	$(DOCKER_COMPOSE) up -d

down: ## Down the project
	$(call main_title,)
## $(DOCKER_COMPOSE) down --remove-orphans --volumes

stop: ## Stop the project
	$(call main_title,)
	$(DOCKER_COMPOSE) stop

terminal: ## Launch a bash terminal
	$(call main_title,)
	$(DOCKER_COMPOSE) exec app entrypoint bash

terminal-root: ## Launch a root bash terminal
	$(call main_title,)
	$(DOCKER_COMPOSE) exec app bash

install: ## Install and start the project
##install: checkenv git-hooks docker vendor acl assets-install assets db vhosts
install: checkenv docker vendor acl assets-install assets db vhosts

install-prod: ## Install the project for prod
install-prod: vendor acl assets-install assets-build db-create db-migrate

update: ## Update the project if already installed (keep database data)
update: docker vendor assets-install assets db-migrate

confirm:
	@if [[ -z "$(CI)" ]]; then \
		REPLY="" ; \
		read -p "⚠ Are you sure? [y/n] > " -r ; \
		if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then \
			printf $(_ERROR) "KO" "Stopping" ; \
			exit 1 ; \
		else \
			printf $(_TITLE) "OK" "Continuing" ; \
			exit 0; \
		fi \
	fi
.PHONY: confirm

obliterate:
	@printf $(_ERROR) "WARNING" "This will remove EVERYTHING and result into a setup similar to a fresh \"git clone\"."

	@if $(MAKE) -s confirm ; then \
		printf $(_TITLE) "Ok" "Let's go!"; \
	else \
		printf $(_WARN) "Nevermind"; \
		exit 1; \
	fi

	@printf $(_TITLE) "Project" "Stopping & deleting all containers, volumes, etc."
	@$(DOCKER_COMPOSE) down --volumes --remove-orphans --rmi all
	@$(DOCKER_COMPOSE) rm --force -v --stop

	@printf $(_TITLE) "Project" "Removing non-versioned files"
	@git clean -dx --force \
		--exclude=".env*.local" \
		--exclude="docker-compose.override.y*ml" \
		--exclude=".idea"
.PHONY: obliterate

##@ Interactive Commands

sf-console: ## Run interactive symfony command
	$(call main_title,)
	@read -p "command [options] [arguments]: " command; \
	$(SF_CONSOLE) $$command;

composer:  ## Run interactive composer command
	$(call main_title,)
	@read -p "command [options] [arguments]: " command; \
	$(COMPOSER) $$command;

npm:  ## Run interactive npm command
	$(call main_title,)
	@read -p "[command] [flags]: " command; \
	$(YARN) $$command;

##@ Utils

checkenv: ## Check if .env file exist
	$(call main_title,)
	@if [ ! -f .env ]; \
	then\
		user_id=$(shell id -u); \
		default_project_name=$(notdir $(CURDIR)); \
		read -p "Project name (\"$$default_project_name\"): " project_name; \
		project_name=$${project_name:-$$default_project_name}; \
		app_secret=$$(openssl rand -base64 128 | grep -o '[[:alnum:]]' | head -n 32 | tr -d '\n'); \
		db_password=$$(openssl rand -base64 128 | grep -o '[[:alnum:]]' | head -n 32 | tr -d '\n'); \
		redis_password=$$(openssl rand -base64 128 | grep -o '[[:alnum:]]' | head -n 32 | tr -d '\n'); \
		echo $(openssl rand -base64 32); \
		cp .env.dist .env; \
		if [ $(shell uname -s) = "Darwin" ]; then \
			sed -i "" "s/__USER_ID__/$$user_id/g" .env; \
			sed -i "" "s/__PROJECT_NAME__/$$project_name/g" .env; \
			sed -i "" "s/__APP_SECRET__/$$app_secret/g" .env; \
			sed -i "" "s/__DB_PASSWORD__/$$db_password/g" .env; \
			sed -i "" "s/__PROJECT_NAME__/$$project_name/g" README.md; \
			sed -i "" "s/__PROJECT_NAME__/$$project_name/g" composer.json; \
			sed -i "" "s/__REDIS_PASSWORD__/$$redis_password/g" .env; \
		else \
			sed -i "s/__USER_ID__/$$user_id/g" .env; \
			sed -i "s/__PROJECT_NAME__/$$project_name/g" .env; \
			sed -i "s/__APP_SECRET__/$$app_secret/g" .env; \
			sed -i "s/__DB_PASSWORD__/$$db_password/g" .env; \
			sed -i "s/__PROJECT_NAME__/$$project_name/g" README.md; \
			sed -i "s/__PROJECT_NAME__/$$project_name/g" composer.json; \
			sed -i "s/__REDIS_PASSWORD__/$$redis_password/g" composer.json; \
		fi; \
	fi

git-hooks: ## Link the local ignored git hook folder to the versionned one
	$(call main_title,)
	rm -rf .git/hooks
	ln -s ../.git-hooks .git/hooks

.PHONY: docker
docker:
	$(call main_title,)
	$(DOCKER_COMPOSE) kill
	@${MAKE} down
	$(DOCKER_COMPOSE) pull --quiet --ignore-pull-failures
	$(DOCKER_COMPOSE) build
	@${MAKE} start

acl: ## Set filesystem access rights
	$(call main_title,)
	@echo "Setting permissions for logs..."
	-@$(RUN_IN_APP) "mkdir -p var/log/"
	-@$(RUN_IN_APP) "chmod -R 755 var/log/"

.PHONY: vendor
vendor: ## Composer install
vendor: composer.json
	$(call main_title,)
	@if [ "$(APP_ENV)" = "prod" ]; then \
		$(COMPOSER) install --optimize-autoloader --no-progress --no-suggest --classmap-authoritative --no-interaction; \
	else \
		$(COMPOSER) install; \
	fi

assets-install: ## assets install
assets-install: package.json
	$(call main_title,)
	$(YARN_RUN) install

.PHONY: assets
assets: assets-install ## Generate assets using webpack
	$(call main_title,)
	@printf $(_WARN) "⚠ Warning: this can take a few minutes."
	##@ //$(YARN_RUN) dev

assets-watch: ## Generate assets using webpack in continuous (watch mode)
	$(call main_title,)
	$(YARN) run watch

assets-build: ## Generate assets using webpack for production
	$(call main_title,)
	@printf $(_WARN) "⚠ Warning: this can take a few minutes."
	$(YARN) run build

cache-clear: ## Clear and warmup cache
	$(call main_title,)
	$(PHP) bin/console --ansi cache:clear

db: ## Drop and create database then run migrations
db: db-drop db-create db-migrate fixtures

db-create: ## Create database
	$(call main_title,)
	$(PHP) bin/console --ansi doctrine:database:create --if-not-exists

db-drop: ## Drop database
	$(call main_title,)
	-$(PHP) bin/console --ansi doctrine:database:drop --if-exists --force

db-migrate: ## Run migrations
	$(call main_title,)
	$(PHP) bin/console --ansi doctrine:migrations:migrate --no-interaction --allow-no-migration -vvv

gen-migration: ## Generate migrations
	$(call main_title,)
	$(PHP) bin/console --ansi doctrine:migrations:diff -vvv

fixtures: ## Play fixtures (database will be purged)
	$(call main_title,)
	$(SF_CONSOLE) doctrine:fixtures:load --no-interaction

fixtures-append: ## Play fixtures in append mode (no database purged)
	$(call main_title,)
	$(SF_CONSOLE) doctrine:fixtures:load --append

import-fake-wordpress-data: ## Import fake Wordpress data
	$(call main_title,)
	@echo Importing '$(FAKE_WORDPRESS_DB)'
	@$(DOCKER) cp ./var/fixtures/$(FAKE_WORDPRESS_DB) $(COMPOSE_PROJECT_NAME)-database_1:/tmp
	@$(EXEC_IN_DATABASE) bash -c "mysql -u ${DB_USER} -p${DB_PASSWORD} ${DB_DATABASE} < /tmp/$(FAKE_WORDPRESS_DB)"
	@echo done

vhosts: ## Add required lines to /etc/hosts file
	$(call main_title,)
	-@if [ $(shell cat /etc/hosts | grep $(COMPOSE_PROJECT_NAME).local -c) -ne 0 ]; then \
		echo "Hosts already set."; \
	else \
		echo -ne "Updating hosts file"; \
		CUR_ID="$(shell id -u)"; \
		HOSTS_CMD="echo '127.0.0.1    $(VIRTUAL_HOST) $(PMA_VIRTUAL_HOST)' >> /etc/hosts"; \
		if [ $$CUR_ID = "0" ]; then \
			echo " (as root)"; \
			sh -e -c "$$HOSTS_CMD" ;\
		else \
			echo " (with sudo)"; \
			(sudo -- sh -e -c "$$HOSTS_CMD"); \
    	fi; \
		echo $$HOSTS_CMD; \
	fi;

uid:
	@CUR_ID="$(shell id -u)"; \
	echo "CUR_ID: "$$CUR_ID;
.PHONY: uid

add-cronjobs: ## Add cronjobs
	$(EXEC_IN_APP) sh -c "crontab -u www-data - < /app/bin/cronjobs"

remove-cronjobs: ## Add cronjobs
	-$(EXEC_IN_APP) crontab -u www-data -r

##@ Tests

.PHONY: tests
tests: ## Launch a set of tests
tests: php-cs eslint lint validate phpstan

lint: ## Lint Yaml & Twig files
	$(call main_title,)
	$(SF_CONSOLE) --ansi lint:yaml config *.yml --parse-tags
	$(SF_CONSOLE) --ansi lint:twig templates

validate: ## Validate Doctrine Schema & Composer config file
	$(call main_title,)
	# Options disposnibles pour la commande doctrine:schema:validate :
	# --skip-mapping    Skip the mapping validation check
	# --skip-sync       Skip checking if the mapping is in sync with the database
	$(SF_CONSOLE) --ansi doctrine:schema:validate
	$(COMPOSER) validate --strict

phpstan: ## Launch phpstan tests
	$(call main_title,)
	$(PHP) -d memory_limit=-1 vendor/bin/phpstan --ansi analyse --configuration=phpstan.neon --level=7 src

phpunit: ## Launch phpunit tests
	$(call main_title,)
	APP_ENV=test $(EXEC_IN_APP) php -d memory_limit=-1 bin/phpunit

php-cs: ## Launch php-cs without fixing
	$(call main_title,)
	$(RUN_IN_APP) vendor/bin/php-cs-fixer --ansi fix -v --show-progress=estimating-max --diff-format=udiff --dry-run

php-cs-fixer: ## Launch php-cs-fixer
	$(call main_title,)
	$(RUN_IN_APP) vendor/bin/php-cs-fixer --ansi fix -v --show-progress=estimating-max --diff-format=udiff

eslint: ## Launch eslint
	$(call main_title,)
	$(EXEC_IN_APP) ./node_modules/.bin/eslint public/administrator-theme
	@echo "\033[32mSuccess"

eslint-fix: ## Launch eslint --fix
	$(call main_title,)
	$(EXEC_IN_APP) ./node_modules/.bin/eslint public/administrator-theme --fix
	@echo "\033[32mSuccess"

##@ Helpers

.PHONY: help
help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "    \033[36m%-15s\033[0m\t%s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
.DEFAULT_GOAL := help
