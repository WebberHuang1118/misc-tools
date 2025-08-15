# Virtual Machine (VM) Tools

This directory contains tools for managing and monitoring KubeVirt virtual machines in Kubernetes clusters.

## Files

- `check_kubevirt_vms.sh` - Main script for checking KubeVirt VM instances and their virt-launcher pods
- `vm_list.txt` - Sample VM list file containing VM names organized by environment
- `vm_list-sure-10553.txt` - Specific VM list file for targeted monitoring

## check_kubevirt_vms.sh

A comprehensive bash script that monitors KubeVirt virtual machine instances (VMI) and their associated virt-launcher pods. The script provides detailed status information, creation timestamps, and node placement details.

### Features

- ✅ Check VM instance (VMI) status and health
- ✅ Monitor virt-launcher pod status
- ✅ Display creation timestamps and node placement
- ✅ Support for both single VM file input and cluster-wide scanning
- ✅ **Dynamic namespace detection** from actual VM resources
- ✅ Cross-namespace pod discovery
- ✅ Node mismatch detection between VMI and pods
- ✅ Color-coded output for better readability
- ✅ Summary statistics and analysis

### Usage

```bash
# Check all VMs in the cluster
./check_kubevirt_vms.sh

# Check specific VMs from a file
./check_kubevirt_vms.sh vm_list.txt
```

### Dynamic Namespace Detection

The script **automatically discovers namespaces** by querying the Kubernetes cluster for actual VM resources instead of relying on hardcoded patterns. This approach:

- **Queries VMI resources first** using `kubectl get vmi --all-namespaces`
- **Falls back to VM objects** if VMI is not found
- **Works with any namespace naming convention**
- **Eliminates the need for manual namespace mapping updates**

### Output Information

For each VM, the script displays:

**VMI (Virtual Machine Instance):**
- Status (Running, NOT FOUND, etc.)
- Creation timestamp
- Node placement

**Pod (virt-launcher):**
- Pod name
- Status (Running, NOT FOUND, etc.)
- Creation timestamp
- Node placement

### Summary Features

- **Statistics:** Total VMs checked, found VMIs, found pods, missing components
- **Node Analysis:** Detects mismatches between VMI and pod node placement
- **Summary Table:** Tabular view of all VM statuses for easy comparison
- **Issue Detection:** Identifies missing VMIs or virt-launcher pods

### Status Indicators

- ✓ Green: Running/Healthy
- ✗ Red: Not Found/Error
- ⚠ Yellow: Warning/Other Status

### Example Output

```
╔════════════════════════════════════════════════════════════════════════════════╗
║                           KubeVirt VM Status Check                            ║
╚════════════════════════════════════════════════════════════════════════════════╝

┌─ VM: appsite-dev-1-workerpool1-kmvqg-rk865
├─ Namespace: appsite-dev-1
├─ VMI:
│  ├─ Status: ✓ Running
│  ├─ Created: 2025-07-22 02:08:33
│  └─ Node: node-xyz789
└─ Pod:
   ├─ Name: virt-launcher-appsite-dev-1-workerpool1-kmvqg-rk865-w4n7l
   ├─ Status: ✓ Running
   ├─ Created: 2025-07-22 04:53:20
   └─ Node: node-xyz789
```

## VM List Files

### vm_list.txt

Sample file containing VM names organized by environment. This file demonstrates the expected format for VM list files:

- Lines starting with `#` are treated as comments
- Empty lines are ignored
- Each VM name should be on its own line

### vm_list-sure-10553.txt

Production VM list file containing 16 specific VMs for targeted monitoring, primarily located on the `node-xyz789` node.

### Sample Structure

```
# Application Development VMs
appsite-dev-1-workerpool1-kmvqg-rk865
appsite-dev-1-workerpool1-kmvqg-s674q

# Application Production VMs
appsite-prod-1-controlplane-4nr4h-bf66k
appsite-prod-1-workerpool1-hjmgg-v6c48

# Platform Management VMs
rke2-platform-mgmt-02
```

## Prerequisites

- `kubectl` must be installed and configured
- Access to the Kubernetes cluster with KubeVirt
- Appropriate RBAC permissions to read VMI and Pod resources across all namespaces
- Bash shell environment
- Proper KUBECONFIG setup (e.g., `KUBECONFIG=/home/user/.sim/admin.kubeconfig`)

## Error Handling

The script includes robust error handling for:
- Missing VM list files
- Network connectivity issues
- Insufficient permissions
- Cross-namespace pod searches
- Invalid VM names or formats
- Namespace detection failures

## Use Cases

- **Health Monitoring:** Regular checks of VM infrastructure
- **Troubleshooting:** Identify missing or misconfigured VMs
- **Capacity Planning:** Monitor VM distribution across nodes
- **Compliance:** Verify VM deployment consistency
- **Migration Planning:** Understand current VM placement
- **Node-specific Analysis:** Monitor VMs on specific nodes (e.g., `node-xyz789`)

## Tips

1. Use the cluster-wide mode (`./check_kubevirt_vms.sh`) for comprehensive health checks
2. Create custom VM list files for environment-specific monitoring
3. Run regularly via cron for automated monitoring
4. Pipe output to files for historical tracking
5. Use the node mismatch detection to identify potential issues
6. Set the appropriate `KUBECONFIG` environment variable before running
7. The dynamic namespace detection eliminates the need to update hardcoded mappings

## Contributing

The script now uses dynamic namespace detection, so there's no need to manually update namespace patterns. However, when making changes:

1. Test with both cluster-wide and file-based VM lists
2. Verify cross-namespace functionality
3. Update this README with any new features or usage patterns
4. Test with different KUBECONFIG setups