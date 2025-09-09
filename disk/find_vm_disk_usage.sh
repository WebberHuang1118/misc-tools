#!/bin/bash

# Script to find VM disk image files and check if they're used by VMs
# Usage: sudo ./find_vm_disk_usage.sh [OPTIONS] [search_path]
# Note: Requires sudo to access system libvirt directories and run virsh commands

# set -e  # Will enable after fixing error handling issues

# Default search paths for VM disk images
DEFAULT_SEARCH_PATHS=(
    "/var/lib/libvirt/images"
    "/var/lib/libvirt/qemu"
    "/opt/vm-images" 
    "/home/*/VirtualMachines"
    "/home/*/.local/share/libvirt/images"
    "/tmp"
)

# Global variables for options
DELETE_MODE=false
DRY_RUN=false
SEARCH_PATH=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if running with sufficient privileges
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        print_color $YELLOW "Warning: Running without root privileges."
        print_color $YELLOW "Some system directories may not be accessible."
        print_color $YELLOW "Consider running with: sudo $0 $@"
        echo
    fi
}

# Function to check if virsh is available
check_virsh() {
    if ! command -v virsh &> /dev/null; then
        print_color $RED "Error: virsh command not found. Please install libvirt-clients."
        exit 1
    fi
}

# Function to find disk image files
find_disk_images() {
    local search_path="$1"
    
    if [[ ! -d "$search_path" ]]; then
        return
    fi
    
    # Find common VM disk image formats
    find "$search_path" -type f \( \
        -name "*.qcow2" -o \
        -name "*.qcow" -o \
        -name "*.img" -o \
        -name "*.raw" -o \
        -name "*.vmdk" -o \
        -name "*.vdi" -o \
        -name "*.vhd" -o \
        -name "*.vhdx" \
    \) 2>/dev/null
}

# Function to get all VM disk paths from virsh
get_vm_disks() {
    local vm_disks=()
    local vms
    
    # Get list of all VMs (running and stopped)
    vms=$(virsh list --all --name 2>/dev/null || true)
    
    for vm in $vms; do
        if [[ -n "$vm" ]]; then
            # Get disk paths from VM definition, filtering out empty sources and cdrom devices
            local disks
            disks=$(virsh domblklist "$vm" --details 2>/dev/null | awk '$1=="file" && $4 != "-" && $4 != "" {print $4}' || true)
            for disk in $disks; do
                if [[ -n "$disk" && "$disk" != "-" ]]; then
                    vm_disks+=("$disk")
                fi
            done
        fi
    done
    
    printf '%s\n' "${vm_disks[@]}" | sort -u
}

# Function to check if a disk is used by any VM
is_disk_used() {
    local disk_path="$1"
    local used_disks="$2"
    
    echo "$used_disks" | grep -Fxq "$disk_path"
}

# Function to get VM names using a specific disk
get_vms_using_disk() {
    local disk_path="$1"
    local vms_using_disk=()
    local vms
    
    vms=$(virsh list --all --name 2>/dev/null || true)
    
    for vm in $vms; do
        if [[ -n "$vm" ]]; then
            local disks
            disks=$(virsh domblklist "$vm" --details 2>/dev/null | awk '/^file/ {print $4}' || true)
            for disk in $disks; do
                if [[ "$disk" == "$disk_path" ]]; then
                    vms_using_disk+=("$vm")
                fi
            done
        fi
    done
    
    printf '%s\n' "${vms_using_disk[@]}"
}

# Function to get file size in human readable format
get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        du -h "$file" | cut -f1
    else
        echo "N/A"
    fi
}

# Function to get file modification time
get_file_mtime() {
    local file="$1"
    if [[ -f "$file" ]]; then
        stat -c "%y" "$file" | cut -d'.' -f1
    else
        echo "N/A"
    fi
}

