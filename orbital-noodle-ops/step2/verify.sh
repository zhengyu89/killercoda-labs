#!/bin/bash
#
# Every exit path below says why. Killercoda only reads the exit code, so the
# explanation is written to /root/.check and the learner reads it with `why`.
LOG=/root/.check
STEP="Step 2 · The cold deck"
: > "$LOG"
fail() { { echo "x $STEP"; echo; printf '%s\n' "$@"; } | tee "$LOG"; exit 1; }
pass() { echo "OK $STEP -- passed." | tee "$LOG"; exit 0; }
R=""

NS=cold-deck
D=freezer-monitor
COLD=$(kubectl get nodes -l station.lab/deck=cold -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

for _ in $(seq 1 18); do
  kubectl -n $NS get deploy $D >/dev/null 2>&1 || { R="nodeploy"; sleep 5; continue; }

  # Tolerations: the cold-deck one must be there, a blanket one must not.
  TOLS=$(kubectl -n $NS get deploy $D -o jsonpath='{range .spec.template.spec.tolerations[*]}{.key}|{.operator}|{.value}|{.effect}{"\n"}{end}' 2>/dev/null)
  echo "$TOLS" | grep -Eq '^\|Exists\|' && { R="blanket"; sleep 5; continue; }
  echo "$TOLS" | grep -Eq '^cryo\|(Equal|)\|active\|(NoSchedule|)$|^cryo\|Exists\|\|(NoSchedule|)$' \
    || { R="notol"; sleep 5; continue; }

  # Required node affinity on the deck label. nodeSelector alone does not count:
  # the task is about affinity.
  AFF=$(kubectl -n $NS get deploy $D -o jsonpath='{range .spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[*].matchExpressions[*]}{.key}|{.operator}|{.values}{"\n"}{end}' 2>/dev/null)
  echo "$AFF" | grep -E '^station\.lab/deck\|In\|' | grep -q '"cold"' || { R="noaff"; sleep 5; continue; }

  REPL=$(kubectl -n $NS get deploy $D -o jsonpath='{.spec.replicas}' 2>/dev/null)
  [ "$REPL" == "3" ] || { R="replicas"; sleep 5; continue; }
  READY=$(kubectl -n $NS get deploy $D -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  UPD=$(kubectl -n $NS get deploy $D -o jsonpath='{.status.updatedReplicas}' 2>/dev/null)
  [ "$READY" == "3" ] && [ "$UPD" == "3" ] || { R="notready"; sleep 5; continue; }

  # Where the Pods actually run, not where they were asked to run.
  WHERE=$(kubectl -n $NS get pods -l app=freezer-monitor \
    --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null)
  [ -n "$WHERE" ] || { R="notready"; sleep 5; continue; }
  OFF=$(echo "$WHERE" | grep -vx "$COLD" | sort | uniq -c)
  [ -z "$OFF" ] || { R="offdeck"; sleep 5; continue; }

  pass
done

case "$R" in
  nodeploy) fail \
    "There is no Deployment named freezer-monitor in namespace cold-deck." \
    "" \
    "  kubectl -n cold-deck get deploy" ;;
  blanket) fail \
    "freezer-monitor has a toleration with operator Exists and no key." \
    "" \
    "That tolerates every taint on every node -- including ones that mean" \
    "'do not run here' for reasons you have not thought of yet, such as the" \
    "unschedulable taint a drain adds. Tolerate the one taint you mean:" \
    "  key: cryo, operator: Equal, value: active, effect: NoSchedule" ;;
  notol) fail \
    "freezer-monitor does not tolerate the cold-deck taint cryo=active:NoSchedule." \
    "" \
    "  tolerations found (key|operator|value|effect):" \
    "$(echo "${TOLS:-<none>}" | sed 's/^/    /')" \
    "" \
    "Without it, the only node your affinity allows will refuse every Pod." ;;
  noaff) fail \
    "freezer-monitor has no required node affinity for station.lab/deck In [cold]." \
    "" \
    "  found:" \
    "$(echo "${AFF:-<none>}" | sed 's/^/    /')" \
    "" \
    "It belongs under spec.template.spec.affinity.nodeAffinity" \
    ".requiredDuringSchedulingIgnoredDuringExecution -- a 'preferred' rule or a" \
    "nodeSelector is not what this step asks for." ;;
  replicas) fail \
    "freezer-monitor has ${REPL:-?} replicas; it should have 3." ;;
  notready) fail \
    "freezer-monitor does not have 3 updated, ready Pods yet (ready: ${READY:-0})." \
    "" \
    "  kubectl -n cold-deck get pods -o wide" \
    "  kubectl -n cold-deck describe pod -l app=freezer-monitor | grep -A8 Events" \
    "" \
    "Pending with 'untolerated taint' means the toleration is wrong; Pending with" \
    "'didn't match Pod's node affinity' means the affinity is." ;;
  offdeck) fail \
    "Some freezer-monitor Pods are running off the cold deck (${COLD}):" \
    "" \
    "$(echo "$OFF" | sed 's/^/  /')" \
    "" \
    "A toleration only permits the cold deck; it is the required node affinity" \
    "that keeps Pods off the warm one." ;;
  *) fail "Unexpected state -- rerun the check." ;;
esac
