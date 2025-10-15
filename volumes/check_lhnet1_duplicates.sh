#!/bin/bash
# This script checks all pods in the longhorn-system namespace,
# extracts the network-status annotation for the "lhnet1" interface,
# and then reports duplicate IP addresses per node and cluster-wide.
# It also checks if each pod's lhnet1 IP has a corresponding OverlappingRangeIPReservation CR.

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
echo

# Check OverlappingRangeIPReservation CRs
echo "Checking OverlappingRangeIPReservation CRs for each pod's lhnet1 IP..."
echo

missing_crs=()
mismatched_podrefs=()

while IFS= read -r line; do
    if [[ -n "$line" ]]; then
        node=$(echo "$line" | awk '{print $1}')
        pod=$(echo "$line" | awk '{print $2}')
        ip=$(echo "$line" | awk '{print $3}')
        
        # Check if OverlappingRangeIPReservation CR exists with the IP as the name
        cr_exists=$(kubectl get overlappingrangeipreservation "$ip" -n kube-system -o name 2>/dev/null)
        
        if [[ -z "$cr_exists" ]]; then
            missing_crs+=("$node $pod $ip")
            echo "MISSING CR: Pod $pod on node $node with IP $ip has no corresponding OverlappingRangeIPReservation CR"
        else
            # CR exists, check if spec.podref matches the pod
            podref=$(kubectl get overlappingrangeipreservation "$ip" -n kube-system -o jsonpath='{.spec.podref}' 2>/dev/null)
            expected_podref="${NAMESPACE}/${pod}"
            
            if [[ "$podref" != "$expected_podref" ]]; then
                mismatched_podrefs+=("$node $pod $ip $podref")
                echo "MISMATCHED PODREF: Pod $pod on node $node with IP $ip has CR with podref '$podref', expected '$expected_podref'"
            else
                echo "OK: Pod $pod on node $node with IP $ip has matching OverlappingRangeIPReservation CR"
            fi
        fi
    fi
done <<< "$pod_ips"

echo
echo "Summary:"
echo "Total pods with lhnet1 IPs: $(echo "$pod_ips" | grep -c .)"
echo "Missing OverlappingRangeIPReservation CRs: ${#missing_crs[@]}"
echo "Mismatched podref in CRs: ${#mismatched_podrefs[@]}"

if [[ ${#missing_crs[@]} -eq 0 && ${#mismatched_podrefs[@]} -eq 0 ]]; then
    echo "✅ All checks passed! Every pod's lhnet1 IP has a corresponding OverlappingRangeIPReservation CR with matching podref."
else
    echo "❌ Issues found. Please review the details above."
fi
