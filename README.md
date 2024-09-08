# Intel GPU on OpenShift: out-of-tree drivers, DRA plugin, Kubernetes device plugin

> WARNING: This repository is a work in progress. Things may not work!

## Enabling DRA

Enable the DRA feature gate either when installing the cluster, or post-install:

```console
oc patch --type merge -p '{"spec":{"featureSet":"TechPreviewNoUpgrade"}}' featuregate cluster
```

Enable the DRA scheduler profile:

```console
oc patch --type merge -p '{"spec":{"profile": "HighNodeUtilization", "profileCustomizations": {"dynamicResourceAllocation": "Enabled"}}}' scheduler cluster
```

## Setting up OpenShift cluster for Intel products

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

## Intel GPU drivers

This guide focuses on building and installing out-of-tree drivers for not yet supported GPU models and/or kernel versions.
Check out the list of [supported hardware](https://dgpu-docs.intel.com/devices/hardware-table.html) to see if working
drivers might be already available on the node.

Here is an example of a GPU/kernel unsupported by the installed i915 driver:

```console
$ dmesg | grep -i i915
[    4.246825] i915 0000:06:00.0: Your graphics device 56c0 is not properly supported by i915 in this
               kernel version. To force driver probe anyway, use i915.force_probe=56c0
               module parameter or CONFIG_DRM_I915_FORCE_PROBE=56c0 configuration option,
```

Reference:
- [Intel® Data Center GPU Driver for OpenShift](https://github.com/intel/intel-data-center-gpu-driver-for-openshift)
- [Intel® Graphics Driver Backports for Linux® OS (intel-gpu-i915-backports)](https://github.com/intel-gpu/intel-gpu-i915-backports)
- [Intel® GPU firmware](https://github.com/intel-gpu/intel-gpu-firmware)
- [Kernel Module Management (KMM) Operator](https://docs.openshift.com/container-platform/4.16/hardware_enablement/kmm-kernel-module-management.html)

**Important**: It's unlikely that there will be a [pre-build image](https://github.com/intel/intel-technology-enabling-for-openshift/tree/main/kmmo#deploy-intel-data-center-gpu-driver-with-pre-build-mode) available for a recent version of OpenShift,
so we're going to use the on-premise mode.

1. Check which branch/tag has support for your operating system and kernel:
[Active LTS/Production releases](https://github.com/intel-gpu/intel-gpu-i915-backports?tab=readme-ov-file#active-ltsproduction-releases).
E.g. `I915_24WW30.4_803.75_23.10.54_231129.55`, or `backport/main` for the latest drivers for Red Hat Enterprise Linux.

2. (Optional) Select a [firmware release](https://github.com/intel-gpu/intel-gpu-firmware/tags). You can also use `main`.

3. Update [intel-dgpu-driver.Dockerfile](intel-dgpu-driver.Dockerfile). The file is based on the
[upstream Dockerfile](https://github.com/intel/intel-data-center-gpu-driver-for-openshift/blob/main/docker/intel-dgpu-driver.Dockerfile),
but includes some modifications due to changes in the driver backports.

**Note**: You can try to build the image [outside the cluster](#building-a-driver-image-outside-an-openshift-cluster).

4. Create a configmap from the Dockerfile:

```console
oc create configmap intel-dgpu-dockerfile-configmap --from-file=dockerfile=intel-dgpu-driver.Dockerfile -n openshift-kmm
```

5. Set the firmware path to `/var/lib/firmware`:

```console
./update-firmware-path.sh
```

It will patch the KMM configmap and restart the pods.

**Note**: This will not be required anymore with the KMM Operator version 2.2.

5. Make sure the [OpenShift image registry](https://docs.openshift.com/container-platform/4.16/registry/configuring_registry_storage/configuring-registry-storage-baremetal.html) is enabled and working properly.

6. Label a GPU node for canary deployment:

```console
oc label node <node> intel.feature.node.kubernetes.io/dgpu-canary=true
```

7. Create a KMM module for on-premise builds. It's based on the [upstream module](https://github.com/intel/intel-technology-enabling-for-openshift/blob/main/kmmo/intel-dgpu-on-premise-build.yaml), but will unload any in-tree `i915` module that might not support the GPU model:

```console
oc apply -f intel-dgpu-on-premise-build.yaml
```

8. Wait for the build to finish (there will be a pod in the `openshift-kmm` namespace). Then check the node labels:

```console
oc get nodes -l kmm.node.kubernetes.io/openshift-kmm.intel-dgpu-on-premise-build.ready
```

Note that the label is different with [pre-build mode](https://github.com/intel/intel-technology-enabling-for-openshift/tree/main/kmmo#deploy-intel-data-center-gpu-driver-with-pre-build-mode):

```console
oc get nodes -l kmm.node.kubernetes.io/openshift-kmm.intel-dgpu.ready
```

## Intel DRA Plugin

Reference:
- [Intel resource drivers for Kubernetes](https://github.com/intel/intel-resource-drivers-for-kubernetes)

**Note**: The plugin version supported by OpenShift 4.16 is [0.4.0](https://github.com/intel/intel-resource-drivers-for-kubernetes/tree/v0.4.0).
Later versions use a newer Kubernetes API and will not run on OpenShift.

When installing the plugin, the deployment must be modified to allow the service account to use `hostPath`, which requires privileged access on OpenShift.
A straightforward (although making the service account too powerful) way of doing so is to run the container that uses `hostPath` volumes as privileged:

1. Bind the ClusterRole `system:openshift:scc:privileged` the plugin's service account
([example](https://github.com/empovit/intel-resource-drivers-for-kubernetes/blob/37c73b9a424712eb4a8c1f89d9fed7748260e520/deployments/gpu/openshift-privileged-clusterrolebinding.yaml)).

2. Change the `kubelet-plugin` container's security context in `deployments/gpu/resource-driver.yaml` to `privileged: true`
([example](https://github.com/empovit/intel-resource-drivers-for-kubernetes/blob/37c73b9a424712eb4a8c1f89d9fed7748260e520/deployments/gpu/resource-driver.yaml#L79)).

## Intel Device Plugin Operator

The "classic" Kubernetes device plugin can be used as an alternative to DRA, for instance for verifying the hardware, drivers, and cluster setup.

Reference:
- [Setting up Intel Device Plugins Operator](https://github.com/intel/intel-technology-enabling-for-openshift/blob/main/device_plugins/README.md)
- [Intel Device Plugin for Kubernetes](https://github.com/intel/intel-device-plugins-for-kubernetes)
- [Verify Intel® Data Center GPU provisioning](https://github.com/intel/intel-technology-enabling-for-openshift/blob/main/tests/l2/dgpu/README.md)

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

```console
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
