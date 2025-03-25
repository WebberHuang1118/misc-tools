#!/usr/bin/env bash

NAMESPACE="longhorn-system"

echo "BackingImages with non-ready or missing diskFileStatusMap entries:"
echo

kubectl get backingimages.longhorn.io -n "$NAMESPACE" -o json | jq -c '
  .items[]
  | select(
      (.status.diskFileStatusMap == {} or .status.diskFileStatusMap == null)
      or any(.status.diskFileStatusMap[]?; .state != "ready")
    )
  | {
      name: .metadata.name,
      created: .metadata.creationTimestamp,
      sourceType: (.spec.sourceType // "N/A"),
      url: (if .spec.sourceType == "download" then .spec.sourceParameters.url // "N/A" else null end),
      checksum: (.status.checksum // "N/A"),
      diskMap: (.status.diskFileStatusMap // {}),
      states: (
        if (.status.diskFileStatusMap == {} or .status.diskFileStatusMap == null)
        then ["missing"]
        else [.status.diskFileStatusMap[]? | select(.state != "ready") | .state]
        end | unique
      )
    }
' | while read -r backing; do
  NAME=$(echo "$backing" | jq -r '.name')
  CREATED=$(echo "$backing" | jq -r '.created')
  TYPE=$(echo "$backing" | jq -r '.sourceType')
  URL=$(echo "$backing" | jq -r '.url // empty')
  CHECKSUM=$(echo "$backing" | jq -r '.checksum')
  STATES=$(echo "$backing" | jq -r '.states[]' | sed 's/^/    - /')

  echo "- BackingImage: $NAME"
  echo "  Created At: $CREATED"
  echo "  Source Type: $TYPE"
  if [ -n "$URL" ]; then
    echo "  URL: $URL"
  fi
  echo "  Checksum: $CHECKSUM"
  echo "  Problematic States:"
  echo "$STATES"

  echo "  Disk File Status Map:"
  echo "$backing" | jq -r '.diskMap | to_entries[] | "    - Disk: \(.key)\n      State: \(.value.state // "N/A")\n      Progress: \(.value.progress // "N/A")\n      Message: \(.value.message // "N/A")"'

  # Check for BackupBackingImage with same name
  BBI=$(kubectl get backupbackingimages.longhorn.io "$NAME" -n "$NAMESPACE" -o json 2>/dev/null)
  if [ -n "$BBI" ]; then
    BBI_NAME=$(echo "$BBI" | jq -r '.metadata.name')
    BBI_CREATED=$(echo "$BBI" | jq -r '.metadata.creationTimestamp')
    BBI_STATE=$(echo "$BBI" | jq -r '.status.state // "unknown"')
    BBI_CHECKSUM=$(echo "$BBI" | jq -r '.status.checksum // "N/A"')
    echo "  BackupBackingImage:"
    echo "    Name: $BBI_NAME"
    echo "    Created At: $BBI_CREATED"
    echo "    State: $BBI_STATE"
    echo "    Checksum: $BBI_CHECKSUM"
  fi

  # Find volumes using this backing image
  VOLUMES_JSON=$(kubectl get volumes.longhorn.io -n "$NAMESPACE" -o json)
  VOLUMES=$(echo "$VOLUMES_JSON" | jq -r --arg name "$NAME" '
    .items[]
    | select(.spec.backingImage == $name)
    | "    - Volume: \(.metadata.name)\n      State: \(.status.state // "unknown")\n      PVC: \(.status.kubernetesStatus.pvcName // "N/A")\n      Namespace: \(.status.kubernetesStatus.namespace // "N/A")"
  ')

  if [ -n "$VOLUMES" ]; then
    echo "  Used By Volumes:"
    echo "$VOLUMES"
  fi

  echo
done
