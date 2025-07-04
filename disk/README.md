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