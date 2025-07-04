#!/bin/bash

SC_NAME="prod-longhorn"

# Get matching PVs as compact JSON lines
pvs=$(kubectl get pv -o json | jq -c \
  --arg sc "$SC_NAME" \
  '.items[] | select(.spec.storageClassName == $sc) |
   {
     pvName: .metadata.name,
     capacity: .spec.capacity.storage,
     phase: .status.phase
   }')

# Count total number
total=$(echo "$pvs" | wc -l)

# Print header
echo "PV with storageClassName = \"$SC_NAME\""
echo "Total: $total PV(s)"
echo -e "PV Name\tCapacity\tPhase\tLonghorn Status"

# Iterate and print details
echo "$pvs" | while read -r json_line; do
  pv_name=$(echo "$json_line" | jq -r '.pvName')
  capacity=$(echo "$json_line" | jq -r '.capacity')
  phase=$(echo "$json_line" | jq -r '.phase')

  lh_state=$(kubectl get -n longhorn-system volume.longhorn.io "$pv_name" -o jsonpath='{.status.state}' 2>/dev/null || echo "NotFound")

  printf "%s\t%s\t%s\t%s\n" "$pv_name" "$capacity" "$phase" "$lh_state"
done
