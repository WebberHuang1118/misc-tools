#!/bin/bash

# Namespace where BackingImage resources are located
NAMESPACE="longhorn-system"

# Fetch all BackingImage resources in JSON format
BACKING_IMAGES=$(kubectl get backingimage -n $NAMESPACE -o json)

# Loop through each BackingImage and check for discrepancies
echo "BackingImages with mismatched diskFile entries:"
echo "------------------------------------------------"

echo "$BACKING_IMAGES" | jq -r '.items[] | @base64' | while read -r item; do
    # Decode each BackingImage resource
    BACKING_IMAGE=$(echo "$item" | base64 --decode)
    
    # Extract the BackingImage name
    NAME=$(echo "$BACKING_IMAGE" | jq -r '.metadata.name')

    # Extract spec.diskFileSpecMap keys
    SPEC_DISK_KEYS=$(echo "$BACKING_IMAGE" | jq -r '.spec.diskFileSpecMap | keys_unsorted[]' 2>/dev/null)

    # Extract status.diskFileStatusMap keys
    STATUS_DISK_KEYS=$(echo "$BACKING_IMAGE" | jq -r '.status.diskFileStatusMap | keys_unsorted[]' 2>/dev/null)

    # Convert to arrays
    SPEC_ARRAY=($SPEC_DISK_KEYS)
    STATUS_ARRAY=($STATUS_DISK_KEYS)

    # Find entries in status but not in spec
    MISSING_ENTRIES=()
    for status_key in "${STATUS_ARRAY[@]}"; do
        if [[ ! " ${SPEC_ARRAY[@]} " =~ " ${status_key} " ]]; then
            MISSING_ENTRIES+=("$status_key")
        fi
    done

    # If there are missing entries, print the results
    if [[ ${#MISSING_ENTRIES[@]} -gt 0 ]]; then
        echo "BackingImage: $NAME"
        for entry in "${MISSING_ENTRIES[@]}"; do
            echo "  - Disk entry '$entry' appears in status.diskFileStatusMap but is missing in spec.diskFileSpecMap"
        done
        echo "------------------------------------------------"
    fi
done
