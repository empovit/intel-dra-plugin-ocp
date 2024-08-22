# Copyright (c) 2023 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Intel Data Center GPU driver components combinations.
ARG I915_RELEASE=I915_24WW30.4_803.75_23.10.54_231129.55
ARG FIRMWARE_RELEASE=24WW20.5_881.12

# Intel Data Center GPU Driver for OpenShift version.
ARG DRIVER_VERSION=2.2.0

# RHCOS Kernel version supported by the above driver version.
ARG KERNEL_FULL_VERSION

# Red Hat DTK image is used as builder image to build kernel driver modules.
# Appropriate DTK image is provided with the OCP release, to guarantee compatibility
# between the built kernel modules and the OCP version's RHCOS kernel.
# DTK_AUTO is populated automatically with the appropriate DTK image by KMM operator.
ARG DTK_AUTO

ARG RHEL_VERSION=9.4
ARG RHEL_MAJOR=9

FROM ${DTK_AUTO} as builder

ARG I915_RELEASE
ARG FIRMWARE_RELEASE
ARG KERNEL_FULL_VERSION

ARG RHEL_MAJOR
ARG RHEL_VERSION

WORKDIR /build

# Building i915 driver
RUN git clone -b ${I915_RELEASE} --single-branch https://github.com/intel-gpu/intel-gpu-i915-backports.git \
    && cd intel-gpu-i915-backports \
    && install -D COPYING /licenses/i915/COPYING \
    && export LEX=flex; export YACC=bison \
    && export OS_TYPE=rhel_${RHEL_MAJOR} && export RHEL_VERSION=${RHEL_VERSION} \
    && export KLIB=/lib/modules/${KERNEL_FULL_VERSION} \
    && export KLIB_BUILD=/lib/modules/${KERNEL_FULL_VERSION}/build \
    && cp defconfigs/i915 .config \
    && make olddefconfig && make modules -j $(nproc) && make modules_install

# Copy out-of-tree drivers to /opt/lib/modules/${KERNEL_FULL_VERSION}/
RUN for file in $(find /lib/modules/${KERNEL_FULL_VERSION}/updates/ -name "*.ko"); do \
    cp $file /opt --parents; done

# Create the symbolic link for in-tree dependencies
RUN ln -s /lib/modules/${KERNEL_FULL_VERSION} /opt/lib/modules/${KERNEL_FULL_VERSION}/host

RUN depmod -b /opt ${KERNEL_FULL_VERSION}

# Firmware
RUN git clone -b ${FIRMWARE_RELEASE} --single-branch https://github.com/intel-gpu/intel-gpu-firmware.git \
    && install -D /build/intel-gpu-firmware/COPYRIGHT /licenses/firmware/COPYRIGHT \
    && install -D /build/intel-gpu-firmware/COPYRIGHT /build/firmware/license/COPYRIGHT \
    && install -D /build/intel-gpu-firmware/firmware/dg2* /build/firmware/ \
    && install -D /build/intel-gpu-firmware/firmware/pvc* /build/firmware/

# Packaging Intel GPU driver components in the base UBI image for certification
FROM registry.redhat.io/ubi${RHEL_MAJOR}/ubi-minimal:${RHEL_VERSION}
ARG DRIVER_VERSION
ARG KERNEL_FULL_VERSION
ARG I915_RELEASE
ARG FIRMWARE_RELEASE

# Required labels for the image metadata
LABEL vendor="Intel®"
LABEL version="${DRIVER_VERSION}"
LABEL release="${KERNEL_FULL_VERSION}"
LABEL name="intel-data-center-gpu-driver-container"
LABEL summary="Intel® Data Center GPU Driver Container Image"
LABEL description="Intel® Data Center GPU Driver container image designed for Red Hat OpenShift Container Platform. \
The driver container is based on Intel Data Center GPU driver components - i915 driver release:${I915_RELEASE}, \
and Firmware release:${FIRMWARE_RELEASE}. This driver container image is supported for RHOCP 4.14 RHCOS kernel version: ${KERNEL_FULL_VERSION}."

RUN microdnf update -y && rm -rf /var/cache/yum
RUN microdnf -y install kmod findutils && microdnf clean all
COPY --from=builder /licenses/ /licenses/
COPY --from=builder /opt/lib/modules/${KERNEL_FULL_VERSION}/ /opt/lib/modules/${KERNEL_FULL_VERSION}/
COPY --from=builder /build/firmware/ /firmware/i915/