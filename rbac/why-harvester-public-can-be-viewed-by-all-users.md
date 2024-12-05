The `RoleBinding` you found in the `harvester-public` namespace explains why the user `u-8zbwk` can access resources in that namespace. Here's a breakdown of what it means: (from `kubectl get rolebindings -n harvester-public`)

### Breakdown of the `RoleBinding`

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: harvester-public
  namespace: harvester-public
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:authenticated
```

1. **`metadata.name: harvester-public`**:
   - This `RoleBinding` is named `harvester-public` and is applied specifically in the `harvester-public` namespace.

2. **`roleRef`**:
   - **`kind: ClusterRole`**: This indicates that the `RoleBinding` refers to a `ClusterRole` rather than a namespace-scoped `Role`.
   - **`name: view`**: The `ClusterRole` being referenced is `view`. This role provides read-only access to view resources within a namespace.

3. **`subjects`**:
   - **`kind: Group`** and **`name: system:authenticated`**: This grants the permissions defined in the `view` ClusterRole to all users that belong to the group `system:authenticated`.
   - The `system:authenticated` group includes all authenticated users in the cluster. Therefore, any user who is authenticated, including `u-8zbwk`, falls into this group and inherits the permissions defined by the `view` ClusterRole.

### What This Means

Since the `RoleBinding` in the `harvester-public` namespace binds the `view` ClusterRole to the `system:authenticated` group, any authenticated user (including `u-8zbwk`) will have read-only access to resources within the `harvester-public` namespace.

This configuration is likely set up to allow general, read-only access for all authenticated users to the resources within this namespace. That is why `u-8zbwk` can see `virtualmachineimages` and other resources in `harvester-public` but not in other namespaces where this `RoleBinding` doesn’t apply.

### Summary

- The `RoleBinding` `harvester-public` allows all authenticated users to use the `view` ClusterRole in the `harvester-public` namespace.
- This explains why `u-8zbwk` can access resources within `harvester-public`: as an authenticated user, they inherit the `view` permissions for that namespace.

If you want to restrict this access, you may need to modify or remove this `RoleBinding` or create a more specific binding that limits which users or groups have access to the `harvester-public` namespace.

### Source code

Setting from https://github.com/harvester/harvester/blob/d4c699718434682dda46c201cbbd87e80d23db8d/pkg/data/rbac.go#L11-L74

### Clusterrole View

Is from clustrole/role with "rbac.authorization.k8s.io/aggregate-to-view: "true""

In harvester, ClusterRole harvesterhci.io:view
https://github.com/harvester/harvester/blob/d4c699718434682dda46c201cbbd87e80d23db8d/deploy/charts/harvester/templates/rbac.yaml#L63-L65