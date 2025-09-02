#!/bin/bash

# Script to create and manage BackingImage and BackupBackingImage CRs in a continuous cycle
# Usage: ./create_bi_bbi_cycle.sh [KUBECONFIG_PATH]
# Example: ./create_bi_bbi_cycle.sh /home/ubuntu/.kube/arm.yaml

set -e

# Function to show usage
show_usage() {
    echo "Usage: $0 [KUBECONFIG_PATH]"
    echo ""
    echo "Arguments:"
    echo "  KUBECONFIG_PATH    Path to the kubeconfig file (optional)"
    echo ""
    echo "Environment Variables:"
    echo "  KUBECONFIG         Can also be set via environment variable"
    echo ""
    echo "Examples:"
    echo "  $0 /home/ubuntu/.kube/arm.yaml"
    echo "  KUBECONFIG=/home/ubuntu/.kube/arm.yaml $0"
    echo ""
    echo "If no KUBECONFIG is specified, kubectl will use its default configuration."
}

# Parse command line arguments
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

# Set KUBECONFIG for kubectl authentication
if [ -n "$1" ]; then
    # Use command line argument if provided
    export KUBECONFIG="$1"
    echo "Using KUBECONFIG from argument: $KUBECONFIG"
elif [ -n "$KUBECONFIG" ]; then
    # Use environment variable if already set
    echo "Using KUBECONFIG from environment: $KUBECONFIG"
else
    # Use default if neither provided
    echo "No KUBECONFIG specified, using kubectl default configuration"
fi

# Verify KUBECONFIG file exists if specified
if [ -n "$KUBECONFIG" ] && [ ! -f "$KUBECONFIG" ]; then
    echo "Error: KUBECONFIG file not found: $KUBECONFIG"
    exit 1
fi

# Configuration
BI_NAME="bi-noble"
BBI_NAME_PREFIX="bi-noble"
NAMESPACE="longhorn-system"
BACKING_IMAGE_URL="https://cloud-images.ubuntu.com/noble/20250805/noble-server-cloudimg-arm64.img"
BACKUP_TARGET_NAME="default"
MIN_COPIES=3
DATA_ENGINE="v1"

# Cycle tracking variables
CYCLE_START_TIME=$(date +%s)
TOTAL_CYCLES_COMPLETED=0
TOTAL_BI_CREATED=0
TOTAL_BBI_CREATED=0
TOTAL_BBI_COMPLETED=0

# Timeout configurations (in seconds)
BI_READY_TIMEOUT=600    # 10 minutes
BBI_TIMEOUT=600         # 10 minutes for completion or error
BBI_INPROGRESS_TIMEOUT=600  # 10 minutes for InProgress state

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Function to create BackingImage CR
create_bi() {
    log "Creating BackingImage CR: $BI_NAME"

    cat <<EOF | kubectl apply -f -
apiVersion: longhorn.io/v1beta2
kind: BackingImage
metadata:
  name: $BI_NAME
  namespace: $NAMESPACE
  labels:
    longhorn.io/component: backing-image
    longhorn.io/managed-by: longhorn-manager
spec:
  checksum: ""
  dataEngine: $DATA_ENGINE
  diskSelector: []
  disks: {}
  minNumberOfCopies: $MIN_COPIES
  nodeSelector: []
  secret: ""
  secretNamespace: ""
  sourceParameters:
    url: $BACKING_IMAGE_URL
  sourceType: download
EOF

    if [ $? -eq 0 ]; then
        log_success "BackingImage CR created successfully"
        TOTAL_BI_CREATED=$((TOTAL_BI_CREATED + 1))
    else
        log_error "Failed to create BackingImage CR"
        return 1
    fi
}

# Function to wait for BackingImage to have at least one ready disk
wait_for_bi_ready() {
    log "Waiting for BackingImage to have at least one disk with state=ready..."

    local start_time=$(date +%s)
    local timeout=$BI_READY_TIMEOUT

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ $elapsed -gt $timeout ]; then
            log_error "Timeout waiting for BackingImage to be ready (${timeout}s)"
            return 1
        fi

        # Check if BI exists and has ready disks
        local ready_disks=$(kubectl get backingimage $BI_NAME -n $NAMESPACE -o jsonpath='{.status.diskFileStatusMap}' 2>/dev/null || echo "")

        if [ -n "$ready_disks" ]; then
            # Parse the diskFileStatusMap to check for ready state
            local has_ready=$(kubectl get backingimage $BI_NAME -n $NAMESPACE -o json 2>/dev/null | jq -r '.status.diskFileStatusMap // {} | to_entries[] | select(.value.state == "ready") | .key' | head -1)

            if [ -n "$has_ready" ]; then
                log_success "BackingImage has at least one disk ready: $has_ready"
                return 0
            fi
        fi

        log "Waiting for BackingImage to be ready... (elapsed: ${elapsed}s)"
        sleep 3
    done
}

