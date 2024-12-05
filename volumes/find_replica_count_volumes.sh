#!/bin/bash

# Check if a desired replica count is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <desired_replica_count>"
    exit 1
fi

DESIRED_REPLICA_COUNT=$1
NAMESPACE="longhorn-system"

# Get all Longhorn volumes and replicas in JSON format
volumes=$(kubectl get volumes.longhorn.io -n $NAMESPACE -o json)
replicas=$(kubectl get replicas.longhorn.io -n $NAMESPACE -o json)

# Count volumes with the desired replica count
count=$(echo "$volumes" | jq -r '.items[] | .metadata.name' | while read -r volume_name; do
    replica_count=$(echo "$replicas" | jq -r --arg volume_name "$volume_name" '.items[] | select(.spec.volumeName == $volume_name) | .metadata.name' | wc -l)
    if [ "$replica_count" -eq "$DESIRED_REPLICA_COUNT" ]; then
        echo 1
    fi
done | wc -l)

# Output the total count
echo "Total number of volumes with $DESIRED_REPLICA_COUNT replicas: $count"
