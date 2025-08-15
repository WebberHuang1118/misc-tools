#!/bin/bash

# Script to check KubeVirt VM instances (VMI) and their virt-launcher pods
# This script checks the status.phase, creation time, and node placement for both VMI and pods
# Usage: 
#   ./check_kubevirt_vms.sh                    # Check all VMs
#   ./check_kubevirt_vms.sh vm_list.txt        # Check VMs from file

echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║                           KubeVirt VM Status Check                            ║"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"
echo "Timestamp: $(date)"
echo

# Function to get all VMs from cluster
get_all_vms() {
    # Get all VMIs (running virtual machine instances)
    local vmis=($(kubectl get vmi --all-namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | sort))
    
    # Get all VM objects (including those that might not have VMIs)
    local vms=($(kubectl get vm --all-namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | sort))
    
    # Combine and deduplicate the lists
    local all_vms=($(printf '%s\n' "${vmis[@]}" "${vms[@]}" | sort -u))
    
    printf '%s\n' "${all_vms[@]}"
}

# Function to read VMs from file
read_vms_from_file() {
    local file_path=$1
    if [ ! -f "$file_path" ]; then
        echo "❌ Error: File '$file_path' not found!" >&2
        exit 1
    fi
    
    # Read file, remove empty lines and comments
    grep -v '^\s*#' "$file_path" | grep -v '^\s*$' | tr -d '\r'
}

