#!/bin/bash

# Default configuration
DEFAULT_NUM_PVCS=100      # Default number of PVCs if not provided
PVCS_PER_POD=3            # Number of PVCs to attach to each pod
NAMESPACE="io-test"       # Namespace for the pods
DELAY_SECONDS=2           # Delay between pod creations
MAX_START_TIME=240        # Max time in seconds for a pod to transition to running (4 minutes)
MIN_RUNNING_RATE=10       # Minimum number of pods transitioning to running per minute
MAX_CRASHING_PODS=3       # Maximum allowed crashing pods or restarted containers

# Parse input arguments
NUM_PVCS=${1:-$DEFAULT_NUM_PVCS}

echo "Number of PVCs to create: $NUM_PVCS"

# Calculate the number of pods needed
NUM_PODS=$(( (NUM_PVCS + PVCS_PER_POD - 1) / PVCS_PER_POD ))
echo "Number of pods to create: $NUM_PODS"

# Create the namespace if it doesn't exist
kubectl create namespace $NAMESPACE || echo "Namespace $NAMESPACE already exists"

# Create PVCs
for i in $(seq 1 $NUM_PVCS); do
    PVC_NAME="pvc-$i"
    echo "Creating PVC $PVC_NAME..."
    cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
done

# Wait before creating pods to ensure PVCs are ready
echo "Waiting for PVCs to become available..."
sleep 5

# Create Pods
for i in $(seq 1 $NUM_PODS); do
    POD_NAME="io-pod-$i"
    START=$(( (i - 1) * PVCS_PER_POD + 1 ))
    END=$(( i * PVCS_PER_POD ))
    if [[ $END -gt $NUM_PVCS ]]; then
        END=$NUM_PVCS
    fi

    echo "Creating Pod $POD_NAME with PVCs from pvc-$START to pvc-$END..."

    # Generate volumes and mounts for the PVCs
    VOLUMES=""
    VOLUME_MOUNTS=""
    for j in $(seq $START $END); do
        PVC_NAME="pvc-$j"
        VOLUMES="${VOLUMES}
        - name: volume-$j
          persistentVolumeClaim:
            claimName: $PVC_NAME"
        VOLUME_MOUNTS="${VOLUME_MOUNTS}
        - mountPath: /data/volume-$j
          name: volume-$j"
    done

    # Create the Pod
    cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
spec:
  containers:
    - name: io-container
      image: busybox
      imagePullPolicy: IfNotPresent
      command: ["/bin/sh"]
      args:
        - "-c"
        - |
          while true; do
              for dir in /data/volume-*; do
                  echo \$(date) >> \$dir/io.log;
                  dd if=/dev/urandom of=\$dir/file bs=1M count=100;
              done
          done
      volumeMounts:
${VOLUME_MOUNTS}
  volumes:
${VOLUMES}
EOF

    echo "Pod $POD_NAME created. Waiting for $DELAY_SECONDS seconds..."
    sleep $DELAY_SECONDS
done

echo "All PVCs and Pods have been created. Verifying status..."

# Verify Pods and PVCs
kubectl get pods -n $NAMESPACE
kubectl get pvc -n $NAMESPACE
