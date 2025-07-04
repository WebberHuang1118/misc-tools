# Backup Scripts

This directory contains scripts for managing backups and monitoring NFS services in a Kubernetes environment.

## Scripts

### monitor_nfs_longhorn_twice.sh
This script monitors the logs of the `longhorn-manager` DaemonSet in the `longhorn-system` namespace for occurrences of the error message `Failed to get info from backup store`. If the error message appears twice, the script restarts the NFS service after a delay of 59 seconds.

#### Usage
1. Ensure you have `kubectl` installed and configured to access your Kubernetes cluster.
2. Run the script with appropriate permissions to manage the NFS service:
   ```bash
   ./monitor_nfs_longhorn_twice.sh
   ```

#### Key Features
- Stops the NFS service initially.
- Monitors logs for specific error messages.
- Restarts the NFS service if the error message appears twice.

### create_vm_backup_with_nfs_control.sh
This script automates the creation of `VirtualMachineBackup` custom resources (CRs) in a Kubernetes cluster. It also manages the NFS service during the backup process.

#### Usage
1. Ensure you have `kubectl` installed and configured to access your Kubernetes cluster.
2. Run the script with appropriate permissions to manage the NFS service:
   ```bash
   ./create_vm_backup_with_nfs_control.sh
   ```

#### Key Features
- Creates `VirtualMachineBackup` CRs with names from `1` to `4`.
- Waits for each backup to be ready or encounter an error before proceeding.
- Stops the NFS service after the second backup.
- Restarts the NFS service after the fourth backup.

### find-lh-backup-by-pvname.sh
This script retrieves information about Longhorn backups associated with a specific PersistentVolume (PV) in a Kubernetes cluster.

#### Usage
1. Ensure you have `kubectl` and `jq` installed and configured to access your Kubernetes cluster.
2. Run the script with the PV name as an argument:
   ```bash
   ./find-lh-backup-by-pvname.sh <PV_NAME>
   ```

#### Key Features
- Fetches Longhorn backup details such as name, creation time, state, and associated snapshot.
- Retrieves additional information about the snapshot and its VolumeSnapshotContent, including readiness and snapshot handle.

#### Example Output
```
Backup:
  Name:         backup-12345
  Created:      2025-05-23T10:00:00Z
  BackupTime:   2025-05-23T10:05:00Z
  State:        Ready
  Snapshot:
    Name:       snapshot-12345
    Created:    2025-05-23T09:55:00Z
    Ready:      true
  VolumeSnapshotContent:
    Name:           snapcontent-12345
    Namespace:      longhorn-system
    Snapshot:       snapshot-12345
    ReadyToUse:     true
    SnapshotHandle: snap-12345
```

## Prerequisites
- `kubectl` must be installed and configured.
- Sufficient permissions to manage the NFS service on the host system.

## Notes
- Ensure the NFS service is properly configured before running these scripts.
- These scripts are designed for specific use cases and may require modifications for other environments.