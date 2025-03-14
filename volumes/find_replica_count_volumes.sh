#!/bin/bash
# Usage: ./script.sh <desired_replica_count>
# Example: ./script.sh 2

if [ $# -lt 1 ]; then
    echo "Usage: $0 <desired_replica_count>"
    exit 1
fi

DESIRED_REPLICA_COUNT=$1
NAMESPACE="longhorn-system"

echo "Finding volumes with exactly $DESIRED_REPLICA_COUNT replicas (filtered by replica name prefix matching the volume name) in namespace $NAMESPACE..."

# Get all volumes in the namespace as JSON.
volumes=$(kubectl get volume -n "$NAMESPACE" -o json)

# Iterate over each volume.
echo "$volumes" | jq -r '.items[].metadata.name' | while read -r vol; do
    # Fetch replicas for the volume via label and filter by name prefix.
    replica_json=$(kubectl get replica -n "$NAMESPACE" -l longhornvolume="$vol" -o json)
    replica_count=$(echo "$replica_json" | jq '[.items[] | select(.metadata.name | startswith("'"$vol"'"))] | length')
    
    if [ "$replica_count" -eq "$DESIRED_REPLICA_COUNT" ]; then
        echo "---------------------------------------"
        echo "Volume: $vol"
        
        # Retrieve volume's spec.nodeID, status.state, and status.robustness.
        vol_node=$(kubectl get volume "$vol" -n "$NAMESPACE" -o jsonpath='{.spec.nodeID}')
        vol_state=$(kubectl get volume "$vol" -n "$NAMESPACE" -o jsonpath='{.status.state}')
        vol_robust=$(kubectl get volume "$vol" -n "$NAMESPACE" -o jsonpath='{.status.robustness}')
        echo "  spec.nodeID: $vol_node"
        echo "  status.state: $vol_state"
        echo "  status.robustness: $vol_robust"
        
        echo "  Replicas:"
        # Print header with adjusted column widths.
        printf "    %-60s %-20s %-20s\n" "Replica Name:" "Replica spec.nodeID:" "Replica status.currentState:"
        
        # Extract each matching replica's details, using "N/A" for missing values.
        echo "$replica_json" | jq -r --arg vol "$vol" \
          ' .items[] | select(.metadata.name | startswith($vol)) |
            [ (.metadata.name // "N/A"),
              (.spec.nodeID // "N/A"),
              (.status.currentState // "N/A") ] | @tsv' \
          | while IFS=$'\t' read -r r_name r_node r_state; do
                printf "    %-60s %-20s %-20s\n" "$r_name" "$r_node" "$r_state"
          done
        echo ""
    fi
done

echo "---------------------------------------"
