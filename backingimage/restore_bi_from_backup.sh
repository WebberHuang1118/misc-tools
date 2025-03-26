#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="longhorn-system"
DRYRUN=false

# Parse args
if [[ "${1:-}" == "--dry-run" ]]; then
  DRYRUN=true
  BACKING_IMAGE_NAME="${2:-}"
else
  BACKING_IMAGE_NAME="${1:-}"
fi

if [ -z "$BACKING_IMAGE_NAME" ]; then
  echo "Usage: $0 [--dry-run] <backing-image-name>"
  exit 1
fi

echo "🔍 Checking BackingImage: $BACKING_IMAGE_NAME"
$DRYRUN && echo "🧪 Dry-run mode enabled — no changes will be made."

#------------------------------------------------------------------------------
# Helper function to remove or restore "DELETE" operation
# from the validating webhook configuration for Longhorn.
#------------------------------------------------------------------------------
patch_webhook_rule() {
  local action="$1" # remove | restore
  echo "🔧 Patching webhook for operation: $action DELETE on backingimages..."

  local webhook
  webhook="$(kubectl get validatingwebhookconfigurations.admissionregistration.k8s.io longhorn-webhook-validator -o json)"

  local new_webhook
  new_webhook="$(echo "$webhook" | jq --arg action "$action" '
    .webhooks |= map(
      if .rules then
        .rules |= map(
          if (.apiGroups == ["longhorn.io"]
              and .apiVersions == ["v1beta2"]
              and (.resources | index("backingimages")) != null
              and .scope == "Namespaced") then
              if $action == "remove" then
                .operations -= ["DELETE"]
              else
                if (.operations | index("DELETE")) == null then
                  .operations += ["DELETE"]
                else
                  .
                end
              end
          else
            .
          end
        )
      else
        .
      end
    )
  ' )"

  # Apply the updated webhook config
  echo "$new_webhook" | kubectl apply -f -
}

#------------------------------------------------------------------------------
# 1) Check if the current BackingImage has a valid (ready) replica
#------------------------------------------------------------------------------
BI_JSON="$(kubectl get backingimages.longhorn.io "$BACKING_IMAGE_NAME" -n "$NAMESPACE" -o json)"
DISK_STATUS="$(echo "$BI_JSON" | jq -r '.status.diskFileStatusMap // {}')"
READY_COUNT="$(echo "$DISK_STATUS" | jq '[to_entries[] | select(.value.state == "ready")] | length')"

if [ "$READY_COUNT" -gt 0 ]; then
  echo "✅ BackingImage has at least one valid replica. No action needed."
  exit 0
fi

echo "⚠️  No valid replica found for $BACKING_IMAGE_NAME"

#------------------------------------------------------------------------------
# 2) Confirm the BackupBackingImage is "completed"
#    by searching for a BBI whose name STARTS with the BackingImage name
#------------------------------------------------------------------------------
BBI_JSON="$(kubectl get backupbackingimages.longhorn.io -n "$NAMESPACE" -o json \
  | jq -c --arg prefix "$BACKING_IMAGE_NAME" '
    .items[]
    | select(.metadata.name | startswith($prefix))
  ' | head -n1
)"

# If no BBI found with that prefix
if [ -z "$BBI_JSON" ]; then
  echo "❌ No BackupBackingImage found whose name starts with $BACKING_IMAGE_NAME"
  exit 1
fi

BBI_STATE="$(echo "$BBI_JSON" | jq -r '.status.state')"
BBI_URL="$(echo "$BBI_JSON" | jq -r '.status.url')"
BBI_CHECKSUM="$(echo "$BBI_JSON" | jq -r '.status.checksum // empty')"

if [[ "${BBI_STATE,,}" != "completed" ]]; then
  echo "❌ BackupBackingImage found but not in 'completed' state (state = $BBI_STATE)"
  exit 1
fi
echo "✅ BackupBackingImage is completed."

#------------------------------------------------------------------------------
# 3) Check volumes using this BackingImage (must be 'detached')
#------------------------------------------------------------------------------
VOLUMES_JSON="$(kubectl get volumes.longhorn.io -n "$NAMESPACE" -o json)"
USING_VOLUMES="$(echo "$VOLUMES_JSON" | jq -r --arg bi "$BACKING_IMAGE_NAME" '
  .items[]
  | select(.spec.backingImage == $bi)
  | "\(.metadata.name):\(.status.state // "unknown")"
')"

if [ -n "$USING_VOLUMES" ]; then
  echo "📦 Found volumes using BackingImage $BACKING_IMAGE_NAME:"
  echo "$USING_VOLUMES" | sed 's/^/  - /'

  NON_DETACHED="$(echo "$USING_VOLUMES" | awk -F: '$2 != "detached"')"
  if [ -n "$NON_DETACHED" ]; then
    echo "❌ One or more volumes using this BackingImage are not in 'detached' state:"
    echo "$NON_DETACHED" | sed 's/^/  - /'
    echo "🛑 Aborting to avoid disrupting active workloads."
    exit 1
  fi
fi

#------------------------------------------------------------------------------
# 4) Remove DELETE from webhook, then delete the BackingImage (non-blocking)
#------------------------------------------------------------------------------
if $DRYRUN; then
  echo "🧪 Would patch webhook and delete BackingImage $BACKING_IMAGE_NAME (non-blocking)."
else
  patch_webhook_rule remove

  echo "🗑️  Attempting to delete BackingImage (non-blocking)..."
  kubectl delete backingimages.longhorn.io "$BACKING_IMAGE_NAME" -n "$NAMESPACE" \
    --ignore-not-found \
    --wait=false || true

  echo "⏳ Sleeping 5s to allow deletionTimestamp to appear if stuck..."
  sleep 5

  #------------------------------------------------------------------------------
  # 5) If still "terminating" with finalizer, force-remove finalizer
  #------------------------------------------------------------------------------
  if kubectl get backingimages.longhorn.io "$BACKING_IMAGE_NAME" -n "$NAMESPACE" -o json 2>/dev/null | \
     jq -e '.metadata.deletionTimestamp != null and (.metadata.finalizers | length > 0)' >/dev/null; then
    echo "⚠️  BackingImage is still terminating — removing finalizer..."
    kubectl patch backingimages.longhorn.io "$BACKING_IMAGE_NAME" -n "$NAMESPACE" \
      --type=json \
      -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
  fi

  patch_webhook_rule restore
fi

#------------------------------------------------------------------------------
# 6) Re-create the BackingImage from backup
#------------------------------------------------------------------------------
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
