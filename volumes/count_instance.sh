#!/bin/bash

# Check if INSTANCE_MANAGER_NAME is provided as a parameter
if [ -z "$1" ]; then
  echo "Usage: $0 <INSTANCE_MANAGER_NAME>"
  exit 1
fi

# Namespace where the InstanceManager resides
NAMESPACE="longhorn-system"

# Name of the InstanceManager resource (passed as a parameter)
INSTANCE_MANAGER_NAME="$1"

# Count instanceEngines
INSTANCE_ENGINES_COUNT=$(kubectl get -n "$NAMESPACE" instancemanagers.longhorn.io "$INSTANCE_MANAGER_NAME" -o jsonpath='{.status.instanceEngines}' | jq length)

# Count instanceReplicas
INSTANCE_REPLICAS_COUNT=$(kubectl get -n "$NAMESPACE" instancemanagers.longhorn.io "$INSTANCE_MANAGER_NAME" -o jsonpath='{.status.instanceReplicas}' | jq length)

# Output the results
echo "Number of instanceEngines: $INSTANCE_ENGINES_COUNT"
echo "Number of instanceReplicas: $INSTANCE_REPLICAS_COUNT"
