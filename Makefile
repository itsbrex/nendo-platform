.PHONY: init setup setup-cpu all flush build build-dev server-build web-build web-build-dev server-logs web-logs server-shell web-shell run run-dev run-cpu update-dependencies set-password invite-codes

all: help

docker_gid := $(shell grep docker /etc/group | cut -d: -f3 | if [ -z '$$(cat)' ]; then echo 999; else cat; fi)
uid := $(shell id -u)
gid := $(shell id -g)
@:$(eval USE_SSL=$(or $(USE_SSL),false))
@:$(eval SERVER_URL=$(or $(SERVER_URL),http://localhost))

init:
	cd ./scripts/ && ./init_local_dev.sh && cd ..

setup: init build-dev build-tools-gpu

setup-cpu: init build-dev build-tools-cpu

flush:
	@/bin/bash -c 'read -p "Are you sure you want to delete all rows from the specified tables? [y/N] " confirm; \
	if [[ $$confirm == [yY] ]]; then \
		docker exec -i nendo-postgres psql -U nendo -d nendo -c "BEGIN; DELETE FROM embeddings; DELETE FROM collection_collection_relationships; DELETE FROM track_track_relationships; DELETE FROM track_collection_relationships; DELETE FROM plugin_data; DELETE FROM scenes; DELETE FROM collections; DELETE FROM tracks; COMMIT;"; \
		rm -rf library/*/*; \
	fi'

build-dev: server-build-dev web-build-dev

build: server-build web-build

server-build-dev:
	HOST_CWD=$(shell pwd) docker compose --profile dev build server-dev --build-arg UID=$(uid) --build-arg GID=$(gid) --build-arg DOCKER_GID=$(docker_gid)

server-build:
	HOST_CWD=$(shell pwd) docker compose --profile prod build server --build-arg UID=$(uid) --build-arg GID=$(gid) --build-arg DOCKER_GID=$(docker_gid)

web-build-dev:
	@echo Building with SERVER_URL=$(SERVER_URL)
	@HOST_CWD=$(shell pwd) docker compose --profile dev build --build-arg SERVER_URL=$(SERVER_URL) web-dev

web-build:
	@echo Building with SERVER_URL=$(SERVER_URL)
	@HOST_CWD=$(shell pwd) docker compose --profile prod build --build-arg SERVER_URL=$(SERVER_URL) web

build-tools-cpu:
	cd build/core/3.8-cpu && docker build --no-cache --build-arg UID=$(uid) --build-arg GID=$(gid) -t nendo/core:3.8 .
	cd build/voiceanalysis/cpu && docker build -t nendo/voiceanalysis .
	cd build/polymath && docker build -t nendo/polymath .
	cd build/quantize && docker build -t nendo/quantize .

build-tools-gpu:
	cd build/core/3.8-gpu && docker build --no-cache --build-arg UID=$(uid) --build-arg GID=$(gid) -t nendo/core:3.8 .
	cd build/musicanalysis && docker build -t nendo/musicanalysis .
	cd build/voiceanalysis/gpu && docker build -t nendo/voiceanalysis .
	cd build/voicegen && docker build -t nendo/voicegen .
	cd build/musicgen && docker build -t nendo/musicgen .
	cd build/polymath && docker build -t nendo/polymath .
	cd build/quantize && docker build -t nendo/quantize .

server-logs:
	docker logs nendo-server

web-logs:
	docker logs nendo-web

server-shell:
	docker exec -it nendo-server /bin/bash 

web-shell:
	docker exec -it nendo-web /bin/bash

run-dev:
	@echo Running with HOST_CWD=$(shell pwd), USE_GPU=$(USE_GPU)
	@if [ -z "$$(docker images -q nendo-server)" ] || [ -z "$$(docker images -q nendo-web)" ]; then \
        echo "One or both images not found. Running setup..."; \
        $(MAKE) setup; \
    else \
        echo "Both images found. Running application..."; \
    fi
	@HOST_CWD=$(shell pwd) docker compose --profile dev down
	@HOST_CWD=$(shell pwd) docker compose --profile dev up

run-cpu:
	@echo Running with HOST_CWD=$(shell pwd), USE_GPU=false
	@if [ -z "$$(docker images -q nendo-server)" ] || [ -z "$$(docker images -q nendo-web)" ]; then \
        echo "One or both images not found. Running setup..."; \
        $(MAKE) setup-cpu; \
    else \
        echo "Both images found. Running application..."; \
    fi
	@HOST_CWD=$(shell pwd) USE_GPU=false docker compose --profile dev down
	@HOST_CWD=$(shell pwd) USE_GPU=false docker compose --profile dev up

run:
	@echo Running with HOST_CWD=$(shell pwd)
	@if [ -z "$$(docker images -q nendo-server)" ] || [ -z "$$(docker images -q nendo-web)" ]; then \
        echo "One or both images not found. Running setup..."; \
        $(MAKE) setup; \
    else \
        echo "Both images found. Running application..."; \
    fi
	@if [ "$(USE_SSL)" = "false" ]; then \
		echo "Running insecure mode (no SSL)"; \
		PROFILE=prod-http; \
	else \
		echo "Running with SSL"; \
		PROFILE=prod; \
	fi; \
	HOST_CWD=$(shell pwd) docker compose --profile $$PROFILE down; \
	HOST_CWD=$(shell pwd) docker compose --profile $$PROFILE up -d

update-dependencies:
	git pull
	cd repo/nendo-server && git pull
	cd repo/nendo-web && git pull

set-password:
	$(if $(NEW_PASSWORD),,@echo "NEW_PASSWORD is not set. Use 'make set-password NEW_PASSWORD=mynewpassword' to set it." && exit 1)
	@docker cp ./scripts/changepw.py nendo-server:/home/nendo && docker exec nendo-server python /home/nendo/changepw.py $(NEW_PASSWORD) > /dev/null 2>&1
	@docker exec nendo-server rm /home/nendo/changepw.py

invite-codes:
	@docker cp scripts/invcodes.sql nendo-postgres:/root
	@docker exec nendo-postgres psql -U nendo -d nendo -f /root/invcodes.sql
	@docker exec nendo-postgres psql -U nendo -d nendo -c 'SELECT * FROM user_invite_code'

help:
	@echo '==================='
	@echo '-- DOCUMENTATION --'
	@echo 'init                   - initialize the environment (clone repos)'
	@echo 'setup                  - prepare the development environment'
	@echo 'setup-cpu              - prepare the development environment (CPU-only)'
	@echo 'flush                  - flush the database and delete all files in the default user library'
	@echo 'build                  - build all images'
	@echo 'build-dev              - build all images for development'
	@echo 'server-build           - build nendo-server'
	@echo 'server-build-dev       - build nendo-server in development mode'
	@echo 'server-logs            - get the docker logs for nendo-server'
	@echo 'server-shell           - get a shell into nendo-server'
	@echo 'web-build              - build nendo-web'
	@echo 'web-build-dev          - build nendo-web in development mode'
	@echo 'web-logs               - get the docker logs for nendo-web'
	@echo 'web-shell              - get a shell into nendo-web'
	@echo 'build-tools-cpu        - build nendo tools (CPU-only)'
	@echo 'build-tools-gpu        - build nendo tools (GPU enabled)'
	@echo 'run                    - run Nendo Platform'
	@echo 'run-dev                - run Nendo Platform in development mode with hot-reloading'
	@echo 'run-cpu                - run Nendo Platform in development mode with hot-reloading (CPU mode)'
	@echo 'set-password           - set a new password for the default nendo user'
	@echo 'update-dependencies    - update development dependencies'
	@echo '==================='