#!/usr/bin/env bash

oc create configmap intel-dgpu-dockerfile-configmap --from-file=dockerfile=intel-dgpu-driver.Dockerfile -n openshift-kmm