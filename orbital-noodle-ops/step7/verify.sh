#!/bin/bash
#
# Every exit path below says why. Killercoda only reads the exit code, so the
# explanation is written to /root/.check and the learner reads it with `why`.
LOG=/root/.check
STEP="Step 7 · Hull maintenance"
: > "$LOG"
fail() { { echo "x $STEP"; echo; printf '%s\n' "$@"; } | tee "$LOG"; exit 1; }
pass() { echo "OK $STEP -- passed." | tee "$LOG"; exit 0; }
R=""

NS=lounge
COLD=$(kubectl get nodes -l station.lab/deck=cold -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

for _ in $(seq 1 18); do
  kubectl -n $NS get pdb jukebox-pdb >/dev/null 2>&1 || { R="nopdb"; sleep 5; continue; }
  MIN=$(kubectl -n $NS get pdb jukebox-pdb -o jsonpath='{.spec.minAvailable}' 2>/dev/null)
  [ "$MIN" == "2" ] || { R="pdbmin"; sleep 5; continue; }
  # The PDB's own status says how many Pods its selector found -- a selector
  # that matches nothing protects nothing, and still looks fine at a glance.
  EXP=$(kubectl -n $NS get pdb jukebox-pdb -o jsonpath='{.status.expectedPods}' 2>/dev/null)
  [ "$EXP" == "3" ] || { R="pdbsel"; sleep 5; continue; }

  UNSCHED=$(kubectl get node "$COLD" -o jsonpath='{.spec.unschedulable}' 2>/dev/null)
  [ "$UNSCHED" == "true" ] || { R="notcordoned"; sleep 5; continue; }

  # Anything still bound to the node that drain should have evicted: not a
  # DaemonSet Pod, not a static (mirror) Pod, and not already finished.
  LEFT=$(kubectl get pods -A --field-selector "spec.nodeName=$COLD" \
    -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}|{.metadata.ownerReferences[0].kind}|{.metadata.annotations.kubernetes\.io/config\.mirror}|{.status.phase}{"\n"}{end}' 2>/dev/null \
    | awk -F'|' '$2!="DaemonSet" && $3=="" && $4!="Succeeded" && $4!="Failed" && $1!="" {print $1}')
  [ -z "$LEFT" ] || { R="notdrained"; sleep 5; continue; }

  READY=$(kubectl -n $NS get deploy jukebox -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [ "$READY" == "3" ] || { R="jukebox"; sleep 5; continue; }
  OFFDECK=$(kubectl -n $NS get pods -l app=jukebox --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | grep -vx "$COLD" | grep -c .)
  [ "$OFFDECK" == "3" ] || { R="jukebox"; sleep 5; continue; }

  pass
done

case "$R" in
  nopdb) fail \
    "There is no PodDisruptionBudget named jukebox-pdb in namespace lounge." \
    "" \
    "  kubectl -n lounge create poddisruptionbudget jukebox-pdb --selector=app=jukebox --min-available=2" ;;
  pdbmin) fail \
    "jukebox-pdb has minAvailable='${MIN:-<unset>}'; it should be 2." \
    "" \
    "If you used maxUnavailable instead: it would protect the same 3 Pods today," \
    "but the task asks for a floor of 2 running players, which is minAvailable." ;;
  pdbsel) fail \
    "jukebox-pdb covers ${EXP:-0} Pods; the jukebox has 3." \
    "" \
    "  kubectl -n lounge get pdb jukebox-pdb -o jsonpath='{.spec.selector}'" \
    "  kubectl -n lounge get pods --show-labels" \
    "" \
    "A PDB whose selector matches nothing protects nothing -- and blocks nothing." ;;
  notcordoned) fail \
    "Node ${COLD} is schedulable. It should stay cordoned while maintenance runs." \
    "" \
    "  kubectl drain ${COLD} --ignore-daemonsets --delete-emptydir-data" \
    "" \
    "(If you already drained and then uncordoned it, cordon it again:" \
    " kubectl cordon ${COLD})" ;;
  notdrained) fail \
    "These Pods are still bound to ${COLD}:" \
    "" \
    "$(echo "$LEFT" | sed 's/^/  /')" \
    "" \
    "Cordoning only stops new Pods; draining evicts the existing ones:" \
    "  kubectl drain ${COLD} --ignore-daemonsets --delete-emptydir-data" ;;
  jukebox) fail \
    "The jukebox does not have 3 ready Pods on the warm deck (ready: ${READY:-0}, off ${COLD}: ${OFFDECK:-0})." \
    "" \
    "  kubectl -n lounge get pods -o wide" \
    "  kubectl -n lounge describe pod -l app=jukebox | grep -A8 Events" ;;
  *) fail "Unexpected state -- rerun the check." ;;
esac
