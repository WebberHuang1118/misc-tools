#!/usr/bin/env bash
# list-va-tickets-tree.sh  —  Longhorn tickets + ALL k8s VolumeAttachments
#   • full node names
#   • hashes shortened by default, use --full to keep them intact

SHORT=true
[[ "$1" == "--full" ]] && SHORT=false

short() { $SHORT && [[ ${#1} -gt 12 ]] && printf '%s…' "${1:0:12}" || printf '%s' "$1"; }
tick()  { [[ "$1" == "true" ]] && printf '✓' || printf '✗'; }

# ── 1. index every k8s VolumeAttachment by PV name ──────────────────────────
declare -A K8S_BY_PV
while IFS=$'\t' read -r name pv node attached errmsg; do
  entry="$(printf '%s|%s|%s|%s\n' "$name" "$node" "$attached" "$errmsg")"
  K8S_BY_PV["$pv"]+=$'\n'"$entry"
done < <(
  kubectl get volumeattachments.storage.k8s.io -o json |
  jq -r '.items[]
         | [.metadata.name,
            .spec.source.persistentVolumeName,
            .spec.nodeName,
            (.status.attached|tostring),
            (.status.attachError.message // "")]
         | @tsv'
)

# ── 2. walk Longhorn VAs with >1 ticket ─────────────────────────────────────
kubectl get volumeattachments.longhorn.io --all-namespaces -o json |
jq -r '
  .items[]
  | select(.spec.attachmentTickets | length > 1)
  | {pv: .metadata.name,
     tk: .spec.attachmentTickets,
     st: .status.attachmentTicketStatuses,
     ts: .metadata.creationTimestamp}
  | @json' | while read -r obj; do
    pv=$(jq -r '.pv' <<<"$obj")
    ts=$(jq -r '.ts' <<<"$obj")
    echo
    echo "LH VA created: $ts ($pv)"

    # Longhorn tickets
    jq -r '.tk | to_entries[] | @json' <<<"$obj" | while read -r t; do
      key=$(jq -r '.key'          <<<"$t")
      id=$(jq  -r '.value.id'     <<<"$t")
      node=$(jq -r '.value.nodeID'<<<"$t")        # FULL node name
      typ=$(jq -r '.value.type'   <<<"$t")
      sat=$(jq -r --arg k "$key" '.st[$k].satisfied // false' <<<"$obj")

      printf '  ├─ %-14s (node=%-25s type=%-12s sat=%s id=%s)\n' \
             "$(short "$key")" "$node" "$typ" "$(tick "$sat")" "$(short "$id")"
    done

    # all k8s VAs for this PV
    if [[ -n ${K8S_BY_PV["$pv"]} ]]; then
      echo "  └─ k8s-VA"
      while IFS='|' read -r kname knode kattach kerr; do
        [[ -z "$kname" ]] && continue
        printf '        ↳ %-14s node=%-25s attached=%s err=%s\n' \
               "$(short "$kname")" "$knode" "$(tick "$kattach")" "$kerr"
      done <<<"${K8S_BY_PV["$pv"]}"
    fi
done
