#!/bin/bash
# Usage: ./find_volume_details.sh <volume_name>
# Example: ./find_volume_details.sh pvc-22da63fa-ed58-47df-bfb0-b8933ea96b8f

if [ $# -lt 1 ]; then
    echo "Usage: $0 <volume_name>"
    exit 1
fi

VOL_NAME=$1
NAMESPACE="longhorn-system"

# Retrieve volume details.
vol_spec_node=$(kubectl get volume "$VOL_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.nodeID}')
vol_state=$(kubectl get volume "$VOL_NAME" -n "$NAMESPACE" -o jsonpath='{.status.state}')
vol_robust=$(kubectl get volume "$VOL_NAME" -n "$NAMESPACE" -o jsonpath='{.status.robustness}')

# Display volume information.
echo "======================================="
printf "Volume: %s\n" "$VOL_NAME"
echo "---------------------------------------"
printf "  %-22s %s\n" "spec.nodeID:" "$vol_spec_node"
printf "  %-22s %s\n" "status.robustness:" "$vol_robust"
printf "  %-22s %s\n" "status.state:" "$vol_state"
echo "======================================="

# Retrieve engine details.
engine_json=$(kubectl get engine -n "$NAMESPACE" -l longhornvolume="$VOL_NAME" -o json)
engine_count=$(echo "$engine_json" | jq '.items | length')

if [ "$engine_count" -gt 0 ]; then
    engine_name=$(echo "$engine_json" | jq -r '.items[0].metadata.name // "N/A"')
    engine_spec_node=$(echo "$engine_json" | jq -r '.items[0].spec.nodeID // "N/A"')
    engine_state=$(echo "$engine_json" | jq -r '.items[0].status.currentState // "N/A"')
    echo "Engine:"
    echo "---------------------------------------"
    printf "  %-22s %s\n" "Name:" "$engine_name"
    printf "  %-22s %s\n" "spec.nodeID:" "$engine_spec_node"
    printf "  %-22s %s\n" "status.currentState:" "$engine_state"
else
    echo "Engine: No engine found for volume $VOL_NAME"
fi
echo "======================================="

# Retrieve replica details.
replica_json=$(kubectl get replica -n "$NAMESPACE" -l longhornvolume="$VOL_NAME" -o json)
replica_count=$(echo "$replica_json" | jq '.items | length')

echo "Replicas:"
echo "---------------------------------------"
if [ "$replica_count" -gt 0 ]; then
    # Print header with fixed-width columns.
    printf "    %-60s %-20s %-20s\n" "Replica Name:" "Replica spec.nodeID:" "Replica status.currentState:"
    echo "$replica_json" | jq -r \
      '.items[] | [ .metadata.name, (.spec.nodeID // "N/A"), (.status.currentState // "N/A") ] | @tsv' \
      | while IFS=$'\t' read -r r_name r_node r_state; do
            printf "    %-60s %-20s %-20s\n" "$r_name" "$r_node" "$r_state"
      done
else
    echo "  No replicas found for volume $VOL_NAME"
fi
echo "======================================="