# Determine VM list source
declare -a VMS
if [ $# -eq 0 ]; then
    # No arguments - get all VMs
    echo "📊 Mode: Checking ALL VMs in the cluster"
    readarray -t VMS < <(get_all_vms)
    echo "Found ${#VMS[@]} VMs to check"
elif [ $# -eq 1 ]; then
    # One argument - read from file
    echo "📋 Mode: Checking VMs from file"
    readarray -t VMS < <(read_vms_from_file "$1")
    echo "Found ${#VMS[@]} VMs in file: $1"
else
    echo "❌ Usage: $0 [vm_list_file]"
    echo "   $0                    # Check all VMs in cluster"
    echo "   $0 vm_list.txt        # Check VMs listed in file"
    exit 1
fi

if [ ${#VMS[@]} -eq 0 ]; then
    echo "❌ No VMs found to check!"
    exit 1
fi

echo
echo "📝 VMs to be checked:"
for vm in "${VMS[@]}"; do
    echo "  • $vm"
done
echo

# Color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to extract namespace from VM name
get_namespace() {
    local vm_name=$1
    
    # First try to get namespace from VMI
    local namespace=$(kubectl get vmi --all-namespaces -o jsonpath='{range .items[*]}{.metadata.name}{","}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | grep "^$vm_name," | cut -d',' -f2 | head -1)
    
    # If VMI not found, try to get namespace from VM object
    if [[ -z "$namespace" ]]; then
        namespace=$(kubectl get vm --all-namespaces -o jsonpath='{range .items[*]}{.metadata.name}{","}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | grep "^$vm_name," | cut -d',' -f2 | head -1)
    fi
    
    # If still not found, return "unknown"
    if [[ -z "$namespace" ]]; then
        echo "unknown"
    else
        echo "$namespace"
    fi
}

# Function to format status with color
format_status() {
    local status=$1
    case $status in
        "Running")
            echo -e "${GREEN}✓ Running${NC}"
            ;;
        "NOT FOUND")
            echo -e "${RED}✗ NOT FOUND${NC}"
            ;;
        *)
            echo -e "${YELLOW}⚠ $status${NC}"
            ;;
    esac
}

# Function to format timestamp
format_timestamp() {
    local timestamp=$1
    if [[ $timestamp == "N/A" ]]; then
        echo -e "${RED}N/A${NC}"
    else
        # Convert to more readable format and add color
        local formatted=$(echo "$timestamp" | cut -c1-19 | sed 's/T/ /')
        echo -e "${CYAN}$formatted${NC}"
    fi
}

# Function to format node name
format_node() {
    local node=$1
    if [[ $node == "N/A" ]] || [[ -z $node ]]; then
        echo -e "${RED}N/A${NC}"
    else
        echo -e "${CYAN}$node${NC}"
    fi
}

# Function to check virt-launcher pod
check_virt_launcher_pod() {
    local vm_name=$1
    local namespace=$2
    
    # Search for virt-launcher pod using the vm.kubevirt.io/name label (most reliable)
    local pod_info=$(kubectl get pods -n "$namespace" -l "vm.kubevirt.io/name=$vm_name" -o jsonpath='{range .items[*]}{.metadata.name},{.status.phase},{.metadata.creationTimestamp},{.spec.nodeName}{"\n"}{end}' 2>/dev/null | head -1)
    
    if [ -z "$pod_info" ]; then
        # Fallback: search by kubevirt.io label and VM name pattern
        pod_info=$(kubectl get pods -n "$namespace" -l "kubevirt.io=virt-launcher" -o jsonpath='{range .items[*]}{.metadata.name},{.status.phase},{.metadata.creationTimestamp},{.spec.nodeName},{.metadata.labels.vm\.kubevirt\.io/name}{"\n"}{end}' 2>/dev/null | grep "$vm_name" | head -1)
        
        if [ -n "$pod_info" ]; then
            # Remove the extra field (vm name) from the end
            pod_info=$(echo "$pod_info" | cut -d',' -f1-4)
        fi
    fi
    
    if [ -z "$pod_info" ]; then
        # Last resort: search across all namespaces using label
        pod_info=$(kubectl get pods --all-namespaces -l "vm.kubevirt.io/name=$vm_name" -o jsonpath='{range .items[*]}{.metadata.namespace},{.metadata.name},{.status.phase},{.metadata.creationTimestamp},{.spec.nodeName}{"\n"}{end}' 2>/dev/null | head -1)
        
        if [ -n "$pod_info" ]; then
            IFS=',' read -r found_namespace pod_name pod_status pod_creation pod_node <<< "$pod_info"
            echo -e "   ${BLUE}├─ Name: ${CYAN}$pod_name${NC}"
            echo -e "   ${BLUE}├─ Status: $(format_status "$pod_status")"
            echo -e "   ${BLUE}├─ Created: $(format_timestamp "$pod_creation")"
            echo -e "   ${BLUE}├─ Node: $(format_node "$pod_node")"
            echo -e "   ${BLUE}└─ Found in namespace: ${YELLOW}$found_namespace${NC}"
            found_pods=$((found_pods + 1))
            return 0
        fi
    else
        IFS=',' read -r pod_name pod_status pod_creation pod_node <<< "$pod_info"
        found_pods=$((found_pods + 1))
    fi
    
    if [ -n "$pod_name" ]; then
        echo -e "   ${BLUE}├─ Name: ${CYAN}$pod_name${NC}"
        echo -e "   ${BLUE}├─ Status: $(format_status "$pod_status")"
        echo -e "   ${BLUE}├─ Created: $(format_timestamp "$pod_creation")"
        echo -e "   ${BLUE}└─ Node: $(format_node "$pod_node")"
        return 0
    else
        echo -e "   ${BLUE}├─ Status: $(format_status "NOT FOUND")"
        echo -e "   ${BLUE}├─ Created: $(format_timestamp "N/A")"
        echo -e "   ${BLUE}└─ Node: $(format_node "N/A")"
        return 1
    fi
}

# Arrays to store summary data
declare -a summary_data
declare -a issues

# Main processing loop
total_vms=0
found_vmis=0
found_pods=0

echo "┌────────────────────────────────────────────────────────────────────────────────┐"
echo "│                                Checking VMs...                                │"
echo "└────────────────────────────────────────────────────────────────────────────────┘"
echo

for vm in "${VMS[@]}"; do
    echo -e "${BLUE}┌─ VM: ${CYAN}$vm${NC}"
    
    namespace=$(get_namespace "$vm")
    total_vms=$((total_vms + 1))
    
    # Check VMI
    vmi_status="NOT FOUND"
    vmi_creation="N/A"
    vmi_node="N/A"
    echo -e "${BLUE}├─ Namespace: ${YELLOW}$namespace${NC}"
    echo -e "${BLUE}├─ VMI:${NC}"
    
    vmi_info=$(kubectl get vmi "$vm" -n "$namespace" -o jsonpath='{.status.phase},{.metadata.creationTimestamp},{.status.nodeName}' 2>/dev/null)
    
    if [ -n "$vmi_info" ]; then
        found_vmis=$((found_vmis + 1))
        IFS=',' read -r vmi_status vmi_creation vmi_node <<< "$vmi_info"
        echo -e "${BLUE}│  ├─ Status: $(format_status "$vmi_status")"
        echo -e "${BLUE}│  ├─ Created: $(format_timestamp "$vmi_creation")"
        echo -e "${BLUE}│  └─ Node: $(format_node "$vmi_node")"
    else
        echo -e "${BLUE}│  ├─ Status: $(format_status "NOT FOUND")"
        echo -e "${BLUE}│  ├─ Created: $(format_timestamp "N/A")"
        echo -e "${BLUE}│  └─ Node: $(format_node "N/A")"
        issues+=("$vm: Missing VMI")
    fi
    
    echo -e "${BLUE}└─ Pod:${NC}"
    
    # Check virt-launcher pod
    pod_status="NOT FOUND"
    pod_creation="N/A"
    pod_node="N/A"
    if check_virt_launcher_pod "$vm" "$namespace"; then
        # Get the pod info for summary (the function already incremented found_pods)
        pod_info=$(kubectl get pods -n "$namespace" -l "vm.kubevirt.io/name=$vm" -o jsonpath='{range .items[*]}{.metadata.name},{.status.phase},{.metadata.creationTimestamp},{.spec.nodeName}{"\n"}{end}' 2>/dev/null | head -1)
        
        if [ -z "$pod_info" ]; then
            # Fallback search
            pod_info=$(kubectl get pods -n "$namespace" -l "kubevirt.io=virt-launcher" -o jsonpath='{range .items[*]}{.metadata.name},{.status.phase},{.metadata.creationTimestamp},{.spec.nodeName},{.metadata.labels.vm\.kubevirt\.io/name}{"\n"}{end}' 2>/dev/null | grep "$vm" | head -1)
            if [ -n "$pod_info" ]; then
                pod_info=$(echo "$pod_info" | cut -d',' -f1-4)
            fi
        fi
        
        if [ -z "$pod_info" ]; then
            # Cross-namespace search
            pod_info=$(kubectl get pods --all-namespaces -l "vm.kubevirt.io/name=$vm" -o jsonpath='{range .items[*]}{.metadata.namespace},{.metadata.name},{.status.phase},{.metadata.creationTimestamp},{.spec.nodeName}{"\n"}{end}' 2>/dev/null | head -1)
            if [ -n "$pod_info" ]; then
                IFS=',' read -r found_namespace pod_name pod_status pod_creation pod_node <<< "$pod_info"
                namespace="$found_namespace"
            fi
        else
            IFS=',' read -r pod_name pod_status pod_creation pod_node <<< "$pod_info"
        fi
    else
        issues+=("$vm: Missing virt-launcher pod")
    fi
    
    # Store summary data
    summary_data+=("$vm|$namespace|$vmi_status|$vmi_creation|$vmi_node|$pod_status|$pod_creation|$pod_node")
    
    echo
done

echo "┌────────────────────────────────────────────────────────────────────────────────┐"
echo "│                                Summary Table                                   │"
echo "└────────────────────────────────────────────────────────────────────────────────┘"
echo

# Print summary table header
printf "%-30s %-18s %-12s %-20s %-15s %-12s %-20s %-15s\n" "VM Name" "Namespace" "VMI Status" "VMI Created" "VMI Node" "Pod Status" "Pod Created" "Pod Node"
printf "%-30s %-18s %-12s %-20s %-15s %-12s %-20s %-15s\n" "$(printf '%.0s─' {1..30})" "$(printf '%.0s─' {1..18})" "$(printf '%.0s─' {1..12})" "$(printf '%.0s─' {1..20})" "$(printf '%.0s─' {1..15})" "$(printf '%.0s─' {1..12})" "$(printf '%.0s─' {1..20})" "$(printf '%.0s─' {1..15})"

# Print summary data
for entry in "${summary_data[@]}"; do
    IFS='|' read -r vm namespace vmi_status vmi_creation vmi_node pod_status pod_creation pod_node <<< "$entry"
    
    # Format timestamps for display
    vmi_creation_short=$(echo "$vmi_creation" | cut -c1-19 | sed 's/T/ /')
    pod_creation_short=$(echo "$pod_creation" | cut -c1-19 | sed 's/T/ /')
    
    # Truncate node names if they're too long
    vmi_node_short=$(echo "$vmi_node" | cut -c1-14)
    pod_node_short=$(echo "$pod_node" | cut -c1-14)
    
    # Add status indicators
    vmi_indicator=""
    pod_indicator=""
    
    case $vmi_status in
        "Running") vmi_indicator="✓" ;;
        "NOT FOUND") vmi_indicator="✗" ;;
        *) vmi_indicator="⚠" ;;
    esac
    
    case $pod_status in
        "Running") pod_indicator="✓" ;;
        "NOT FOUND") pod_indicator="✗" ;;
        *) pod_indicator="⚠" ;;
    esac
    
    printf "%-30s %-18s %-1s%-11s %-20s %-15s %-1s%-11s %-20s %-15s\n" \
        "$vm" "$namespace" "$vmi_indicator" "$vmi_status" "$vmi_creation_short" "$vmi_node_short" "$pod_indicator" "$pod_status" "$pod_creation_short" "$pod_node_short"
