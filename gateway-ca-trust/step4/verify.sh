#!/bin/bash
#
# Every exit path below says why. Killercoda only reads the exit code, so the
# explanation is written to /root/.check and the learner reads it with `why`.
# The loop records the condition it is still waiting on in R, and if it runs
# out of attempts that is what the learner is told.
LOG=/root/.check
STEP="Step 4 · Usagi receives the CA by hand"
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

for _ in $(seq 1 24); do
  GWIP=$(gw_ip)
  [ -n "$GWIP" ] || { R="nogateway"; sleep 5; continue; }

  BUNDLE=$(kubectl -n usagi get configmap chiikawa-ca-bundle \
    -o jsonpath='{.data.ca\.crt}' 2>/dev/null)
  if [ -z "$BUNDLE" ]; then
    KEYS=$(kubectl -n usagi get configmap chiikawa-ca-bundle \
      -o jsonpath='{.data}' 2>/dev/null)
    R="nobundle"; sleep 5; continue
  fi

  # A trust bundle is copied everywhere and readable by anyone who can read a
  # ConfigMap. A private key in one is the whole CA, handed out.
  echo "$BUNDLE" | grep -q "PRIVATE KEY" && { R="haskey"; sleep 5; continue; }

  echo "$BUNDLE" | openssl x509 -noout -subject >/dev/null 2>&1 \
    || { R="notacert"; sleep 5; continue; }
  BC=$(echo "$BUNDLE" | openssl x509 -noout -ext basicConstraints 2>/dev/null)
  BSUBJ=$(echo "$BUNDLE" | openssl x509 -noout -subject 2>/dev/null)
  echo "$BC" | grep -q "CA:TRUE" || { R="notca"; sleep 5; continue; }

  FP1=$(echo "$BUNDLE" | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
  FP2=$(kubectl -n cert-manager get secret chiikawa-ca-key-pair \
    -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null \
    | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
  [ -n "$FP2" ] && [ "$FP1" == "$FP2" ] || { R="notthisca"; sleep 5; continue; }

  READY=$(kubectl -n usagi get deploy usagi \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [ "${READY:-0}" -ge 1 ] 2>/dev/null || { R="noclient"; sleep 5; continue; }

  # Trust proven from inside the cluster, by the Pod, against the file it
  # mounted -- not by the node and not by the learner's own helper.
  BODY=$(kubectl -n usagi exec deploy/usagi -- curl -sS --cacert /etc/trust/ca.crt \
    --resolve "$HOST:443:$GWIP" "https://$HOST/hostname" 2>/dev/null)
  WITHRC=$?
  [ "$WITHRC" == "0" ] || { R="stillfails"; sleep 5; continue; }
  echo "$BODY" | grep -q "hachiware" || { R="wrongbackend"; sleep 5; continue; }

  kubectl -n usagi exec deploy/usagi -- curl -sS \
    --resolve "$HOST:443:$GWIP" "https://$HOST/hostname" >/dev/null 2>&1
  BARERC=$?
  [ "$BARERC" != "0" ] || { R="alreadytrusted"; sleep 5; continue; }

  pass
done

case "$R" in
  nogateway) fail \
    "There is no Gateway data plane to talk to -- finish step 2 first." \
    "" \
    "  kubectl -n chiikawa get gateway,svc" ;;
  nobundle) fail \
    "No ConfigMap 'chiikawa-ca-bundle' in namespace usagi with a 'ca.crt' key." \
    "" \
    "  keys present: ${KEYS:-<no such ConfigMap>}" \
    "" \
    "The key name is the filename inside the container, and /root/usagi.yaml" \
    "mounts the whole ConfigMap at /etc/trust:" \
    "  kubectl -n usagi create configmap chiikawa-ca-bundle --from-file=ca.crt=/root/answers/ca.crt" ;;
  haskey) fail \
    "The bundle contains a PRIVATE KEY. Delete it now." \
    "" \
    "  kubectl -n usagi delete configmap chiikawa-ca-bundle" \
    "" \
    "A trust bundle is public by construction: copied into every namespace," \
    "mounted by every workload, readable by anyone who can read a ConfigMap." \
    "The CA's private key in one is not a leak of a certificate -- it is the" \
    "authority itself, and anything holding it can mint a certificate for any" \
    "name you own. Certificates only:" \
    "  kubectl -n usagi create configmap chiikawa-ca-bundle --from-file=ca.crt=/root/answers/ca.crt" ;;
  notacert) fail \
    "The 'ca.crt' key in the bundle is not a PEM certificate." \
    "" \
    "  kubectl -n usagi get configmap chiikawa-ca-bundle -o jsonpath='{.data.ca\\.crt}' | head -1" \
    "" \
    "If it looks like base64 rather than -----BEGIN CERTIFICATE-----, it was" \
    "copied straight out of a Secret without decoding it." ;;
  notca) fail \
    "The certificate in the bundle is not a CA certificate." \
    "" \
    "  subject: ${BSUBJ:-<none>}" \
    "  basicConstraints: ${BC:-<none>}" \
    "" \
    "Same trap as step 3, one layer further out: distributing the leaf makes" \
    "today's request work and guarantees an outage at the first renewal." ;;
  notthisca) fail \
    "The bundle does not hold the CA this cluster signs with." \
    "" \
    "  bundle:   ${FP1:-<none>}" \
    "  cluster:  ${FP2:-<could not read the CA Secret>}" ;;
  noclient) fail \
    "The usagi Deployment has no ready replica." \
    "" \
    "  kubectl apply -f /root/usagi.yaml" \
    "  kubectl -n usagi describe pod -l app=usagi | tail -20" \
    "" \
    "A Pod whose volume names a ConfigMap that does not exist does not crash --" \
    "it waits in ContainerCreating indefinitely, with the reason on the Pod's" \
    "events and nowhere else." ;;
  stillfails) fail \
    "From inside the Pod, the request against /etc/trust/ca.crt still fails (curl exit ${WITHRC})." \
    "" \
    "  kubectl -n usagi exec deploy/usagi -- curl -sS --cacert /etc/trust/ca.crt --resolve hachiware.chiikawa.lab:443:${GWIP} https://hachiware.chiikawa.lab/hostname" \
    "" \
    "Check what actually landed in the container, and under what name:" \
    "  kubectl -n usagi exec deploy/usagi -- ls -l /etc/trust" ;;
  wrongbackend) fail \
    "The in-cluster request succeeded but the reply did not come from hachiware." \
    "" \
    "  body: ${BODY:-<empty>}" ;;
  alreadytrusted) fail \
    "The in-cluster request succeeds with no CA file at all, which it must not." \
    "" \
    "This step is the difference between the two requests. If the plain one" \
    "passes, the image's trust store already contains your CA, or the Pod is" \
    "reaching something other than the Gateway:" \
    "  kubectl -n usagi exec deploy/usagi -- curl -sS --resolve hachiware.chiikawa.lab:443:${GWIP} https://hachiware.chiikawa.lab/hostname" ;;
  *) fail "Unexpected state -- rerun the check." ;;
esac
