# DRA feature gate

For DRA, enable the DRA feature gate either when installing the cluster, or by running:

```console
oc patch --type merge -p '{"spec":{"featureSet":"TechPreviewNoUpgrade"}}' featuregate cluster
```

or

```console
oc apply -f dra-feature-gate.yml
```

# Setting up OpenShift cluster for Intel products

Reference: [Intel® Technology Enabling for OpenShift](https://github.com/intel/intel-technology-enabling-for-openshift).

1. Install the NFD Operator:

    ```
    oc apply -f nfd-operator.yml
    ```

2. Run node feature discovery for Intel products:

    ```console
    oc apply -f https://raw.githubusercontent.com/intel/intel-technology-enabling-for-openshift/main/nfd/node-feature-discovery-openshift.yaml
    ```

    and

    ```console
    oc apply -f https://raw.githubusercontent.com/intel/intel-technology-enabling-for-openshift/main/nfd/node-feature-rules-openshift.yaml
    ```

3. Verify the feature discovery:

    ```console
    oc describe node | grep 'intel.feature.node.kubernetes.io/gpu'
    ```

4. Install the KMM Operator:

    ```console
    oc apply -f kmm-operator.yml
    ```

# Intel GPU drivers

Reference:
- [Intel® Data Center GPU Driver for OpenShift](https://github.com/intel/intel-data-center-gpu-driver-for-openshift)
- [Intel® Graphics Driver Backports for Linux® OS (intel-gpu-i915-backports)](https://github.com/intel-gpu/intel-gpu-i915-backports)
- [Intel® GPU firmware](https://github.com/intel-gpu/intel-gpu-firmware)
- [Kernel Module Management (KMM) Operator](https://docs.openshift.com/container-platform/4.16/hardware_enablement/kmm-kernel-module-management.html)

**Important**: It's unlikely that there will be a [pre-build image](https://github.com/intel/intel-technology-enabling-for-openshift/tree/main/kmmo#deploy-intel-data-center-gpu-driver-with-pre-build-mode) available for a recent version of OpenShift,
so we're going to use the on-premise mode.

1. Check which branch/tag has support for your operating system and kernel:
[Active LTS/Production releases](https://github.com/intel-gpu/intel-gpu-i915-backports?tab=readme-ov-file#active-ltsproduction-releases).
E.g. `I915_24WW30.4_803.75_23.10.54_231129.55`.

2. (Optional) Select a [firmware release](https://github.com/intel-gpu/intel-gpu-firmware/tags).

3. Update [#intel-dgpu-driver.Dockerfile]. The file is based on the
[upstream Dockerfile](https://github.com/intel/intel-data-center-gpu-driver-for-openshift/blob/main/docker/intel-dgpu-driver.Dockerfile),
but includes some modifications due to changes in the driver backports.

**Note**: You can try to build the image [outside the cluster](#building-a-driver-image-outside-an-openshift-cluster).

4. Create a configmap from the Dockerfile:

```console
oc create configmap intel-dgpu-dockerfile-configmap --from-file=intel-dgpu-driver.Dockerfile -n openshift-kmm
```

5. Set the firmware path to `/var/lib/firmware`:

```
./update-firmware-path.sh
```

It will patch the KMM configmap and restart the pods.

**Note**: This will not be required anymore with the KMM Operator version 2.2.

5. Make sure the [OpenShift image registry](https://docs.openshift.com/container-platform/4.16/registry/configuring_registry_storage/configuring-registry-storage-baremetal.html) is enabled and working properly.

6. Create a KMM module for on-premise builds:

```
oc apply -f https://raw.githubusercontent.com/intel/intel-technology-enabling-for-openshift/main/kmmo/intel-dgpu-on-premise-build.yaml
```

## Building a driver image outside an OpenShift cluster

1. Find out the right Driver Toolkit Image (DTK). Use your OCP release version and architecture:

```console
export DTK_IMAGE=$(oc adm release info -a $HOME/pull-secret.txt --image-for=driver-toolkit quay.io/openshift-release-dev/ocp-release:4.16.4-x86_64)
```

2. Determine the RHEL and kernel versions that correspond to the OpenShift/DTK version:

```console
export RHEL_VERSION=$(podman run --authfile $HOME/pull-secret.txt --rm -ti ${DTK_IMAGE} cat /etc/driver-toolkit-release.json | jq -r '.RHEL_VERSION')
export RHEL_MAJOR=$(echo "${RHEL_VERSION}" | cut -d '.' -f 1)
export KERNEL_VERSION=$(podman run --authfile $HOME/pull-secret.txt --rm -ti ${DTK_IMAGE} cat /etc/driver-toolkit-release.json | jq -r '.KERNEL_VERSION')
```

3. Run the build:

```
podman build \
    --build-arg DTK_AUTO=${DTK_IMAGE} \
    --build-arg I915_RELEASE=I915_24WW30.4_803.75_23.10.54_231129.55 \
    --build-arg FIRMWARE_RELEASE=24WW20.5_881.12 \
    --build-arg RHEL_VERSION=${RHEL_VERSION} \
    --build-arg RHEL_MAJOR=${RHEL_MAJOR} \
    --build-arg KERNEL_FULL_VERSION=${KERNEL_VERSION} \
    -t intel-dgpu-driver:latest \
    -f intel-dgpu-driver.Dockerfile
```

## Useful commands

- List KMM custom resources:

    ```console
    for r in $(oc api-resources --verbs=list -o name | grep kmm); do oc get $r -A; done
    ```

- Delete KMM pods and get them re-created:

    ```console
    oc delete pods -n openshift-kmm -l app.kubernetes.io/component=kmm
    ```
