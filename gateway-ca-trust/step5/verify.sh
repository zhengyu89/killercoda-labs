#!/bin/bash
#
# Every exit path below says why. Killercoda only reads the exit code, so the
# explanation is written to /root/.check and the learner reads it with `why`.
# The loop records the condition it is still waiting on in R, and if it runs
# out of attempts that is what the learner is told.
LOG=/root/.check
STEP="Step 5 · Trust that scales: trust-manager"
: > "$LOG"
fail() { { echo "x $STEP"; echo; printf '%s\n' "$@"; } | tee "$LOG"; exit 1; }
pass() { echo "OK $STEP -- passed." | tee "$LOG"; exit 0; }
R=""

gw_ip() {
  local ip
  ip=$(kubectl -n chiikawa get svc \
    -l gateway.networking.k8s.io/gateway-name=chiikawa-gateway \
    -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null)
  [ -z "$ip" ] && ip=$(kubectl -n chiikawa get svc chiikawa-gateway-nginx \
    -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
  echo "$ip"
}

HOST=hachiware.chiikawa.lab
CA_FP=$(kubectl -n cert-manager get secret chiikawa-ca-key-pair \
  -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)

for _ in $(seq 1 30); do
  SRC=$(kubectl get bundle chiikawa-ca-bundle \
    -o jsonpath='{.spec.sources[0].secret.name}{" "}{.spec.sources[0].secret.key}' 2>/dev/null)
  [ -n "$SRC" ] || { R="nobundle"; sleep 5; continue; }
  [ "$SRC" == "chiikawa-ca-key-pair tls.crt" ] || { R="wrongsource"; sleep 5; continue; }

  TARGETKEY=$(kubectl get bundle chiikawa-ca-bundle \
    -o jsonpath='{.spec.target.configMap.key}' 2>/dev/null)
  [ "$TARGETKEY" == "ca.crt" ] || { R="wrongtargetkey"; sleep 5; continue; }

  SELECTOR=$(kubectl get bundle chiikawa-ca-bundle \
    -o jsonpath='{.spec.target.namespaceSelector.matchLabels.chiikawa\.lab/trust-bundle}' 2>/dev/null)
  [ "$SELECTOR" == "true" ] || { R="noselector"; sleep 5; continue; }

  SYNCED=$(kubectl get bundle chiikawa-ca-bundle \
    -o jsonpath='{.status.conditions[?(@.type=="Synced")].status}' 2>/dev/null)
  SYNCMSG=$(kubectl get bundle chiikawa-ca-bundle \
    -o jsonpath='{.status.conditions[?(@.type=="Synced")].message}' 2>/dev/null)
  [ "$SYNCED" == "True" ] || { R="notsynced"; sleep 5; continue; }

  # A Bundle with no namespaceSelector targets every namespace. Checking a
  # control namespace that was never meant to be labeled is what catches
  # that mistake -- the earlier checks would all still pass without it.
  CONTROL=$(kubectl -n chiikawa get configmap chiikawa-ca-bundle \
    -o jsonpath='{.data.ca\.crt}' 2>/dev/null)
  [ -z "$CONTROL" ] || { R="toobroad"; sleep 5; continue; }

  ALLGOOD=1
  unset UNLABELED MISSINGNS WRONGNS
  for NS in usagi kitchen; do
    LBL=$(kubectl get namespace "$NS" \
      -o jsonpath='{.metadata.labels.chiikawa\.lab/trust-bundle}' 2>/dev/null)
    [ "$LBL" == "true" ] || { ALLGOOD=0; UNLABELED="$NS"; break; }

    CMDATA=$(kubectl -n "$NS" get configmap chiikawa-ca-bundle \
      -o jsonpath='{.data.ca\.crt}' 2>/dev/null)
    if [ -z "$CMDATA" ]; then ALLGOOD=0; MISSINGNS="$NS"; break; fi

    FP=$(echo "$CMDATA" | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
    if [ -z "$CA_FP" ] || [ "$FP" != "$CA_FP" ]; then ALLGOOD=0; WRONGNS="$NS"; break; fi
  done
  [ "$ALLGOOD" == "1" ] || {
    if [ -n "$UNLABELED" ]; then R="unlabeled"; else
    if [ -n "$MISSINGNS" ]; then R="missingcm"; else R="wrongcm"; fi; fi
    sleep 5; continue
  }

  # Proven live, from Usagi's own Pod, against the file trust-manager wrote --
  # not against the copy the learner deleted at the start of this step.
  GWIP=$(gw_ip)
  [ -n "$GWIP" ] || { R="nogateway"; sleep 5; continue; }

  READY=$(kubectl -n usagi get deploy usagi -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [ "${READY:-0}" -ge 1 ] 2>/dev/null || { R="noclient"; sleep 5; continue; }

  BODY=$(kubectl -n usagi exec deploy/usagi -- curl -sS --cacert /etc/trust/ca.crt \
    --resolve "$HOST:443:$GWIP" "https://$HOST/hostname" 2>/dev/null)
  WITHRC=$?
  [ "$WITHRC" == "0" ] || { R="stillfails"; sleep 5; continue; }
  echo "$BODY" | grep -q "hachiware" || { R="wrongbackend"; sleep 5; continue; }

  pass
done

case "$R" in
  nobundle) fail \
    "There is no Bundle 'chiikawa-ca-bundle' with a Secret source." \
    "" \
    "  kubectl get bundle" \
    "" \
    "  https://cert-manager.io/docs/trust/trust-manager/" ;;
  wrongsource) fail \
    "The Bundle's source is '${SRC:-<none>}', not 'chiikawa-ca-key-pair tls.crt'." \
    "" \
    "The same Secret cert-manager already reads for signing has the CA" \
    "certificate under tls.crt -- no new Secret is needed:" \
    "  kubectl get bundle chiikawa-ca-bundle -o jsonpath='{.spec.sources}'" ;;
  wrongtargetkey) fail \
    "The Bundle's target ConfigMap key is '${TARGETKEY:-<none>}', not 'ca.crt'." \
    "" \
    "Usagi's Pod mounts the ConfigMap and expects a file named ca.crt at" \
    "/etc/trust -- the target key is that filename:" \
    "  kubectl get bundle chiikawa-ca-bundle -o jsonpath='{.spec.target}'" ;;
  noselector) fail \
    "The Bundle has no namespaceSelector matching chiikawa.lab/trust-bundle=true." \
    "" \
    "With no namespaceSelector at all, a Bundle targets *every* namespace --" \
    "that is not 'select nothing', it is 'select everything':" \
    "  kubectl get bundle chiikawa-ca-bundle -o jsonpath='{.spec.target.namespaceSelector}'" ;;
  notsynced) fail \
    "Bundle 'chiikawa-ca-bundle' is not Synced (Synced=${SYNCED:-<none>})." \
    "" \
    "What it says:" \
    "  ${SYNCMSG:-<no message yet>}" ;;
  toobroad) fail \
    "Namespace 'chiikawa' has the Bundle's ConfigMap, and it was never labeled." \
    "" \
    "That only happens with no namespaceSelector, or one that matches too much." \
    "Fix spec.target.namespaceSelector.matchLabels and re-apply the Bundle:" \
    "  kubectl get bundle chiikawa-ca-bundle -o jsonpath='{.spec.target.namespaceSelector}'" ;;
  unlabeled) fail \
    "Namespace '${UNLABELED}' is missing the label chiikawa.lab/trust-bundle=true." \
    "" \
    "  kubectl label namespace ${UNLABELED} chiikawa.lab/trust-bundle=true" ;;
  missingcm) fail \
    "Namespace '${MISSINGNS}' is labeled, but has no ConfigMap 'chiikawa-ca-bundle' yet." \
    "" \
    "  kubectl get bundle chiikawa-ca-bundle -o jsonpath='{.status.conditions}'" \
    "  kubectl -n ${MISSINGNS} get configmap" ;;
  wrongcm) fail \
    "Namespace '${WRONGNS}' has the ConfigMap, but its ca.crt does not match" \
    "this cluster's CA." \
    "" \
    "  kubectl -n ${WRONGNS} get configmap chiikawa-ca-bundle -o jsonpath='{.data.ca\\.crt}' | openssl x509 -noout -subject -issuer" ;;
  nogateway) fail \
    "There is no Gateway data plane to talk to -- finish step 2 first." \
    "" \
    "  kubectl -n chiikawa get gateway,svc" ;;
  noclient) fail \
    "The usagi Deployment has no ready replica." \
    "" \
    "  kubectl apply -f /root/usagi.yaml" \
    "  kubectl -n usagi describe pod -l app=usagi | tail -20" ;;
  stillfails) fail \
    "From inside the Pod, the request against /etc/trust/ca.crt still fails (curl exit ${WITHRC})." \
    "" \
    "  kubectl -n usagi exec deploy/usagi -- curl -sS --cacert /etc/trust/ca.crt --resolve hachiware.chiikawa.lab:443:${GWIP} https://hachiware.chiikawa.lab/hostname" \
    "" \
    "Give the volume a moment to catch up with the new ConfigMap -- kubelet" \
    "syncs mounted ConfigMaps on its own schedule, not instantly:" \
    "  kubectl -n usagi exec deploy/usagi -- cat /etc/trust/ca.crt" ;;
  wrongbackend) fail \
    "The in-cluster request succeeded but the reply did not come from hachiware." \
    "" \
    "  body: ${BODY:-<empty>}" ;;
  *) fail "Unexpected state -- rerun the check." ;;
esac
