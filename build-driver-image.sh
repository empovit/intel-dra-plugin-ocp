#!/bin/sh

set -e
set -o pipefail

export TARGET_ARCH=x86_64
export IMAGE_REGISTRY=quay.io/vemporop/intel-data-center-gpu-driver-container
export IMAGE_VERSION=1.1.0

ocp_version=$(oc version | grep 'Server Version' | awk -F': ' '{print $2}')
echo "OCP version: $ocp_version"

export DTK_AUTO=$(oc adm release info -a $HOME/pull-secret.txt --image-for=driver-toolkit quay.io/openshift-release-dev/ocp-release:${ocp_version}-${TARGET_ARCH})
echo "DTK image: $DTK_AUTO"

export KERNEL_VERSION=$(podman run --authfile $HOME/pull-secret.txt --rm -ti ${DTK_AUTO} cat /etc/driver-toolkit-release.json | jq -r '.KERNEL_VERSION')
echo "Kernel version: $KERNEL_VERSION"

export RHEL_VERSION=$(podman run --authfile $HOME/pull-secret.txt --rm -ti ${DTK_IMAGE} cat /etc/driver-toolkit-release.json | jq -r '.RHEL_VERSION')
echo "RHEL version: ${RHEL_VERSION}"

export RHEL_MAJOR=$(echo "${RHEL_VERSION}" | cut -d '.' -f 1)
echo "RHEL major version: ${RHEL_MAJOR}"

# cd ../intel-data-center-gpu-driver-for-openshift/docker

export IMAGE_NAME=${IMAGE_REGISTRY}:${IMAGE_VERSION}-${KERNEL_VERSION}

podman build \
    --build-arg KERNEL_FULL_VERSION=$KERNEL_VERSION \
    --build-arg DTK_AUTO=$DTK_AUTO \
    --build-arg RHEL_VERSION=$RHEL_VERSION \
    --build-arg RHEL_MAJOR=$RHEL_MAJOR \
    --build-arg I915_RELEASE=I915_24WW30.4_803.75_23.10.54_231129.55 \
    --build-arg FIRMWARE_RELEASE=24WW20.5_881.12 \
    -t $IMAGE_NAME -f intel-dgpu-driver.Dockerfile
podman push $IMAGE_NAME