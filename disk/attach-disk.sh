#!/bin/bash
# The script creates a QEMU image and attaches it to a Vagrant (libvirt) VM.
#
# What the script does:
# (1) It attaches a virtio-scsi controller to a domain if the domain doesn't have a controller yet.
# (2) Create a qcow2 file under $DISKS_DIR and attach it to the provided domain.
#
# Although we could not detect the next device automatically, now it is easy to use.
#
# Usage: ./attach-disk.sh <VM name> <Target device> <disk size (GB)>
#

if [[ $# < 3 ]]
then
        echo "Usage: ./attach-disk.sh <VM name> <Target device> <disk size (GB)> <WWN>"
        echo "You can skip WWN but the example WWN would be 0x5000c50017654321"
        exit 1
fi

TARGET_VM=$1
TARGET_DEVICE=$2
DISK_SIZE=$3
DISK_WWN=$4
DISK_NAME=$TARGET_VM-$TARGET_DEVICE
: ${DISKS_DIR:=/home/webber/libvirt_disks}

if [ -z $DISK_WWN ]; then
        DISK_WWN=0x5000c50015$(date +%s | sha512sum | head -c 6)
        echo "WWN does not config, use random one ${DISK_WWN}"
fi

# create disk image
mkdir -p $DISKS_DIR
FILE=$DISKS_DIR/$DISK_NAME.qcow2

# Check if disk image already exists
if [ -f "$FILE" ]; then
    echo "Warning: Disk image $FILE already exists"
    read -p "Do you want to remove it and create a new one? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$FILE"
        echo "Removed existing disk image"
    else
        echo "Using existing disk image"
    fi
fi

# Create disk image only if it doesn't exist
if [ ! -f "$FILE" ]; then
    qemu-img create -f qcow2 $FILE "${DISK_SIZE}"g
fi

# Check if virtio-scsi controller exists, if not find next available index
CONTROLLER_INDEX=0
VM_XML=$(virsh dumpxml $TARGET_VM)

# Check if target device already exists
if echo "$VM_XML" | grep -q "target dev='$TARGET_DEVICE'"; then
    echo "Error: Target device $TARGET_DEVICE already exists in VM $TARGET_VM"
    echo "Existing devices:"
    echo "$VM_XML" | grep "target dev=" | sed -n "s/.*target dev='\([^']*\)'.*/\1/p" | sort
    echo "Please choose a different target device name"
    exit 1
fi

if echo "$VM_XML" | grep -q "controller type='scsi'.*model='virtio-scsi'"; then
    echo "virtio-scsi controller already exists"
    CONTROLLER_INDEX=$(echo "$VM_XML" | grep "controller type='scsi'.*model='virtio-scsi'" | sed -n "s/.*index='\([0-9]*\)'.*/\1/p")
else
    # Find next available controller index
    EXISTING_INDICES=$(echo "$VM_XML" | grep "controller type='scsi'" | sed -n "s/.*index='\([0-9]*\)'.*/\1/p" | sort -n)
    for i in {0..15}; do
        if ! echo "$EXISTING_INDICES" | grep -q "^$i$"; then
            CONTROLLER_INDEX=$i
            break
        fi
    done
    
    echo "Attach virtio-scsi controller to $TARGET_VM at index $CONTROLLER_INDEX"
    CONTROLLER_XML=controller.xml
    cat > $CONTROLLER_XML << EOF
    <controller type='scsi' model='virtio-scsi' index='$CONTROLLER_INDEX'/>
EOF
    
    if ! virsh attach-device --domain $TARGET_VM --file $CONTROLLER_XML --live; then
        echo "Failed to attach controller, but continuing with disk attachment..."
    fi
fi

# Find next available unit number for the controller
USED_UNITS=$(echo "$VM_XML" | grep "controller='$CONTROLLER_INDEX'" | sed -n "s/.*unit='\([0-9]*\)'.*/\1/p" | sort -n)
UNIT=0
for i in {0..15}; do
    if ! echo "$USED_UNITS" | grep -q "^$i$"; then
        UNIT=$i
        break
    fi
done

# attach device
XML_FILE=$DISKS_DIR/$DISK_NAME.xml
cat > $XML_FILE <<EOF
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='$FILE'/>
      <target dev='$TARGET_DEVICE' bus='scsi'/>
      <wwn>$DISK_WWN</wwn>
      <address type='drive' controller='$CONTROLLER_INDEX' bus='0' target='0' unit='$UNIT'/>
    </disk>
EOF

echo "Attaching disk to controller index $CONTROLLER_INDEX, unit $UNIT"
if virsh attach-device --domain $TARGET_VM --file $XML_FILE --persistent; then
    echo "Disk attached successfully!"
    echo "You may need to rescan SCSI devices in the guest OS:"
    echo "  echo '- - -' > /sys/class/scsi_host/host*/scan"
else
    echo "Failed to attach disk"
    exit 1
fi