# Function to confirm deletion
confirm_deletion() {
    local unused_images=("$@")
    local total_size=0
    
    echo
    print_color $YELLOW "=== DELETION CONFIRMATION ==="
    print_color $RED "WARNING: You are about to delete ${#unused_images[@]} unused disk image files!"
    echo
    
    # Calculate total size of files to be deleted
    for image in "${unused_images[@]}"; do
        if [[ -f "$image" ]]; then
            local size_bytes=$(stat -c%s "$image" 2>/dev/null || echo 0)
            total_size=$((total_size + size_bytes))
        fi
    done
    
    # Convert to human readable format
    local human_size=$(numfmt --to=iec --suffix=B $total_size 2>/dev/null || echo "${total_size} bytes")
    
    print_color $CYAN "Total space to be freed: $human_size"
    echo
    print_color $RED "Files to be deleted:"
    for image in "${unused_images[@]}"; do
        local size=$(get_file_size "$image")
        print_color $RED "  - $image ($size)"
    done
    
    echo
    print_color $YELLOW "This action cannot be undone!"
    echo -n "Are you sure you want to delete these files? (Type 'yes' to confirm): "
    read -r confirmation
    
    if [[ "$confirmation" == "yes" ]]; then
        return 0
    else
        print_color $GREEN "Deletion cancelled."
        return 1
    fi
}

