# attach-disk.sh
This script creates a QEMU image and attaches it to a Vagrant (libvirt) VM. It performs the following tasks:

1. Attaches a `virtio-scsi` controller to the domain if the domain doesn't already have one.
2. Creates a `qcow2` disk image under a specified directory and attaches it to the provided domain.
3. Generates an XML configuration for the disk and attaches it to the VM.

Dependencies:
- `qemu-img`
- `virsh`

Usage:
```bash
./attach-disk.sh <VM name> <Target device> <disk size (GB)> [WWN]
```

- `<VM name>`: The name of the target VM.
- `<Target device>`: The target device (e.g., `sdc`).
- `<disk size (GB)>`: The size of the disk in GB.
- `[WWN]`: (Optional) The World Wide Name for the disk. If not provided, a random WWN will be generated.

Example:
```bash
./attach-disk.sh vagrant-pxe-harvester_harvester-node-0 sdc 10
```

# find_vm_disk_usage.sh
This script finds VM disk image files and checks whether they are currently used by VMs using virsh. It helps identify unused disk images that may be consuming storage space and can optionally delete them.

**Note: This script requires sudo privileges to access system libvirt directories and run virsh commands properly.**

Features:
- Searches for common VM disk image formats (qcow2, qcow, img, raw, vmdk, vdi, vhd, vhdx)
- Checks if disk images are currently attached to any VM (running or stopped)
- Shows file size, modification date, and which VMs are using each disk
- Provides colored output for easy identification of used vs unused disks
- Supports both default search locations and custom directories
- Warns when running without sufficient privileges
- **NEW: Delete mode to remove unused disk images**
- **NEW: Dry-run mode to preview what would be deleted**

Dependencies:
- `virsh`
- `find`
- `awk`
- `du`
- `stat`
- `sudo` (for accessing system directories)
- `numfmt` (for human-readable size calculations)

Usage:
```bash
sudo ./find_vm_disk_usage.sh [OPTIONS] [search_path]
```

Options:
- `--delete`: Delete unused disk images after confirmation
- `--dry-run`: Show what would be deleted without actually deleting (can be combined with --delete)
- `-h, --help`: Show help message

Arguments:
- `[search_path]`: Optional. Directory to search for disk images. If not provided, searches in default locations:
  - `/var/lib/libvirt/images`
  - `/var/lib/libvirt/qemu`
  - `/opt/vm-images`
  - `/home/*/VirtualMachines`
  - `/home/*/.local/share/libvirt/images`
  - `/tmp`

Examples:
```bash
# Basic usage - just analyze disk usage
sudo ./find_vm_disk_usage.sh                      # Search in default locations
sudo ./find_vm_disk_usage.sh /var/lib/libvirt/images  # Search in specific directory

# Delete mode examples
sudo ./find_vm_disk_usage.sh --delete             # Delete unused images with confirmation
sudo ./find_vm_disk_usage.sh --dry-run            # Preview what would be deleted
sudo ./find_vm_disk_usage.sh --delete --dry-run   # Dry-run mode for deletion
sudo ./find_vm_disk_usage.sh --delete /home/user/vm-images  # Delete in custom directory
```

## Delete Mode Features:

**Dry-run Mode (`--dry-run`):**
- Shows exactly which files would be deleted
- Calculates total space that would be freed
- No actual deletion occurs
- Safe to run anytime for analysis

**Delete Mode (`--delete`):**
- Lists all unused disk images to be deleted
- Shows total space to be freed
- Requires explicit confirmation (type "yes" to proceed)
- Provides detailed deletion progress and results
- Cannot be undone - use dry-run first for safety

**Safety Features:**
- Requires explicit "yes" confirmation before deletion
- Shows file sizes and total space to be freed
- Provides detailed success/failure feedback
- Only deletes files confirmed as unused by virsh analysis

Output includes:
- Status (USED/UNUSED) with color coding
- Full path to disk image file
- File size in human-readable format
- Last modification time
- List of VMs using the disk (if any)
- Summary with counts of used/unused disk images
- In delete mode: detailed deletion results and space freed

# find_evict_disks.sh
This script checks for Longhorn nodes and disks marked for eviction. It outputs:

1. A list of Longhorn nodes with `evictionRequested` set to `true`.
2. A table of disks with `evictionRequested` set to `true`, showing the node, disk, and path.

Dependencies:
- `kubectl`
- `jq`
- `column`

Usage:
Run the script directly:
```bash
./find_evict_disks.sh
```