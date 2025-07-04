#!/bin/bash
# Usage: ./find_volume_details.sh <volume_name>
# Example: ./find_volume_details.sh pvc-22da63fa-ed58-47df-bfb0-b8933ea96b8f

if [ $# -lt 1 ]; then
    echo "Usage: $0 <volume_name>"
    exit 1
fi

VOL_NAME=$1
NAMESPACE="longhorn-system"

# ----------------------------------------------------------------------------------
# Retrieve VOLUME details.
# ----------------------------------------------------------------------------------
vol_spec_node=$(kubectl get volume "$VOL_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.nodeID}')
vol_state=$(kubectl get volume "$VOL_NAME" -n "$NAMESPACE" -o jsonpath='{.status.state}')
vol_robust=$(kubectl get volume "$VOL_NAME" -n "$NAMESPACE" -o jsonpath='{.status.robustness}')

# ----------------------------------------------------------------------------------
# Retrieve ENGINE details.
# ----------------------------------------------------------------------------------
engine_json=$(kubectl get engine -n "$NAMESPACE" -l longhornvolume="$VOL_NAME" -o json)
engine_count=$(echo "$engine_json" | jq '.items | length')

if [ "$engine_count" -gt 0 ]; then
    engine_name=$(echo "$engine_json" | jq -r '.items[0].metadata.name // "N/A"')
    engine_spec_node=$(echo "$engine_json" | jq -r '.items[0].spec.nodeID // "N/A"')
    engine_state=$(echo "$engine_json" | jq -r '.items[0].status.currentState // "N/A"')
    engine_created=$(echo "$engine_json" | jq -r '.items[0].metadata.creationTimestamp // "N/A"')
    engine_replica_map_json=$(echo "$engine_json" | jq '.items[0].status.currentReplicaAddressMap')
else
    engine_name="N/A"
    engine_spec_node="N/A"
    engine_state="N/A"
    engine_created="N/A"
    engine_replica_map_json="{}"
fi

# ----------------------------------------------------------------------------------
# Retrieve REPLICA details.
# ----------------------------------------------------------------------------------
replica_json=$(kubectl get replica -n "$NAMESPACE" -l longhornvolume="$VOL_NAME" -o json)
replica_count=$(echo "$replica_json" | jq '.items | length')

# ----------------------------------------------------------------------------------
# Print the results in a hierarchical format.
# ----------------------------------------------------------------------------------
echo "================================================================================"
echo "Volume: ${VOL_NAME}"
echo "  spec.nodeID: ${vol_spec_node}"
echo "  status:"
echo "    robustness: ${vol_robust}"
echo "    state: ${vol_state}"

echo ""
echo "  Engine:"
if [ "$engine_count" -gt 0 ]; then
  echo "    name: ${engine_name}"
  echo "    spec.nodeID: ${engine_spec_node}"
  echo "    status:"
  echo "      currentState: ${engine_state}"
  echo "      currentReplicaAddressMap:"
  
  map_count=$(echo "$engine_replica_map_json" | jq 'length')
  if [ "$map_count" -gt 0 ]; then
    echo "$engine_replica_map_json" | jq -r '
      to_entries[] |
      "        - " + .key + ": " + .value
    '
  else
    echo "        No replica address map found"
  fi
  echo "      creationTimestamp: ${engine_created}"
else
  echo "    No engine found for volume ${VOL_NAME}"
fi

echo ""
echo "  Replicas:"
if [ "$replica_count" -gt 0 ]; then
    echo "$replica_json" | \
      jq -r '.items[] | [
          .metadata.name,
          (.status.ip // "N/A"),
          (.status.storageIP // "N/A"),
          (.status.port // "N/A"),
          (.spec.nodeID // "N/A"),
          (.spec.diskPath // "N/A"),
          (.spec.diskID // "N/A"),
          (.status.currentState // "N/A"),
          (.spec.healthyAt // "N/A"),
          (.spec.lastFailedAt // "N/A"),
          (.spec.lastHealthyAt // "N/A"),
          (.metadata.creationTimestamp // "N/A")
      ] | @tsv' | \
      while IFS=$'\t' read -r r_name r_ip r_storage_ip r_port r_node r_disk_path r_disk_id r_state r_healthy_at r_last_failed_at r_last_healthy_at r_created; do
          echo "    - name: ${r_name}"
          echo "      status.ip: ${r_ip}"
          echo "      status.storageIP: ${r_storage_ip}"
          echo "      status.port: ${r_port}"
          echo "      spec.nodeID: ${r_node}"
          echo "      spec.diskPath: ${r_disk_path}"
          echo "      spec.diskID: ${r_disk_id}"
          echo "      status.currentState: ${r_state}"
          echo "      spec.healthyAt: ${r_healthy_at}"
          echo "      spec.lastFailedAt: ${r_last_failed_at}"
          echo "      spec.lastHealthyAt: ${r_last_healthy_at}"
          echo "      creationTimestamp: ${r_created}"
          echo
      done
else
    echo "    No replicas found for volume ${VOL_NAME}"
fi

echo "================================================================================"