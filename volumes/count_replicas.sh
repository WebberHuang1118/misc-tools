#!/bin/bash

# Check if a node name is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <node-name>"
  exit 1
fi

# Assign the first argument to NODE_NAME
NODE_NAME="$1"

# Get the Longhorn node resource
kubectl -n longhorn-system get nodes.longhorn.io "$NODE_NAME" -o json | jq -r '
.status.diskStatus |
to_entries |
map("\(.key): \(.value.scheduledReplica | length)") |
.[]'