# Function to delete unused disk images
delete_unused_images() {
    local unused_images=("$@")
    local deleted_count=0
    local failed_count=0
    local total_freed=0
    
    if [[ ${#unused_images[@]} -eq 0 ]]; then
        print_color $GREEN "No unused disk images to delete."
        return 0
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_color $CYAN "=== DRY RUN MODE - No files will actually be deleted ==="
        echo
        print_color $YELLOW "Would delete ${#unused_images[@]} unused disk image files:"
        
        for image in "${unused_images[@]}"; do
            if [[ -f "$image" ]]; then
                local size=$(get_file_size "$image")
                local size_bytes=$(stat -c%s "$image" 2>/dev/null || echo 0)
                total_freed=$((total_freed + size_bytes))
                print_color $YELLOW "  [DRY RUN] Would delete: $image ($size)"
            else
                print_color $RED "  [DRY RUN] File not found: $image"
            fi
        done
        
        local human_total=$(numfmt --to=iec --suffix=B $total_freed 2>/dev/null || echo "${total_freed} bytes")
        echo
        print_color $CYAN "Total space that would be freed: $human_total"
        print_color $BLUE "To actually delete these files, run without --dry-run option."
        return 0
    fi
    
    # Confirm deletion in non-dry-run mode
    if ! confirm_deletion "${unused_images[@]}"; then
        return 1
    fi
    
    echo
    print_color $BLUE "=== DELETING UNUSED DISK IMAGES ==="
    
    for image in "${unused_images[@]}"; do
        if [[ -f "$image" ]]; then
            local size_bytes=$(stat -c%s "$image" 2>/dev/null || echo 0)
            
            if rm -f "$image" 2>/dev/null; then
                local size=$(get_file_size "$image" 2>/dev/null || echo "unknown")
                print_color $GREEN "✓ Deleted: $image"
                ((deleted_count++))
                total_freed=$((total_freed + size_bytes))
            else
                print_color $RED "✗ Failed to delete: $image"
                ((failed_count++))
            fi
        else
            print_color $RED "✗ File not found: $image"
            ((failed_count++))
        fi
    done
    
    echo
    print_color $BLUE "=== DELETION SUMMARY ==="
    print_color $GREEN "Successfully deleted: $deleted_count files"
    if [[ $failed_count -gt 0 ]]; then
        print_color $RED "Failed to delete: $failed_count files"
    fi
    
    local human_total=$(numfmt --to=iec --suffix=B $total_freed 2>/dev/null || echo "${total_freed} bytes")
    print_color $CYAN "Total space freed: $human_total"
}

# Main function
main() {
    local all_disk_images=()
    local used_disks
    local unused_count=0
    local used_count=0
    local unused_images=()
    
    print_color $BLUE "=== VM Disk Image Usage Checker ==="
    echo
    
    # Check privileges
    check_privileges "$@"
    
    # Check if virsh is available
    check_virsh
    
    # Determine search paths
    if [[ -n "$SEARCH_PATH" ]]; then
        if [[ ! -d "$SEARCH_PATH" ]]; then
            print_color $RED "Error: Directory '$SEARCH_PATH' does not exist."
            exit 1
        fi
        search_paths=("$SEARCH_PATH")
    else
        search_paths=("${DEFAULT_SEARCH_PATHS[@]}")
        print_color $YELLOW "No search path specified. Searching in default locations..."
    fi
    
    # Find all disk image files
    print_color $BLUE "Searching for VM disk image files..."
    for path in "${search_paths[@]}"; do
        if [[ -d "$path" ]]; then
            echo "Searching in: $path"
            while IFS= read -r file; do
                if [[ -n "$file" ]]; then
                    all_disk_images+=("$file")
                fi
            done < <(find_disk_images "$path")
        fi
    done
    
    if [[ ${#all_disk_images[@]} -eq 0 ]]; then
        print_color $YELLOW "No VM disk image files found in the specified locations."
        exit 0
    fi
    
    print_color $GREEN "Found ${#all_disk_images[@]} disk image files."
    echo
    
    # Get all disks currently used by VMs
    print_color $BLUE "Getting disks currently used by VMs..."
    used_disks=$(get_vm_disks)
    
    # Analyze each disk image
    print_color $BLUE "Analyzing disk usage..."
    echo
    printf "%-8s %-60s %-12s %-20s %-s\n" "STATUS" "DISK PATH" "SIZE" "MODIFIED" "USED BY VMs"
    printf "%-8s %-60s %-12s %-20s %-s\n" "--------" "------------------------------------------------------------" "------------" "--------------------" "-------------"
    
    for disk_image in "${all_disk_images[@]}"; do
        local size
        local mtime
        local status_text
        local status_color
        local vms_using
        
        size=$(get_file_size "$disk_image")
        mtime=$(get_file_mtime "$disk_image")
        
        if is_disk_used "$disk_image" "$used_disks"; then
            status_text="USED"
            status_color=$GREEN
            vms_using=$(get_vms_using_disk "$disk_image" | tr '\n' ',' | sed 's/,$//')
            ((used_count++))
        else
            status_text="UNUSED"
            status_color=$RED
            vms_using="-"
            unused_images+=("$disk_image")
            ((unused_count++))
        fi
        
        # Print the row with proper color formatting
        echo -e "${status_color}$(printf "%-8s" "$status_text")${NC} $(printf "%-60s %-12s %-20s %-s" "$disk_image" "$size" "$mtime" "$vms_using")"
    done
    
    echo
    print_color $BLUE "=== Summary ==="
    print_color $GREEN "Used disk images: $used_count"
    print_color $RED "Unused disk images: $unused_count"
    print_color $BLUE "Total disk images: ${#all_disk_images[@]}"
    
    if [[ $unused_count -gt 0 ]]; then
        echo
        print_color $YELLOW "Warning: Found $unused_count unused disk image(s)."
        print_color $YELLOW "Consider reviewing and removing unused disk images to free up space."
        
        if [[ "$DELETE_MODE" == true ]]; then
            delete_unused_images "${unused_images[@]}"
        fi
    fi
}

# Show usage information
show_usage() {
    echo "Usage: sudo $0 [OPTIONS] [search_path]"
    echo
    echo "Find VM disk image files and check if they're used by VMs using virsh."
    echo "Note: Requires sudo to access system libvirt directories and run virsh commands."
    echo
    echo "Options:"
    echo "  --delete       Delete unused disk images."
    echo "  --dry-run      Show what would be deleted without actually deleting."
    echo "  -h, --help     Show this help message."
    echo
    echo "Arguments:"
    echo "  search_path    Optional. Directory to search for disk images."
    echo "                 If not provided, searches in default locations:"
    for path in "${DEFAULT_SEARCH_PATHS[@]}"; do
        echo "                   - $path"
    done
    echo
    echo "Examples:"
    echo "  sudo $0                                    # Search in default locations"
    echo "  sudo $0 /var/lib/libvirt/images           # Search in specific directory"
    echo "  sudo $0 --delete                          # Delete unused disk images"
    echo "  sudo $0 --dry-run                         # Dry run mode"
    echo "  sudo $0 --delete /home/user/vm-images     # Delete unused images in custom directory"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --delete)
            DELETE_MODE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            if [[ -z "$SEARCH_PATH" ]]; then
                SEARCH_PATH="$1"
            else
                print_color $RED "Error: Unknown argument or multiple search paths specified: $1"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Run main function
main