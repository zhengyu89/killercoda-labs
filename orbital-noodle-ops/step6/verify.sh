#!/bin/bash
#
# Every exit path below says why. Killercoda only reads the exit code, so the
# explanation is written to /root/.check and the learner reads it with `why`.
LOG=/root/.check
STEP="Step 6 · Dead air"
: > "$LOG"
fail() { { echo "x $STEP"; echo; printf '%s\n' "$@"; } | tee "$LOG"; exit 1; }
pass() { echo "OK $STEP -- passed." | tee "$LOG"; exit 0; }
R=""

NS=comms
ORIG_UID=$(cat /root/.lab/radio-svc-uid 2>/dev/null)

restarts() {
  kubectl -n $NS get pods -l app=radio \
    -o jsonpath='{range .items[*]}{.metadata.name}={.status.containerStatuses[0].restartCount}{"\n"}{end}' 2>/dev/null | sort
}

for _ in $(seq 1 18); do
  UID_NOW=$(kubectl -n $NS get svc radio -o jsonpath='{.metadata.uid}' 2>/dev/null)
  [ -n "$UID_NOW" ] || { R="nosvc"; sleep 5; continue; }
  [ -z "$ORIG_UID" ] || [ "$UID_NOW" == "$ORIG_UID" ] || { R="recreated"; sleep 5; continue; }

  # The radio itself must be untouched apart from the probe.
  LBL=$(kubectl -n $NS get deploy radio -o jsonpath='{.spec.template.metadata.labels.app}' 2>/dev/null)
  CPORT=$(kubectl -n $NS get deploy radio -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}/{.spec.template.spec.containers[0].ports[0].name}' 2>/dev/null)
  [ "$LBL" == "radio" ] && [ "$CPORT" == "9090/http" ] || { R="tampered"; sleep 5; continue; }

  # Same order as the step text: selector, then targetPort, then the probe.
  SEL=$(kubectl -n $NS get svc radio -o jsonpath='{.spec.selector}' 2>/dev/null)
  MATCHED=$(kubectl -n $NS get endpointslices -l kubernetes.io/service-name=radio \
    -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{"\n"}{end}' 2>/dev/null | grep -c .)
  [ "$MATCHED" -gt 0 ] || { R="noendpoints"; sleep 5; continue; }

  TPORT=$(kubectl -n $NS get svc radio -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)
  case "$TPORT" in 9090|http) ;; *) R="targetport"; sleep 5; continue ;; esac

  PROBE=$(kubectl -n $NS get deploy radio -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}' 2>/dev/null)
  [ -n "$PROBE" ] || { R="noprobe"; sleep 5; continue; }
  PPORT=$(kubectl -n $NS get deploy radio -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.port}{.spec.template.spec.containers[0].livenessProbe.tcpSocket.port}' 2>/dev/null)
  case "$PPORT" in 9090|http) ;; *) R="probeport"; sleep 5; continue ;; esac

  SPEC=$(kubectl -n $NS get deploy radio -o jsonpath='{.spec.replicas}' 2>/dev/null)
  READY=$(kubectl -n $NS get deploy radio -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  UPD=$(kubectl -n $NS get deploy radio -o jsonpath='{.status.updatedReplicas}' 2>/dev/null)
  TOTAL=$(kubectl -n $NS get deploy radio -o jsonpath='{.status.replicas}' 2>/dev/null)
  [ "$SPEC" == "2" ] && [ "$READY" == "2" ] && [ "$UPD" == "2" ] && [ "$TOTAL" == "2" ] \
    || { R="notready"; sleep 5; continue; }

  # End to end: the listener resolves the Service by name and gets an answer
  # from one of the radio Pods.
  BODY=$(kubectl -n $NS exec deploy/listener -- curl -sS -m 5 http://radio/hostname 2>&1)
  echo "$BODY" | grep -q '^radio-' || { R="nocurl"; sleep 5; continue; }

  # Restarts must stop climbing. A probe on the wrong port kills the container
  # about 15s after it starts, so 25s is long enough to catch one.
  BEFORE=$(restarts)
  sleep 25
  AFTER=$(restarts)
  [ "$BEFORE" == "$AFTER" ] || { R="restarting"; continue; }

  pass
done

case "$R" in
  nosvc) fail \
    "There is no Service named radio in namespace comms." \
    "" \
    "The task was to fix it in place. If it was deleted, it has to come back" \
    "with the same name -- but this check will then report it as re-created." ;;
  recreated) fail \
    "The radio Service has been deleted and re-created (its UID changed)." \
    "" \
    "On a real cluster, re-creating a Service can change its ClusterIP and break" \
    "anything that cached it. Fix Services in place:" \
    "  kubectl -n comms edit svc radio" \
    "" \
    "To try the step again cleanly, restart the scenario." ;;
  tampered) fail \
    "The radio Pods were changed in a way the task rules out:" \
    "" \
    "  Pod label app: '${LBL}' (want 'radio')" \
    "  container port/name: '${CPORT}' (want '9090/http')" \
    "" \
    "The radio is fine -- fix what points at it (the Service and the probe)." ;;
  noprobe) fail \
    "The radio container has no liveness probe any more." \
    "" \
    "Removing it stops the restarts, but also means a radio that really hangs" \
    "is never restarted. Keep the probe and point it at the right port:" \
    "  kubectl -n comms edit deploy radio" ;;
  probeport) fail \
    "The liveness probe still checks port '${PPORT}'. The radio serves on 9090 (named http)." \
    "" \
    "  kubectl -n comms describe pod -l app=radio | grep -E 'Liveness|Unhealthy'" ;;
  noendpoints) fail \
    "The radio Service selects no Pods -- its EndpointSlice is empty." \
    "" \
    "  Service selector: ${SEL:-<none>}" \
    "  kubectl -n comms get pods --show-labels" \
    "" \
    "The selector has to match labels the radio Pods actually carry." ;;
  targetport) fail \
    "The Service now selects the radio Pods, but sends traffic to targetPort '${TPORT}'." \
    "" \
    "Nothing in the radio container listens there. It listens on 9090, named http:" \
    "  kubectl -n comms get deploy radio -o jsonpath='{.spec.template.spec.containers[0].ports}'" ;;
  notready) fail \
    "The radio Deployment is not fully rolled out and ready (ready ${READY:-0} of ${SPEC:-?})." \
    "" \
    "  kubectl -n comms get pods -l app=radio" \
    "  kubectl -n comms rollout status deploy/radio" ;;
  nocurl) fail \
    "The listener still cannot hear the radio:" \
    "" \
    "  kubectl -n comms exec deploy/listener -- curl -sS -m 5 http://radio/hostname" \
    "$(echo "${BODY:-<no output>}" | head -3 | sed 's/^/    /')" ;;
  restarting) fail \
    "Everything is wired up, but radio Pods are still being restarted:" \
    "" \
    "  before: $(echo "$BEFORE" | tr '\n' ' ')" \
    "  after:  $(echo "$AFTER" | tr '\n' ' ')" \
    "" \
    "  kubectl -n comms describe pod -l app=radio | grep -A10 Events" ;;
  *) fail "Unexpected state -- rerun the check." ;;
esac
