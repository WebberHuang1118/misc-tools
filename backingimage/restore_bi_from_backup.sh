#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="longhorn-system"
DRYRUN=false

# Parse args
if [[ "$1" == "--dry-run" ]]; then
  DRYRUN=true
  BACKING_IMAGE_NAME="$2"
else
  BACKING_IMAGE_NAME="$1"
fi

if [ -z "$BACKING_IMAGE_NAME" ]; then
  echo "Usage: $0 [--dry-run] <backing-image-name>"
  exit 1
fi

echo "🔍 Checking BackingImage: $BACKING_IMAGE_NAME"
$DRYRUN && echo "🧪 Dry-run mode enabled — no changes will be made."

# Get the BackingImage
BI_JSON=$(kubectl get backingimages.longhorn.io "$BACKING_IMAGE_NAME" -n "$NAMESPACE" -o json)

# Check for valid replicas
DISK_STATUS=$(echo "$BI_JSON" | jq -r '.status.diskFileStatusMap // {}')
READY_COUNT=$(echo "$DISK_STATUS" | jq '[to_entries[] | select(.value.state == "ready")] | length')

if [ "$READY_COUNT" -gt 0 ]; then
  echo "✅ BackingImage has at least one valid replica. No action needed."
  exit 0
fi

echo "⚠️  No valid replica found for $BACKING_IMAGE_NAME"

# Check for BackupBackingImage
BBI_JSON=$(kubectl get backupbackingimages.longhorn.io "$BACKING_IMAGE_NAME" -n "$NAMESPACE" -o json)

BBI_STATE=$(echo "$BBI_JSON" | jq -r '.status.state')
BBI_URL=$(echo "$BBI_JSON" | jq -r '.status.url')
BBI_CHECKSUM=$(echo "$BBI_JSON" | jq -r '.status.checksum // empty')

if [[ "${BBI_STATE,,}" != "completed" ]]; then
  echo "❌ BackupBackingImage exists but is not in 'completed' state (state = $BBI_STATE)"
  exit 1
fi

echo "✅ BackupBackingImage is completed."

# Simulate or perform finalizer removal
if $DRYRUN; then
  echo "🧪 Would remove finalizer from BackingImage $BACKING_IMAGE_NAME"
else
  echo "🧹 Removing finalizer from BackingImage..."
  kubectl patch backingimages.longhorn.io "$BACKING_IMAGE_NAME" -n "$NAMESPACE" \
    --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
fi

# Simulate or perform deletion
if $DRYRUN; then
  echo "🧪 Would delete BackingImage $BACKING_IMAGE_NAME"
else
  echo "🗑️  Deleting old BackingImage..."
  kubectl delete backingimages.longhorn.io "$BACKING_IMAGE_NAME" -n "$NAMESPACE" --ignore-not-found
fi

# Prepare new BI manifest
echo "♻️  Recreate BackingImage from backup with:"
echo "  Name: $BACKING_IMAGE_NAME"
echo "  URL: $BBI_URL"
echo "  Checksum: $BBI_CHECKSUM"

cat <<EOF
---
apiVersion: longhorn.io/v1beta2
kind: BackingImage
metadata:
  name: $BACKING_IMAGE_NAME
  namespace: $NAMESPACE
spec:
  sourceType: restore
  sourceParameters:
    backup-url: $BBI_URL
    concurrent-limit: "2"
  checksum: $BBI_CHECKSUM
---
EOF

# Apply if not dry run
if ! $DRYRUN; then
  echo "🚀 Applying new BackingImage CR..."
  cat <<EOF | kubectl apply -f -
apiVersion: longhorn.io/v1beta2
kind: BackingImage
metadata:
  name: $BACKING_IMAGE_NAME
  namespace: $NAMESPACE
spec:
  sourceType: restore
  sourceParameters:
    backup-url: $BBI_URL
    concurrent-limit: "2"
  checksum: $BBI_CHECKSUM
EOF
  echo "✅ BackingImage $BACKING_IMAGE_NAME has been re-created from backup."
else
  echo "✅ Dry-run complete."
fi
