#!/bin/bash

#                     ==============
#                      IMAGE LAYERS
#                     ==============
#
#                     original image
# |----------------------------------------------------|
# |                    base-ground                     |
# |----------------------------------------------------|
# |        base-ldap    |  base-client  |  base-samba  |
# |------------------------------------ |--------------|
# |  base-ipa  |        |               |              |
# |------------|        |               |              |
# |    ipa     |  ldap  |    client     |     samba    |
# |            |        |---------------|              |
# |            |        |  client-dev   |              |
# |------------|--------|---------------|--------------|

trap "cleanup &> /dev/null || :" EXIT
pushd $(realpath `dirname "$0"`) &> /dev/null
source ./tools/get-container-engine.sh

export REGISTRY="localhost/sssd"
export BASE_IMAGE="${BASE_IMAGE:-registry.fedoraproject.org/fedora:latest}"
export TAG="${TAG:-latest}"
export UNAVAILABLE="${UNAVAILABLE:-}"
export ANSIBLE_CONFIG=./ansible/ansible.cfg

echo "Building from: $BASE_IMAGE"
echo "Building with tag: $TAG"
echo "Building in priviledged mode: $PRIVILEDGED"
echo "Storing in: $REGISTRY"

set -xe

function cleanup {
  ${DOCKER} rm sssd-wip-base --force
  compose down
}

function compose {
  docker-compose -f "../docker-compose.yml" -f "./docker-compose.build.yml" $@
}

function base_exec {
  ${DOCKER} exec sssd-wip-base /bin/bash -c "$1"
}

# Make sure that python is installed, so we can use ansible.
function base_install_python {
  if base_exec '[ -f /usr/bin/python3 ]'; then
    return 0
  fi

  if base_exec '[ -f /usr/bin/apt ]'; then
    base_exec 'apt update && apt install -y python3 && rm -rf /var/lib/apt/lists/*'
  else
    base_exec 'dnf install -y python3 && dnf clean all'
  fi
}

# We use commit instead of build so we can provision the images with Ansible.
function build_base_image {
  local from=$1
  local name=$2

  for svc in $UNAVAILABLE; do
    if [ "base-$svc" != $name ]; then
      continue
    fi

    echo "Service $svc is not available in $BASE_IMAGE."
    echo "Using quay.io/sssd/ci-base-$svc:latest instead."
    ${DOCKER} pull "quay.io/sssd/ci-base-$svc:latest"
    ${DOCKER} tag "quay.io/sssd/ci-base-$svc:latest" "${REGISTRY}/ci-$name:${TAG}"
    return 0
  done

  echo "Building $name from $from"
  ${DOCKER} run --name sssd-wip-base --detach -i "$from"
  if [ $name == 'base-ground' ]; then
    base_install_python
  fi

  ansible-playbook --limit "$name" ./ansible/playbook_image_base.yml
  ${DOCKER} stop sssd-wip-base
  ${DOCKER} commit                     \
    --change 'CMD ["/sbin/init"]'      \
    --change 'STOPSIGNAL SIGRTMIN+3'   \
    sssd-wip-base "${REGISTRY}/ci-$name:${TAG}"
  ${DOCKER} rm sssd-wip-base --force
}

# We have to use commit because the services require functional systemd.
function build_service_image {
  local from=$1
  local name=$2

  echo "Commiting $from as $name"
  ${DOCKER} commit "$from" "${REGISTRY}/ci-$name:${TAG}"
}

# Create base images
${DOCKER} build --file "Containerfile" --target dns --tag "${REGISTRY}/ci-dns:latest" .
build_base_image "$BASE_IMAGE" base-ground
build_base_image "ci-base-ground:${TAG}" base-client
build_base_image "ci-base-ground:${TAG}" base-ldap
build_base_image "ci-base-ground:${TAG}" base-samba
build_base_image "ci-base-ldap:${TAG}"   base-ipa

# Create services
compose up --detach
ansible-playbook ./ansible/playbook_image_service.yml
compose stop
build_service_image sssd-wip-client client
build_service_image sssd-wip-ipa ipa
build_service_image sssd-wip-ldap ldap
build_service_image sssd-wip-samba samba
compose down

# Create development images with additional packages
build_base_image "ci-client:${TAG}" client-devel
