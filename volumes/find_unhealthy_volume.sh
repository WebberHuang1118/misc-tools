#!/bin/bash
# Find Longhorn volumes that are attached (not "detached") but not "healthy"

NAMESPACE="longhorn-system"

echo "Checking Longhorn volumes in namespace: $NAMESPACE"
echo

kubectl get volume -n "$NAMESPACE" -o json | jq -r '
  .items[] |
  select(
    (.status.state != "detached") and 
    (.status.robustness != "healthy")
  ) |
  [
    .metadata.name,
    (.status.state // "N/A"),
    (.status.robustness // "N/A"),
    (.spec.nodeID // "N/A")
  ] | @tsv
' | awk 'BEGIN {
    print "Volume\tState\tRobustness\tNodeID"
    print "-----------------------------------------------------------"
}
{
    print $0
}'
