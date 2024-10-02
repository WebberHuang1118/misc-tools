#!/bin/bash

# Check if the user name is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <username>"
  exit 1
fi

USERNAME=$1

# Function to print a separator for clarity
print_separator() {
  echo "------------------------------------------"
}

# Get all RoleBindings and ClusterRoleBindings that reference the user
echo "Fetching RoleBindings for user: $USERNAME"
ROLE_BINDINGS=$(kubectl get rolebindings --all-namespaces -o json | jq --arg USER "$USERNAME" '
  .items[] |
  select(.subjects[]? | (.kind == "User" and .name == $USER)) |
  {
    namespace: .metadata.namespace,
    role: .roleRef.name,
    roleKind: .roleRef.kind,
    subjects: .subjects
  }
')

echo "$ROLE_BINDINGS" | jq .

echo "Fetching ClusterRoleBindings for user: $USERNAME"
CLUSTER_ROLE_BINDINGS=$(kubectl get clusterrolebindings -o json | jq --arg USER "$USERNAME" '
  .items[] |
  select(.subjects[]? | (.kind == "User" and .name == $USER)) |
  {
    role: .roleRef.name,
    roleKind: .roleRef.kind,
    subjects: .subjects
  }
')

echo "$CLUSTER_ROLE_BINDINGS" | jq .

# Get the associated Roles or ClusterRoles for the user
echo
echo "========== Fetching Rules for Associated Roles and ClusterRoles =========="
echo
echo "$ROLE_BINDINGS" | jq -r '.role + " " + .roleKind + " " + .namespace' | while read -r role roleKind namespace; do
  print_separator
  if [ "$roleKind" == "ClusterRole" ]; then
    echo "ClusterRole: $role"
    echo "------------------------------------------"
    kubectl get clusterrole "$role" -o yaml || echo "ClusterRole not found: $role"
  else
    echo "Role: $role in namespace: $namespace"
    echo "------------------------------------------"
    kubectl get role "$role" -n "$namespace" -o yaml || echo "Role not found in namespace: $namespace"
  fi
  print_separator
done

# Get the associated ClusterRoles for the user
echo "$CLUSTER_ROLE_BINDINGS" | jq -r '.role' | while read -r clusterrole; do
  print_separator
  echo "ClusterRole: $clusterrole"
  echo "------------------------------------------"
  kubectl get clusterrole "$clusterrole" -o yaml || echo "ClusterRole not found"
  print_separator
done

echo "====================================================================="

