#!/usr/bin/env bash
set -euo pipefail

# Check prerequisites
for bin in jq column; do
  if ! command -v $bin &>/dev/null; then
    echo "Error: '$bin' is required." >&2
    exit 1
  fi
done

# Fetch all Longhorn Node CRs
nodes_json=$(kubectl get nodes.longhorn.io -A -o json)

# 1) Report any nodes requested to evict
echo "=== Longhorn Nodes with evictionRequested ==="
echo "$nodes_json" | jq -r '
  .items[]
  | select(.spec.evictionRequested == true)
  | "\(.metadata.namespace)/\(.metadata.name)"
' || echo "  (none)"

echo
# 2) Report disks requested to evict in a table (hint: EVICT=yes means evictionRequested=true)
{
  # Header with new column
  echo -e "NODE\tDISK\tPATH\tEVICT"
  echo -e "----\t----\t----\t-----"

  # Data rows, appending “yes” in the EVICT column
  kubectl get nodes.longhorn.io -A -o json \
    | jq -r '
        .items[]
        | .metadata.namespace + "/" + .metadata.name as $node
        | .spec.disks
        | to_entries[]
        | select(.value.evictionRequested == true)
        | "\($node)\t\(.key)\t\(.value.path)\tyes"
      '
} | column -t -s $'\t'
