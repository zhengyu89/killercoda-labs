#!/bin/bash
#
# Every exit path below says why. Killercoda only reads the exit code, so the
# explanation is written to /root/.check and the learner reads it with `why`.
LOG=/root/.check
STEP="Step 5 · Stock count"
: > "$LOG"
fail() { { echo "x $STEP"; echo; printf '%s\n' "$@"; } | tee "$LOG"; exit 1; }
pass() { echo "OK $STEP -- passed." | tee "$LOG"; exit 0; }
R=""

NS=ops
CJ=stock-count
JOB=stock-count-manual

# field JSONPATH: one value from the CronJob.
field() { kubectl -n $NS get cronjob $CJ -o jsonpath="{$1}" 2>/dev/null; }

for _ in $(seq 1 18); do
  kubectl -n $NS get cronjob $CJ >/dev/null 2>&1 || { R="nocj"; sleep 5; continue; }

  # Compare every required field at once and report all mismatches together.
  BAD=""
  chk() { [ "$(field "$1")" == "$2" ] || BAD="${BAD}  ${1}: '$(field "$1")' (want '$2')"$'\n'; }
  chk .spec.schedule "15 */6 * * *"
  chk .spec.timeZone "Asia/Kuala_Lumpur"
  chk .spec.concurrencyPolicy "Forbid"
  chk .spec.startingDeadlineSeconds "120"
  chk .spec.successfulJobsHistoryLimit "2"
  chk .spec.failedJobsHistoryLimit "1"
  chk .spec.jobTemplate.spec.backoffLimit "2"
  chk .spec.jobTemplate.spec.activeDeadlineSeconds "90"
  chk .spec.jobTemplate.spec.template.spec.restartPolicy "Never"
  chk '.spec.jobTemplate.spec.template.spec.containers[0].name' "counter"
  chk '.spec.jobTemplate.spec.template.spec.containers[0].image' "alpine:3.20"
  [ -z "$BAD" ] || { R="fields"; sleep 5; continue; }

  kubectl -n $NS get job $JOB >/dev/null 2>&1 || { R="nojob"; sleep 5; continue; }
  # `kubectl create job --from=cronjob/...` marks the Job and makes the CronJob
  # its owner; a Job written by hand has neither.
  INST=$(kubectl -n $NS get job $JOB -o jsonpath='{.metadata.annotations.cronjob\.kubernetes\.io/instantiate}' 2>/dev/null)
  OWNER=$(kubectl -n $NS get job $JOB -o jsonpath='{.metadata.ownerReferences[?(@.kind=="CronJob")].name}' 2>/dev/null)
  [ "$INST" == "manual" ] && [ "$OWNER" == "$CJ" ] || { R="notfrom"; sleep 5; continue; }

  FAILED=$(kubectl -n $NS get job $JOB -o jsonpath='{.status.failed}' 2>/dev/null)
  OK=$(kubectl -n $NS get job $JOB -o jsonpath='{.status.succeeded}' 2>/dev/null)
  [ "$OK" == "1" ] || { R="notdone"; sleep 5; continue; }

  OUT=$(kubectl -n $NS logs job/$JOB 2>/dev/null)
  echo "$OUT" | grep -q "stock-count: all shelves sealed" || { R="logs"; sleep 5; continue; }

  pass
done

case "$R" in
  nocj) fail \
    "There is no CronJob named stock-count in namespace ops." \
    "" \
    "  kubectl -n ops get cronjobs" ;;
  fields) fail \
    "Some CronJob fields don't match:" \
    "" \
    "$BAD" \
    "Remember which layer each one lives at -- the CronJob spec, the Job" \
    "(jobTemplate.spec), or the Pod (jobTemplate.spec.template.spec):" \
    "  kubectl explain cronjob.spec --recursive | less" ;;
  nojob) fail \
    "There is no Job named stock-count-manual in namespace ops." \
    "" \
    "Create it from the CronJob, so it uses the CronJob's own template:" \
    "  kubectl -n ops create job stock-count-manual --from=cronjob/stock-count" ;;
  notfrom) fail \
    "Job stock-count-manual was not created from the CronJob." \
    "" \
    "  annotation cronjob.kubernetes.io/instantiate: '${INST:-<none>}' (want 'manual')" \
    "  owner CronJob: '${OWNER:-<none>}' (want 'stock-count')" \
    "" \
    "Jobs cannot be edited in place -- delete it and create it from the CronJob:" \
    "  kubectl -n ops delete job stock-count-manual" \
    "  kubectl -n ops create job stock-count-manual --from=cronjob/stock-count" ;;
  notdone) fail \
    "Job stock-count-manual has not succeeded (succeeded: ${OK:-0}, failed: ${FAILED:-0})." \
    "" \
    "  kubectl -n ops get pods -l job-name=stock-count-manual" \
    "  kubectl -n ops logs job/stock-count-manual" \
    "" \
    "If it failed, fix the CronJob first, then delete and re-create the Job --" \
    "a Job made with --from copies the template as it was at that moment." ;;
  logs) fail \
    "The Job succeeded but its log does not contain 'stock-count: all shelves sealed'." \
    "" \
    "  log was:" \
    "$(echo "${OUT:-<empty>}" | sed 's/^/    /')" ;;
  *) fail "Unexpected state -- rerun the check." ;;
esac