# Function to create BackupBackingImage CR
create_bbi() {
    # Generate a unique suffix for BBI name
    local timestamp=$(date +%s)
    local suffix=$(echo -n "$timestamp" | tail -c 8)
    local bbi_name="${BBI_NAME_PREFIX}-${suffix}"

    log "Creating BackupBackingImage CR: $bbi_name"

    cat <<EOF | kubectl apply -f -
apiVersion: longhorn.io/v1beta2
kind: BackupBackingImage
metadata:
  name: $bbi_name
  namespace: $NAMESPACE
  labels:
    backing-image: $BI_NAME
    backup-target: $BACKUP_TARGET_NAME
spec:
  backingImage: $BI_NAME
  backupTargetName: $BACKUP_TARGET_NAME
  syncRequestedAt: null
  userCreated: true
EOF

    if [ $? -eq 0 ]; then
        log_success "BackupBackingImage CR created successfully: $bbi_name"
        TOTAL_BBI_CREATED=$((TOTAL_BBI_CREATED + 1))
        # Store the BBI name in a global variable to avoid output conflicts
        CREATED_BBI_NAME="$bbi_name"
        return 0
    else
        log_error "Failed to create BackupBackingImage CR"
        return 1
    fi
}

# Function to wait for BBI completion, error, or timeout
wait_for_bbi_completion() {
    local bbi_name=$1
    log "Waiting for BackupBackingImage completion: $bbi_name"

    local start_time=$(date +%s)
    local inprogress_start_time=0

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        # Get BBI status with better error handling
        local bbi_state=""
        if kubectl get backupbackingimage $bbi_name -n $NAMESPACE >/dev/null 2>&1; then
            bbi_state=$(kubectl get backupbackingimage $bbi_name -n $NAMESPACE -o jsonpath='{.status.state}' 2>/dev/null || echo "")
        fi

        if [ -z "$bbi_state" ]; then
            # Check if BBI exists but status is not yet available
            if kubectl get backupbackingimage $bbi_name -n $NAMESPACE >/dev/null 2>&1; then
                log "BackupBackingImage exists but status not yet available, waiting..."
            else
                log_warning "BackupBackingImage not found: $bbi_name"
            fi
            sleep 3
            continue
        fi

        log "BackupBackingImage state: $bbi_state (elapsed: ${elapsed}s)"

        case "$bbi_state" in
            "Completed")
                log_success "BackupBackingImage completed successfully"
                TOTAL_BBI_COMPLETED=$((TOTAL_BBI_COMPLETED + 1))
                return 0
                ;;
            "Error")
                log_error "BackupBackingImage failed with error state"
                return 1
                ;;
            "InProgress")
                # Track how long it's been in InProgress
                if [ $inprogress_start_time -eq 0 ]; then
                    inprogress_start_time=$current_time
                fi

                local inprogress_elapsed=$((current_time - inprogress_start_time))
                if [ $inprogress_elapsed -gt $BBI_INPROGRESS_TIMEOUT ]; then
                    log_error "BackupBackingImage stuck in InProgress for more than ${BBI_INPROGRESS_TIMEOUT}s"
                    return 1
                fi
                ;;
            *)
                # Reset InProgress timer for other states
                inprogress_start_time=0
                ;;
        esac

        # Overall timeout check
        if [ $elapsed -gt $BBI_TIMEOUT ]; then
            log_error "Overall timeout waiting for BackupBackingImage (${BBI_TIMEOUT}s)"
            return 1
        fi

        sleep 3
    done
}

# Function to cleanup resources
cleanup_resources() {
    local bbi_name=$1

    log "Cleaning up resources..."

    # Delete BBI
    if kubectl get backupbackingimage $bbi_name -n $NAMESPACE >/dev/null 2>&1; then
        log "Deleting BackupBackingImage: $bbi_name"
        kubectl delete backupbackingimage $bbi_name -n $NAMESPACE
    fi

    # Delete BI
    if kubectl get backingimage $BI_NAME -n $NAMESPACE >/dev/null 2>&1; then
        log "Deleting BackingImage: $BI_NAME"
        kubectl delete backingimage $BI_NAME -n $NAMESPACE
    fi

    # Wait a bit for cleanup
    log "Waiting for cleanup to complete..."
    sleep 10
}

