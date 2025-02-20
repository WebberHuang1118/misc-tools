#!/bin/bash

# Check if the user provided an instanceManagerName
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <instanceManagerName>"
  exit 1
fi

# Get the instanceManagerName from the command-line argument
INSTANCE_MANAGER_NAME="$1"

# Set the namespace
NAMESPACE="longhorn-system"

# Fetch and filter replicas
echo "Fetching replicas with instanceManagerName: $INSTANCE_MANAGER_NAME"
kubectl get replicas -n "$NAMESPACE" -o json | \
jq -r --arg instanceManagerName "$INSTANCE_MANAGER_NAME" '.items[] | select(.status.instanceManagerName == $instanceManagerName) | .metadata.name'

# Check if the command succeeded
if [ $? -ne 0 ]; then
  echo "Failed to fetch replicas. Ensure kubectl and jq are installed and configured correctly."
  exit 1
fi
