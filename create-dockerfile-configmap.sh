#!/usr/bin/env bash

oc delete configmap intel-dgpu-dockerfile-configmap -n openshift-kmm --ignore-not-found
oc create configmap intel-dgpu-dockerfile-configmap -n openshift-kmm --from-file=dockerfile=intel-dgpu-driver.Dockerfile