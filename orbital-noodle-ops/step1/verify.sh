#!/bin/bash
#
# Every exit path below says why. Killercoda only reads the exit code, so the
# explanation is written to /root/.check and the learner reads it with `why`.
# The loop records the condition it is still waiting on in R, and if it runs
# out of attempts that is what the learner is told.
LOG=/root/.check
STEP="Step 1 · Ladle-9 gets a badge"
: > "$LOG"
fail() { { echo "x $STEP"; echo; printf '%s\n' "$@"; } | tee "$LOG"; exit 1; }
pass() { echo "OK $STEP -- passed." | tee "$LOG"; exit 0; }
R=""

BOT=system:serviceaccount:galley:order-bot

# can NAMESPACE VERB RESOURCE [--subresource=...]: asks the API server whether
# the bot may do this. Permissions are judged by the authorizer, not by reading
# the Role back, so any shape of Role that grants the same access passes.
can() {
  local ns=$1; shift
  kubectl auth can-i "$@" -n "$ns" --as="$BOT" >/dev/null 2>&1
}

NEEDED='galley get pods
galley list pods
galley watch pods
galley get pods --subresource=log
galley get deployments.apps/noodle-line
galley get deployments.apps/noodle-line --subresource=scale
galley patch deployments.apps/noodle-line --subresource=scale
galley update deployments.apps/noodle-line --subresource=scale'

FORBIDDEN='galley delete pods
galley create pods
galley get secrets
galley list secrets
galley patch deployments.apps/noodle-line
galley update deployments.apps/noodle-line
galley delete deployments.apps/noodle-line
galley get deployments.apps/dish-washer
galley patch deployments.apps/dish-washer --subresource=scale
galley create rolebindings.rbac.authorization.k8s.io
default list pods
default patch deployments.apps/noodle-line --subresource=scale
galley get nodes'

for _ in $(seq 1 12); do
  kubectl -n galley get serviceaccount order-bot >/dev/null 2>&1 || { R="nosa"; sleep 5; continue; }
  kubectl -n galley get role order-bot >/dev/null 2>&1 || { R="norole"; sleep 5; continue; }
  REF=$(kubectl -n galley get rolebinding order-bot \
    -o jsonpath='{.roleRef.kind}/{.roleRef.name}' 2>/dev/null)
  [ -n "$REF" ] || { R="norb"; sleep 5; continue; }
  [ "$REF" == "Role/order-bot" ] || { R="rbref"; sleep 5; continue; }
  SUBJ=$(kubectl -n galley get rolebinding order-bot \
    -o jsonpath='{range .subjects[*]}{.kind}/{.namespace}/{.name}{"\n"}{end}' 2>/dev/null)
  echo "$SUBJ" | grep -qx 'ServiceAccount/galley/order-bot' || { R="rbsubj"; sleep 5; continue; }

  MISSING=""
  while read -r LINE; do
    # shellcheck disable=SC2086 # each line is deliberately split into arguments
    can $LINE || MISSING="${MISSING}  - ${LINE}"$'\n'
  done <<< "$NEEDED"
  [ -z "$MISSING" ] || { R="missing"; sleep 5; continue; }

  EXCESS=""
  while read -r LINE; do
    # shellcheck disable=SC2086
    can $LINE && EXCESS="${EXCESS}  - ${LINE}"$'\n'
  done <<< "$FORBIDDEN"
  [ -z "$EXCESS" ] || { R="excess"; sleep 5; continue; }

  REPL=$(kubectl -n galley get deploy noodle-line -o jsonpath='{.spec.replicas}' 2>/dev/null)
  [ "$REPL" == "4" ] || { R="notscaled"; sleep 5; continue; }
  READY=$(kubectl -n galley get deploy noodle-line -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [ "$READY" == "4" ] || { R="notready"; sleep 5; continue; }

  pass
done

case "$R" in
  nosa) fail \
    "There is no ServiceAccount named order-bot in namespace galley." \
    "" \
    "  kubectl -n galley create serviceaccount order-bot" ;;
  norole) fail \
    "There is no Role named order-bot in namespace galley." \
    "" \
    "  kubectl -n galley get roles" \
    "" \
    "A ClusterRole does not count here: the task asks for a namespaced Role." ;;
  norb) fail \
    "There is no RoleBinding named order-bot in namespace galley." \
    "" \
    "  kubectl -n galley create rolebinding order-bot --role=order-bot --serviceaccount=galley:order-bot" ;;
  rbref) fail \
    "RoleBinding order-bot points at ${REF}, not Role/order-bot." \
    "" \
    "roleRef cannot be edited after creation -- delete the binding and create it again:" \
    "  kubectl -n galley delete rolebinding order-bot" \
    "  kubectl -n galley create rolebinding order-bot --role=order-bot --serviceaccount=galley:order-bot" ;;
  rbsubj) fail \
    "RoleBinding order-bot does not list the ServiceAccount galley/order-bot as a subject." \
    "" \
    "  subjects found:" \
    "$(echo "${SUBJ:-<none>}" | sed 's/^/    /')" \
    "" \
    "A ServiceAccount subject needs kind ServiceAccount, name order-bot AND namespace galley." ;;
  missing) fail \
    "The bot is missing permissions it needs:" \
    "" \
    "$MISSING" \
    "Check each one yourself, for example:" \
    "  kubectl -n galley auth can-i get pods --subresource=log --as=$BOT" \
    "" \
    "Subresources are separate resources in a Role: 'pods/log', 'deployments/scale'." ;;
  excess) fail \
    "The bot can do things it should not:" \
    "" \
    "$EXCESS" \
    "Check one yourself, for example:" \
    "  kubectl -n galley auth can-i patch deployments.apps/noodle-line --as=$BOT" \
    "" \
    "Common causes: a '*' in verbs or resources; 'deployments' granted without" \
    "resourceNames; or an extra RoleBinding/ClusterRoleBinding for this account:" \
    "  kubectl get rolebindings,clusterrolebindings -A -o wide | grep order-bot" ;;
  notscaled) fail \
    "Permissions are right, but noodle-line has ${REPL:-?} replicas, not 4." \
    "" \
    "Scale it as the bot -- that is the proof the Role works end to end:" \
    "  kubectl -n galley scale deployment noodle-line --replicas=4 --as=$BOT" ;;
  notready) fail \
    "noodle-line is set to 4 replicas but only ${READY:-0} are ready yet." \
    "" \
    "  kubectl -n galley get pods -l app=noodle-line" ;;
  *) fail "Unexpected state -- rerun the check." ;;
esac
