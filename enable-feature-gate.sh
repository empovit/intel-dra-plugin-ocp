#!/usr/bin/env bash

oc patch --type merge -p '{"spec":{"featureSet":"TechPreviewNoUpgrade"}}' featuregate cluster