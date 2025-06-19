#!/bin/bash

# Usage: ./export-to-yaml.sh <resource> <name>

RESOURCE=$1
NAME=$2

if [[ -z "$RESOURCE" || -z "$NAME" ]]; then
  echo "Usage: $0 <resource> <name>"
  exit 1
fi

oc get "$RESOURCE" "$NAME" -o yaml | \
  yq eval 'del(
    .metadata.annotations,
    .metadata.creationTimestamp,
    .metadata.namespace,
    .metadata.finalizers,
    .metadata.resourceVersion,
    .metadata.uid,
    .metadata.managedFields,
    .metadata.labels,
    .metadata.ownerReferences,
    .status
  )' -
