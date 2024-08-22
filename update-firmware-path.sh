#!/usr/bin/env bash

set -e

modified_value=$(oc get configmap -n openshift-kmm kmm-operator-manager-config -o "jsonpath={.data['controller_config\.yaml']}" | yq -y '.worker += {"setFirmwareClassPath": "/var/lib/firmware"}' | sed -z 's/\n/\\n/g')
oc patch configmap kmm-operator-manager-config -n openshift-kmm --type=merge -p="{\"data\": {\"controller_config.yaml\":\"${modified_value}\"}}"