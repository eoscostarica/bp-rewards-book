ifneq ("$(wildcard .env)","")
  include .env
  export $(shell sed 's/=.*//' .env)
endif

export VERSION=$(shell git rev-parse --short HEAD)
export IMAGE_NAME_HAPI=bp-rewards-book-hapi
export IMAGE_NAME_HASURA=bp-rewards-book-hasura

SHELL := /bin/bash
BLUE   := $(shell tput -Txterm setaf 6)
RESET  := $(shell tput -Txterm sgr0)

K8S_BUILD_DIR ?= ./.build_k8s
K8S_FILES := $(shell find ./kubernetes -name '*.yaml' | sed 's:./kubernetes/::g')

run:
	make -B postgres
	make -B hapi
	make -B hasura
	make -B -j 3 hapi-logs hasura-cli

postgres:
	@docker-compose stop postgres
	@docker-compose up -d --build postgres
	@echo "done postgres"

hapi:
	@docker-compose stop hapi
	@docker-compose up -d --build hapi
	@echo "done hapi"

hapi-logs:
	@docker-compose logs -f hapi

hasura:
	$(eval -include .env)
	@until \
		docker-compose exec -T postgres pg_isready; \
		do echo "$(BLUE)hasura |$(RESET) waiting for postgres service"; \
		sleep 5; done;
	@until \
		curl -s -o /dev/null -w 'hapi status %{http_code}\n' http://localhost:9090/healthz; \
		do echo "$(BLUE)hasura |$(RESET) waiting for hapi service"; \
		sleep 5; done;
	@docker-compose stop hasura
	@docker-compose up -d --build hasura
	@echo "done hasura"

hasura-cli:
	$(eval -include .env)
	@until \
		curl -s -o /dev/null -w 'hasura status %{http_code}\n' http://localhost:8080/healthz; \
		do echo "$(BLUE)hasura |$(RESET) waiting for hasura service"; \
		sleep 5; done;
	@cd hasura && hasura seeds apply --admin-secret $(HASURA_GRAPHQL_ADMIN_SECRET) && echo "success!" || echo "failure!";
	@cd hasura && hasura console --endpoint http://localhost:8080 --skip-update-check --no-browser --admin-secret $(HASURA_GRAPHQL_ADMIN_SECRET);

stop:
	@docker-compose stop

clean:
	@docker-compose stop
	@rm -rf tmp/postgres
	@rm -rf tmp/hapi
	@rm -rf tmp/webapp
	@docker system prune

build-docker-images:
	@docker pull $(DOCKER_HUB_USER)/$(IMAGE_NAME_NUXT):latest || true
	@docker build -f Dockerfile.Nuxt . \
		-t $(DOCKER_HUB_USER)/$(IMAGE_NAME_NUXT):$(VERSION) \
		-t $(DOCKER_HUB_USER)/$(IMAGE_NAME_NUXT):latest \
		--cache-from $(DOCKER_HUB_USER)/$(IMAGE_NAME_NUXT):latest \
		--build-arg network="$(NETWORK)" \
		--build-arg protocol="$(PROTOCOL)"
	@docker pull $(DOCKER_HUB_USER)/$(IMAGE_NAME_PROXY):latest || true
	@docker build -f Dockerfile.Proxy . \
		-t $(DOCKER_HUB_USER)/$(IMAGE_NAME_PROXY):$(VERSION) \
		-t $(DOCKER_HUB_USER)/$(IMAGE_NAME_PROXY):latest \
		--cache-from $(DOCKER_HUB_USER)/$(IMAGE_NAME_PROXY):latest \
		--build-arg proxy_host="$(PROXY_HOST)"

push-docker-images:
	@echo $(DOCKER_HUB_PASSWORD) | docker login \
		--username $(DOCKER_HUB_USER) \
		--password-stdin
	@docker push $(DOCKER_HUB_USER)/$(IMAGE_NAME_NUXT):$(VERSION)
	@docker push $(DOCKER_HUB_USER)/$(IMAGE_NAME_NUXT):latest
	@docker push $(DOCKER_HUB_USER)/$(IMAGE_NAME_PROXY):$(VERSION)
	@docker push $(DOCKER_HUB_USER)/$(IMAGE_NAME_PROXY):latest

build-kubernetes-namespace:
	@rm -Rf $(K8S_BUILD_DIR) && mkdir -p $(K8S_BUILD_DIR)
	@for file in $(K8S_FILES); do \
		mkdir -p `dirname "$(K8S_BUILD_DIR)/$$file"`; \
		$(SHELL_EXPORT) envsubst <./kubernetes/$$file >$(K8S_BUILD_DIR)/$$file; \
	done

push-kubernetes-namespace:
	@kubectl create ns $(NAMESPACE) || echo "namespace '$(NAMESPACE)' already exists.";
	@echo "Creating SSL certificates..."
	@kubectl create secret tls \
		tls-secret \
		--key ./ssl/eosio.cr.priv.key \
		--cert ./ssl/eosio.cr.crt \
		-n $(NAMESPACE)  || echo "SSL cert already configured.";
	@echo "Creating configmaps..."
	@kubectl create configmap -n $(NAMESPACE) \
	wallet-config \
	--from-file wallet/config/ || echo "Wallet configuration already created.";
	@echo "Applying kubernetes files..."
	@for file in $(shell find $(K8S_BUILD_DIR) -name '*.yaml' | sed 's:$(K8S_BUILD_DIR)/::g'); do \
		kubectl apply -f $(K8S_BUILD_DIR)/$$file -n $(NAMESPACE) || echo "${file} Cannot be updated."; \
	done

deploy:
	@echo "started at: $$(date +%Y-%m-%d:%H:%M:%S)"
	make build-docker-images
	make push-docker-images
	make build-kubernetes-namespace
	make push-kubernetes-namespace
	@echo "completed at: $$(date +%Y-%m-%d:%H:%M:%S)"