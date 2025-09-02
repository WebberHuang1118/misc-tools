# BackingImage Tools

This directory contains utilities for managing Longhorn BackingImages and BackupBackingImages.

## Scripts Overview

### create_bi_bbi_cycle.sh
A comprehensive script that creates and manages BackingImage and BackupBackingImage CRs in a continuous cycle. This is useful for testing backup/restore functionality and monitoring system behavior under continuous operation.

#### Features
- Creates BackingImage CRs with configurable parameters
- Waits for BackingImage to become ready (at least one disk ready)
- Creates BackupBackingImage CRs for backup operations
- Monitors backup completion with configurable timeouts
- Automatic cleanup between cycles
- Detailed logging with color-coded output
- Statistics tracking and reporting
- Signal handling for graceful termination

#### Usage
```bash
# Basic usage with defaults
./create_bi_bbi_cycle.sh

# With custom BackingImage name
./create_bi_bbi_cycle.sh --bi-name my-custom-image

# With custom backing image URL
./create_bi_bbi_cycle.sh --backing-image-url https://example.com/image.img

# With specific kubeconfig
./create_bi_bbi_cycle.sh /home/ubuntu/.kube/config

# Full customization
./create_bi_bbi_cycle.sh --bi-name test-image --backing-image-url https://example.com/test.img /path/to/kubeconfig

# Using environment variables
BI_NAME=env-image BACKING_IMAGE_URL=https://example.com/env.img ./create_bi_bbi_cycle.sh
```

#### Configuration Options
- `--bi-name NAME`: Name for the BackingImage (default: bi-noble)
- `--backing-image-url URL`: URL for the backing image (default: Ubuntu Noble ARM64 cloud image)
- `KUBECONFIG_PATH`: Path to kubeconfig file (positional argument)

#### Environment Variables
- `KUBECONFIG`: Kubernetes configuration file path
- `BI_NAME`: BackingImage name (overridden by --bi-name)
- `BACKING_IMAGE_URL`: Backing image URL (overridden by --backing-image-url)

#### Default Values
- **BI_NAME**: `bi-noble`
- **BACKING_IMAGE_URL**: `https://cloud-images.ubuntu.com/noble/20250805/noble-server-cloudimg-arm64.img`
- **NAMESPACE**: `longhorn-system`
- **MIN_COPIES**: `3`
- **DATA_ENGINE**: `v1`

#### Timeouts
- **BI_READY_TIMEOUT**: 600 seconds (10 minutes) - Time to wait for BackingImage to be ready
- **BBI_TIMEOUT**: 600 seconds (10 minutes) - Overall timeout for BackupBackingImage operations
- **BBI_INPROGRESS_TIMEOUT**: 600 seconds (10 minutes) - Maximum time to stay in InProgress state

#### Output and Monitoring
The script provides:
- Real-time status updates with timestamps
- Color-coded logging (success, warning, error)
- Cycle completion statistics
- Resource cleanup information
- Final manifests for failed operations (for debugging)

#### Statistics Tracking
- Total runtime
- Successful cycles completed
- BackingImages created
- BackupBackingImages created
- BackupBackingImages completed
- Average cycle time

#### Error Handling
- On failure, resources are left for investigation
- Manifests are printed for debugging
- Graceful cleanup on script termination (Ctrl+C)
- Comprehensive timeout handling

### check_backingimage_mismatch.sh
Identifies BackingImages that have disks in status but not in spec, which can indicate configuration inconsistencies.

```bash
./check_backingimage_mismatch.sh
```

### find_non_full_ready_backingimage.sh
Finds BackingImages without valid replicas and shows associated BackupBackingImages and volume references.

```bash
./find_non_full_ready_backingimage.sh
```

### restore_bi_from_backup.sh
Restores a BackingImage from a BackupBackingImage when possible.

#### Usage
```bash
# Dry run to see what would be restored
./restore_bi_from_backup.sh --dry-run default-image-8jbpn

# Actually perform the restoration
./restore_bi_from_backup.sh default-image-8jbpn
```

## Dependencies

All scripts require:
- `kubectl` - Kubernetes command-line tool
- `jq` - JSON processor (required by create_bi_bbi_cycle.sh)
- Access to a Kubernetes cluster with Longhorn installed

## Common Use Cases

### Testing Backup/Restore Workflow
Use `create_bi_bbi_cycle.sh` to continuously test the backup creation process:
```bash
./create_bi_bbi_cycle.sh --bi-name test-cycle
```

### Troubleshooting BackingImage Issues
1. Check for mismatches: `./check_backingimage_mismatch.sh`
2. Find problematic BackingImages: `./find_non_full_ready_backingimage.sh`
3. Restore from backup if needed: `./restore_bi_from_backup.sh <backup-name>`

### Automated Testing
The cycle script is ideal for:
- Long-running stability tests
- Performance benchmarking
- Automated CI/CD testing pipelines
- Load testing backup systems

## Notes

- All scripts are designed to work with Longhorn's default namespace (`longhorn-system`)
- The cycle script includes comprehensive error handling and cleanup
- Scripts assume proper RBAC permissions for BackingImage and BackupBackingImage operations
- For production environments, consider adjusting timeout values based on your system's performance characteristics