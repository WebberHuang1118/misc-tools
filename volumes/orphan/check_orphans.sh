#!/bin/bash

# File containing the list (replace with your file path or input method)
INPUT_FILE=${1:-"orphan_paths.txt"}

# Namespace where Longhorn Orphan CRs are located (default is longhorn-system)
LONGHORN_NS="longhorn-system"

# Detect if output is being piped to a file
if [ -t 1 ]; then
  # Output is to a terminal
  GREEN="\033[32m"
  RED="\033[31m"
  RESET="\033[0m"
else
  # Output is being piped, disable colors
  GREEN=""
  RED=""
  RESET=""
fi

# Fetch all current orphan CRs, their data names, and their conditions
echo "Fetching current Longhorn Orphan CRs from cluster..."
kubectl get orphan.longhorn.io -n ${LONGHORN_NS} -o json \
  | jq -r '.items[] | [.metadata.name, .spec.parameters.DataName, (.status.conditions[] | select(.type == "DataCleanable" or .type == "Error") | .type + ":" + .status)] | @tsv' \
  > /tmp/orphan_data_names.tsv

# Build a lookup map of DataNames and their conditions
declare -A orphan_map
declare -A orphan_conditions_map
while IFS=$'\t' read -r name data_name conditions; do
  orphan_map["$data_name"]="$name"
  orphan_conditions_map["$data_name"]+="$conditions "
done < /tmp/orphan_data_names.tsv

# Initialize counters for found and missing
found_count=0
missing_count=0
cleanable_count=0
error_false_count=0

# Iterate over each line in the input
echo -e "\nChecking each replica data name..."
while read -r line; do
  size=$(echo "$line" | awk '{print $1}')
  path=$(echo "$line" | awk '{print $2}')
  data_name=$(basename "$path")

  if [[ -n "${orphan_map[$data_name]}" ]]; then
    printf "[${GREEN}FOUND${RESET}]  %-40s  %-10s\n" "$data_name" "$size"
    printf "          CR: %-40s\n" "${orphan_map[$data_name]}"
    printf "          Origin Path: %-40s\n" "$path"
    printf "          DataName: %-40s\n" "$data_name"
    printf "              Conditions: %s\n" "${orphan_conditions_map[$data_name]}"
    if [[ "${orphan_conditions_map[$data_name]}" == *"DataCleanable:True"* ]]; then
      printf "                  --> This orphan is cleanable.\n"
      ((cleanable_count++))
    fi
    if [[ "${orphan_conditions_map[$data_name]}" == *"Error:False"* ]]; then
      printf "                  --> This orphan has no errors.\n"
      ((error_false_count++))
    fi

    ((found_count++))
  else
    printf "[${RED}MISSING${RESET}] %-40s  %-10s\n" "$data_name" "$size"
    printf "          --> No matching Orphan CR\n"
    ((missing_count++))
  fi
done < "$INPUT_FILE"

# Final summary
echo -e "\nCheck complete."
echo -e "Summary:"
echo -e "  Found: $found_count"
echo -e "    DataCleanable is True: $cleanable_count"
echo -e "    Error is False: $error_false_count"
echo -e "  Missing: $missing_count"
