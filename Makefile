SHELL_OUT = $(shell fido2-token -L|cut -f1 -d:)

# make build BASE_IMAGE=fedora:latest TAG=latest
build:
	/bin/bash -c "src/build.sh"

# make build REGISTRY=quay.io/account TAG=latest
push:
	/bin/bash -c "src/push.sh"

up:
	export HIDRAW=$(SHELL_OUT) && docker-compose up --detach ${LIMIT}

up-passkey:
	export HIDRAW=$(shell fido2-token -L|cut -f1 -d:) \
	&& docker-compose -f docker-compose.yml -f docker-compose.passkey.yml up \
	--no-recreate --detach ${LIMIT}

up-keycloak:
	docker-compose -f docker-compose.yml -f docker-compose.keycloak.yml up \
	--no-recreate --detach ${LIMIT}

stop:
	docker-compose stop

down:
	docker-compose -f docker-compose.yml \
	-f docker-compose.keycloak.yml \
	-f docker-compose.passkey.yml down

update:
	docker-compose pull

trust-ca:
	/bin/bash -c "src/tools/trust-ca.sh"

setup-dns:
	/bin/bash -c "src/tools/setup-dns.sh"

setup-dns-files:
	/bin/bash -c "src/tools/setup-dns-files.sh"

passkey:
	export ANSIBLE_HOST_KEY_CHECKING=False && \
	ansible-playbook -i src/ansible/passkey/inventory.yml \
	--user root --ask-pass src/ansible/passkey/playbook.yml
