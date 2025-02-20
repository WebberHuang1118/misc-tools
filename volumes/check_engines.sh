#!/bin/bash

# Ensure the script receives the InstanceManager name as an argument
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <InstanceManagerName>"
  exit 1
fi

# InstanceManager name passed as a parameter
INSTANCE_MANAGER_NAME=$1

# Specify the namespace of Longhorn
NAMESPACE="longhorn-system"

# Fetch the InstanceManager resource and extract instance names
instances=$(kubectl -n $NAMESPACE get instancemanager $INSTANCE_MANAGER_NAME -o json | jq -r '.status.instances | keys[]')

if [[ -z "$instances" ]]; then
  echo "No instances found in InstanceManager $INSTANCE_MANAGER_NAME or InstanceManager does not exist."
  exit 1
fi

# Initialize flags to track missing engines and volumes
all_engines_exist=true
all_volumes_exist=true

echo "Checking if all engines and their corresponding volumes exist for instances in $INSTANCE_MANAGER_NAME..."

# Loop through each instance
for instance in $instances; do
  # Check if an Engine resource exists with the name
  engine_exists=$(kubectl -n $NAMESPACE get engine $instance --ignore-not-found)

  if [[ -z "$engine_exists" ]]; then
    echo "Engine for instance $instance is MISSING!"
    all_engines_exist=false
  else
    echo "Engine for instance $instance exists."

    # Extract the volume name from the engine name
    volume_name=$(echo $instance | sed -E 's/-e-[a-z0-9]+$//')

    # Check if the Volume resource exists with the name
    volume_exists=$(kubectl -n $NAMESPACE get volume $volume_name --ignore-not-found)

    if [[ -z "$volume_exists" ]]; then
      echo "Volume $volume_name related to engine $instance is MISSING!"
      all_volumes_exist=false
    else
      echo "Volume $volume_name related to engine $instance exists."
    fi
  fi
done

# Final status
if $all_engines_exist && $all_volumes_exist; then
  echo "All instances in $INSTANCE_MANAGER_NAME have corresponding engines and volumes."
else
  echo "Some instances in $INSTANCE_MANAGER_NAME are missing corresponding engines or volumes."
fi
