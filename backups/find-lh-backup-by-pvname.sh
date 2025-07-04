#!/bin/bash

set -euo pipefail

PV_NAME="$1"
NAMESPACE="longhorn-system"

kubectl get backup.longhorn.io -n "$NAMESPACE" -o json | jq -r --arg pv "$PV_NAME" '
  .items[]
  | {
      name: .metadata.name,
      createdAt: (.metadata.creationTimestamp // "N/A"),
      backupCreatedAt: (.status.backupCreatedAt // "N/A"),
      state: (.status.state // "N/A"),
      snapshotName: (.status.snapshotName // ""),
      volumeName: (.status.volumeName // ""),
      kstatus: (.spec.labels.KubernetesStatus // "")
    }
  | select(
      try (.kstatus | fromjson | .pvName == $pv) catch false
    )
  | [.name, .createdAt, .backupCreatedAt, .state, .snapshotName, .volumeName]
  | @tsv
' | while IFS=$'\t' read -r name createdAt backupCreatedAt state snapshotName volumeName; do

  echo "Backup:"
  printf "  Name:         %s\n" "$name"
  printf "  Created:      %s\n" "$createdAt"
  printf "  BackupTime:   %s\n" "$backupCreatedAt"
  printf "  State:        %s\n" "$state"
  echo "  Snapshot:"
  printf "    Name:       %s\n" "$snapshotName"

  snapCreated="N/A"
  snapReady="N/A"

  if [[ -n "$snapshotName" ]]; then
    SNAP_JSON=$(kubectl get snapshots.longhorn.io "$snapshotName" -n "$NAMESPACE" -o json 2>/dev/null || true)
    if [[ -n "$SNAP_JSON" && "$SNAP_JSON" != "null" ]]; then
      tmpCreated=$(echo "$SNAP_JSON" | jq -r '.status.creationTime // .metadata.creationTimestamp // empty')
      tmpReady=$(echo "$SNAP_JSON" | jq -r '.status.readyToUse // empty')
      if [[ -n "$tmpCreated" ]]; then snapCreated="$tmpCreated"; fi
      if [[ -n "$tmpReady" ]]; then snapReady="$tmpReady"; fi
    fi
  fi

  printf "    Created:    %s\n" "$snapCreated"
  printf "    Ready:      %s\n" "$snapReady"

  # ---- Volumesnapshotcontent block ----
  vsc_name=""
  if [[ -n "$snapshotName" ]]; then
    vsc_name="snapcontent-${snapshotName#snapshot-}"
    VSC_JSON=$(kubectl get volumesnapshotcontents.snapshot.storage.k8s.io "$vsc_name" -o json 2>/dev/null || true)
    vsc_ns="N/A"
    vsc_snap="N/A"
    vsc_ready="N/A"
    vsc_handle="N/A"
    if [[ -n "$VSC_JSON" && "$VSC_JSON" != "null" ]]; then
      vsc_ns=$(echo "$VSC_JSON" | jq -r '.spec.volumeSnapshotRef.namespace // "N/A"')
      vsc_snap=$(echo "$VSC_JSON" | jq -r '.spec.volumeSnapshotRef.name // "N/A"')
      vsc_ready=$(echo "$VSC_JSON" | jq -r '.status.readyToUse // "N/A"')
      vsc_handle=$(echo "$VSC_JSON" | jq -r '.status.snapshotHandle // "N/A"')
    fi
    echo "  VolumeSnapshotContent:"
    printf "    Name:           %s\n" "$vsc_name"
    printf "    Namespace:      %s\n" "$vsc_ns"
    printf "    Snapshot:       %s\n" "$vsc_snap"
    printf "    ReadyToUse:     %s\n" "$vsc_ready"
    printf "    SnapshotHandle: %s\n" "$vsc_handle"
  fi

  echo ""

done
