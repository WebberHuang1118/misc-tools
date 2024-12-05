#!/bin/bash

# Check if the parameter for numberOfReplicas is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <numberOfReplicas>"
  exit 1
fi

NUMBER_OF_REPLICAS=$1

# Fetch all Longhorn volumes and filter by numberOfReplicas
kubectl get volumes.longhorn.io --all-namespaces -o json | jq --argjson replicas "$NUMBER_OF_REPLICAS" -r '
  .items[] | 
  select(.spec.numberOfReplicas == $replicas) |
  {
    volume_name: .metadata.name,
    pvc_name: .status.kubernetesStatus.pvcName
  }
' | jq -s '
  {volumes: ., total: length}
'
