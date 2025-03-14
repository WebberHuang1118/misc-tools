#!/bin/bash
# This script checks all pods in the longhorn-system namespace,
# extracts the network-status annotation for the "lhnet1" interface,
# and then reports duplicate IP addresses per node and cluster-wide.

NAMESPACE="longhorn-system"
INTERFACE="lhnet1"

# Fetch pods and extract node, pod, and IP for the specified interface.
pod_ips=$(kubectl get pods -n "$NAMESPACE" -o json | jq -r --arg iface "$INTERFACE" '
  .items[] |
  { node: .spec.nodeName, pod: .metadata.name, netStatus: (.metadata.annotations["k8s.v1.cni.cncf.io/network-status"] // "[]") | fromjson } |
  (. as $parent | $parent.netStatus[]? | select(.interface == $iface) | .ips[]? | "\($parent.node) \($parent.pod) \(.)")
')

echo "List of IP addresses for interface '$INTERFACE' (Format: Node Pod IP):"
echo "$pod_ips"
echo

# Duplicate IP check per node (each node's IPs must be unique)
echo "Duplicate IP addresses per node:"
echo "$pod_ips" | awk '{print $1, $3}' | sort | uniq -c | awk '$1 > 1 {print "Node:", $2, "- IP:", $3, "- Count:", $1}'
echo

# Duplicate IP check cluster-wide (if the same IP appears anywhere more than once)
echo "Duplicate IP addresses cluster-wide:"
echo "$pod_ips" | awk '{print $3}' | sort | uniq -c | awk '$1 > 1 {print "IP:", $2, "- Count:", $1}'
