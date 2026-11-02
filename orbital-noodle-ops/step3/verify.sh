#!/bin/bash
#
# Every exit path below says why. Killercoda only reads the exit code, so the
# explanation is written to /root/.check and the learner reads it with `why`.
LOG=/root/.check
STEP="Step 3 · Bad broth"
: > "$LOG"
fail() { { echo "x $STEP"; echo; printf '%s\n' "$@"; } | tee "$LOG"; exit 1; }
pass() { echo "OK $STEP -- passed." | tee "$LOG"; exit 0; }
R=""

NS=broth
D=broth-api
GOOD=nginx:1.28-alpine
ANS=/root/answers/broth-revision

for _ in $(seq 1 18); do
  [ -s "$ANS" ] || { R="nofile"; sleep 5; continue; }
  REV=$(tr -d '[:space:]' < "$ANS")
  [ "$REV" == "2" ] || { R="wrongrev"; sleep 5; continue; }

  IMG=$(kubectl -n $NS get deploy $D -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  [ "$IMG" == "$GOOD" ] || { R="image"; sleep 5; continue; }

  MU=$(kubectl -n $NS get deploy $D -o jsonpath='{.spec.strategy.rollingUpdate.maxUnavailable}' 2>/dev/null)
  MS=$(kubectl -n $NS get deploy $D -o jsonpath='{.spec.strategy.rollingUpdate.maxSurge}' 2>/dev/null)
  case "$MU" in 0|0%) ;; *) R="strategy"; sleep 5; continue ;; esac
  [ "$MS" == "1" ] || { R="strategy"; sleep 5; continue; }

  SPEC=$(kubectl -n $NS get deploy $D -o jsonpath='{.spec.replicas}' 2>/dev/null)
  AVAIL=$(kubectl -n $NS get deploy $D -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
  UPD=$(kubectl -n $NS get deploy $D -o jsonpath='{.status.updatedReplicas}' 2>/dev/null)
  TOTAL=$(kubectl -n $NS get deploy $D -o jsonpath='{.status.replicas}' 2>/dev/null)
  [ "$SPEC" == "4" ] || { R="replicas"; sleep 5; continue; }
  [ "$AVAIL" == "4" ] && [ "$UPD" == "4" ] && [ "$TOTAL" == "4" ] || { R="rolling"; sleep 5; continue; }

  SPICY=$(kubectl -n $NS get pods -l app=broth-api \
    -o jsonpath='{range .items[*]}{.metadata.name} {.spec.containers[0].image}{"\n"}{end}' 2>/dev/null \
    | grep -v " ${GOOD}$")
  [ -z "$SPICY" ] || { R="leftover"; sleep 5; continue; }

  pass
done

case "$R" in
  nofile) fail \
    "/root/answers/broth-revision does not exist or is empty." \
    "" \
    "Find the winter-menu revision in the history, then write just its number:" \
    "  kubectl -n broth rollout history deployment broth-api" ;;
  wrongrev) fail \
    "/root/answers/broth-revision says '${REV}', which is not the revision the" \
    "winter menu was originally released as." \
    "" \
    "If you rolled back first and read the history afterwards, the winter-menu" \
    "template now sits under a new, higher number -- a rollback copies the old" \
    "template forward as the newest revision. The question is which revision it" \
    "was released as. ReplicaSets keep earlier numbers in revision-history:" \
    "  kubectl -n broth get rs -o custom-columns='IMAGE:.spec.template.spec.containers[0].image,REVISION:.metadata.annotations.deployment\.kubernetes\.io/revision,HISTORY:.metadata.annotations.deployment\.kubernetes\.io/revision-history'" ;;
  image) fail \
    "broth-api runs image '${IMG}', not the winter-menu image." \
    "" \
    "  kubectl -n broth rollout history deployment broth-api --revision=<n>" \
    "  kubectl -n broth rollout undo deployment broth-api --to-revision=<n>" ;;
  strategy) fail \
    "The rolling-update strategy is maxUnavailable=${MU:-<default 25%>}, maxSurge=${MS:-<default 25%>}." \
    "It should be maxUnavailable=0, maxSurge=1." \
    "" \
    "  kubectl -n broth get deploy broth-api -o jsonpath='{.spec.strategy}'" ;;
  replicas) fail \
    "broth-api is set to ${SPEC:-?} replicas; it should stay at 4." ;;
  rolling) fail \
    "broth-api has not finished rolling out: ${AVAIL:-0} available, ${UPD:-0} updated, ${TOTAL:-0} total (want 4/4/4)." \
    "" \
    "  kubectl -n broth rollout status deployment broth-api" \
    "  kubectl -n broth get pods" ;;
  leftover) fail \
    "Pods with a different image are still around:" \
    "" \
    "$(echo "$SPICY" | sed 's/^/  /')" \
    "" \
    "  kubectl -n broth get rs" ;;
  *) fail "Unexpected state -- rerun the check." ;;
esac
