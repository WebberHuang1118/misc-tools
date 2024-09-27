#!/bin/bash

# Function to wait until status.readyToUse is true or status.error is not empty
wait_for_ready_or_error() {
  local name=$1
  echo "Waiting for VirtualMachineBackup $name to be ready or encounter an error..."

  # Loop until status.readyToUse is true or status.error is not empty
  while true; do
    ready_status=$(kubectl get virtualmachinebackup "$name" -n default -o jsonpath='{.status.readyToUse}')
    error_status=$(kubectl get virtualmachinebackup "$name" -n default -o jsonpath='{.status.error}')

    if [ "$ready_status" == "true" ]; then
      echo "VirtualMachineBackup $name is ready!"
      break
    elif [ -n "$error_status" ]; then
      echo "Error encountered in VirtualMachineBackup $name: $error_status"
      break
    else
      echo "Still waiting for VirtualMachineBackup $name..."
      sleep 5  # Wait 5 seconds before checking again
    fi
  done
}

# Loop to create CRs with names from 1 to 4
for i in {1..4}
do
  # Create the VirtualMachineBackup CR
  cat <<EOF | kubectl apply -f -
apiVersion: harvesterhci.io/v1beta1
kind: VirtualMachineBackup
metadata:
  name: "$i"
  namespace: default
spec:
  source:
    apiGroup: kubevirt.io
    kind: VirtualMachine
    name: vm2
  type: backup
EOF

  # Wait for status.readyToUse to be true or status.error to not be empty
  wait_for_ready_or_error "$i"

  # After the second iteration, stop the NFS service
  if [ "$i" -eq 2 ]; then
    echo "Stopping NFS service after iteration $i..."
    sudo service nfs-kernel-server stop
  fi

  # After the fourth iteration, start the NFS service again
  if [ "$i" -eq 4 ]; then
    echo "Starting NFS service after iteration $i..."
    sudo service nfs-kernel-server start
  fi
done