# Function to display cycle statistics
show_cycle_summary() {
    local current_time=$(date +%s)
    local total_runtime=$((current_time - CYCLE_START_TIME))
    local hours=$((total_runtime / 3600))
    local minutes=$(((total_runtime % 3600) / 60))
    local seconds=$((total_runtime % 60))

    echo
    log_success "==================== CYCLE SUMMARY ===================="
    log_success "Total Runtime: ${hours}h ${minutes}m ${seconds}s"
    log_success "Successful Cycles Completed: $TOTAL_CYCLES_COMPLETED"
    log_success "BackingImages Created: $TOTAL_BI_CREATED"
    log_success "BackupBackingImages Created: $TOTAL_BBI_CREATED"
    log_success "BackupBackingImages Completed: $TOTAL_BBI_COMPLETED"

    if [ $TOTAL_CYCLES_COMPLETED -gt 0 ]; then
        local avg_cycle_time=$((total_runtime / TOTAL_CYCLES_COMPLETED))
        local avg_minutes=$((avg_cycle_time / 60))
        local avg_seconds=$((avg_cycle_time % 60))
        log_success "Average Cycle Time: ${avg_minutes}m ${avg_seconds}s"
    fi

    log_success "========================================================"
    echo
}

# Function to handle script termination
cleanup_and_exit() {
    log_warning "Script interrupted. Performing cleanup..."

    # Show final summary
    show_cycle_summary

    # Try to cleanup any existing resources
    local existing_bbi=$(kubectl get backupbackingimage -n $NAMESPACE -l backing-image=$BI_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$existing_bbi" ]; then
        cleanup_resources "$existing_bbi"
    else
        # Just cleanup BI if no BBI found
        if kubectl get backingimage $BI_NAME -n $NAMESPACE >/dev/null 2>&1; then
            kubectl delete backingimage $BI_NAME -n $NAMESPACE
        fi
    fi

    exit 1
}

# Set up signal handlers
trap cleanup_and_exit SIGINT SIGTERM

# Main execution loop
main() {
    log "Starting BackingImage and BackupBackingImage cycle script"
    log "BI Name: $BI_NAME"
    log "Namespace: $NAMESPACE"
    log "Backing Image URL: $BACKING_IMAGE_URL"
    log "Backup Target: $BACKUP_TARGET_NAME"
    echo

    local cycle_count=1

    while true; do
        log_success "=== Starting Cycle $cycle_count ==="

        # Step 1: Create BackingImage CR
        if ! create_bi; then
            log_error "Failed to create BackingImage. Terminating."
            exit 1
        fi

        # Step 2: Wait for BI to have at least one ready disk
        if ! wait_for_bi_ready; then
            log_error "BackingImage failed to become ready. Terminating."
            exit 1
        fi

        # Add a brief delay to ensure BackingImage is fully stable before creating BBI
        log "Waiting 3 seconds before creating BackupBackingImage..."
        sleep 3

        # Step 3: Create BackupBackingImage CR
        if create_bbi; then
            local bbi_name="$CREATED_BBI_NAME"
        else
            log_error "Failed to create BackupBackingImage. Terminating."
            exit 1
        fi

        # Step 4: Wait for BBI completion or failure
        if wait_for_bbi_completion "$bbi_name"; then
            # Step 5: If BBI completed, cleanup and restart cycle
            log_success "Cycle $cycle_count completed successfully!"
            cleanup_resources "$bbi_name"
            cycle_count=$((cycle_count + 1))
            TOTAL_CYCLES_COMPLETED=$((TOTAL_CYCLES_COMPLETED + 1))

            # Show summary every 5 cycles or on first cycle
            if [ $TOTAL_CYCLES_COMPLETED -eq 1 ] || [ $((TOTAL_CYCLES_COMPLETED % 5)) -eq 0 ]; then
                show_cycle_summary
            fi

            log "Preparing for next cycle..."
            sleep 10
        else
            # Step 6: If BBI failed or timed out, terminate WITHOUT cleanup
            log_error "BackupBackingImage failed or timed out. Terminating script."

            # Show final summary before exit
            show_cycle_summary

            log_warning "Leaving resources for investigation:"
            log_warning "  BackingImage: $BI_NAME"
            log_warning "  BackupBackingImage: $bbi_name"

            # Print manifests for investigation
            echo
            log_warning "==================== RESOURCE MANIFESTS FOR INVESTIGATION ===================="

            log_warning "BackingImage manifest:"
            echo "---"
            kubectl get backingimage $BI_NAME -n $NAMESPACE -o yaml 2>/dev/null || log_error "Failed to get BackingImage manifest"

            echo
            log_warning "BackupBackingImage manifest:"
            echo "---"
            kubectl get backupbackingimage $bbi_name -n $NAMESPACE -o yaml 2>/dev/null || log_error "Failed to get BackupBackingImage manifest"

            log_warning "============================================================================="
            echo

            exit 1
        fi
    done
}

# Check dependencies
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is required but not installed"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed"
    exit 1
fi

# Run main function
main