done

echo
echo "┌────────────────────────────────────────────────────────────────────────────────┐"
echo "│                               Statistics                                       │"
echo "└────────────────────────────────────────────────────────────────────────────────┘"

echo -e "Total VMs checked: ${CYAN}$total_vms${NC}"
echo -e "Found VMIs: ${GREEN}$found_vmis${NC}"
echo -e "Found Pods: ${GREEN}$found_pods${NC}"
echo -e "Missing VMIs: ${RED}$((total_vms - found_vmis))${NC}"
echo -e "Missing Pods: ${RED}$((total_vms - found_pods))${NC}"

# Check for node mismatches
echo
echo "┌────────────────────────────────────────────────────────────────────────────────┐"
echo "│                              Node Analysis                                     │"
echo "└────────────────────────────────────────────────────────────────────────────────┘"

node_mismatches=0
for entry in "${summary_data[@]}"; do
    IFS='|' read -r vm namespace vmi_status vmi_creation vmi_node pod_status pod_creation pod_node <<< "$entry"
    
    if [[ "$vmi_node" != "N/A" ]] && [[ "$pod_node" != "N/A" ]] && [[ "$vmi_node" != "$pod_node" ]]; then
        echo -e "${RED}⚠ Node mismatch for $vm: VMI on '$vmi_node', Pod on '$pod_node'${NC}"
        node_mismatches=$((node_mismatches + 1))
    fi
done

if [ $node_mismatches -eq 0 ]; then
    echo -e "${GREEN}✓ No node mismatches found${NC}"
else
    echo -e "${RED}✗ Found $node_mismatches node mismatches${NC}"
fi

echo
echo "┌────────────────────────────────────────────────────────────────────────────────┐"
echo "│ Script completed at: $(date)                        │"
echo "└────────────────────────────────────────────────────────────────────────────────┘"