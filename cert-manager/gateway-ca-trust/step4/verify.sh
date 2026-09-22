#!/bin/bash
#
# Every exit path below says why. Killercoda only reads the exit code, so the
# explanation is written to /root/.check and the learner reads it with `why`.
# The loop records the condition it is still waiting on in R, and if it runs
# out of attempts that is what the learner is told.
LOG=/root/.check
STEP="Step 4 · The same request, twice"
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

GWIP=$(gw_ip)
HOST=hachiware.chiikawa.lab

for _ in $(seq 1 12); do
  [ -n "$GWIP" ] || { R="nogateway"; sleep 5; GWIP=$(gw_ip); continue; }

  [ -s /root/answers/ca.crt ] || { R="nofile"; sleep 5; continue; }

  SUBJ=$(openssl x509 -in /root/answers/ca.crt -noout -subject 2>/dev/null)
  [ -n "$SUBJ" ] || { R="notacert"; sleep 5; continue; }

  BC=$(openssl x509 -in /root/answers/ca.crt -noout -ext basicConstraints 2>/dev/null)
  echo "$BC" | grep -q "CA:TRUE" || { R="notca"; sleep 5; continue; }
  echo "$SUBJ" | grep -q "CN *= *chiikawa-root-ca" || { R="wrongca"; sleep 5; continue; }

  # Same certificate as the one the cluster is actually signing with, rather
  # than merely something with the right name in it.
  FP1=$(openssl x509 -in /root/answers/ca.crt -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
  FP2=$(kubectl -n cert-manager get secret chiikawa-ca-key-pair \
    -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null \
    | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
  [ -n "$FP2" ] && [ "$FP1" == "$FP2" ] || { R="notthisca"; sleep 5; continue; }

  # The positive: one request, verified against that file, end to end.
  BODY=$(curl -sS --cacert /root/answers/ca.crt --resolve "$HOST:443:$GWIP" \
    "https://$HOST/hostname" 2>/dev/null)
  WITHRC=$?
  [ "$WITHRC" == "0" ] || { R="stillfails"; sleep 5; continue; }
  echo "$BODY" | grep -q "hachiware" || { R="wrongbackend"; sleep 5; continue; }

  # The negative: the same request with nothing but the system store still has
  # to fail, or the trust being demonstrated came from somewhere else.
  curl -sS --resolve "$HOST:443:$GWIP" "https://$HOST/hostname" >/dev/null 2>&1
  BARERC=$?
  [ "$BARERC" != "0" ] || { R="alreadytrusted"; sleep 5; continue; }

  pass
done

case "$R" in
  nogateway) fail \
    "There is no Gateway data plane to talk to -- finish step 3 first." \
    "" \
    "  kubectl -n chiikawa get gateway,svc" ;;
  nofile) fail \
    "/root/answers/ca.crt does not exist, or is empty." \
    "" \
    "Write the certificate that makes the client trust this listener into that" \
    "path, then:" \
    "  visit /root/answers/ca.crt" ;;
  notacert) fail \
    "/root/answers/ca.crt is not a PEM certificate openssl can read." \
    "" \
    "  head -1 /root/answers/ca.crt" \
    "" \
    "If you piped a Secret value into it, remember it is base64 in the object:" \
    "  kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data.ca\\.crt}' | base64 -d > /root/answers/ca.crt" ;;
  notca) fail \
    "The certificate in /root/answers/ca.crt is not a CA certificate." \
    "" \
    "  subject: ${SUBJ}" \
    "  basicConstraints: ${BC:-<none>}" \
    "" \
    "This is almost certainly the leaf, tls.crt -- and 'visit' with it WORKS," \
    "which is exactly why it is worth failing you for. OpenSSL will anchor on" \
    "the exact certificate presented, so the request succeeds and the mistake is" \
    "invisible until the first renewal replaces that leaf and every client you" \
    "handed it to breaks at once." \
    "" \
    "The file that gets distributed is the one with CA:TRUE:" \
    "  kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data.ca\\.crt}' | base64 -d > /root/answers/ca.crt" ;;
  wrongca) fail \
    "The certificate is a CA, but not chiikawa-root-ca." \
    "" \
    "  subject: ${SUBJ}" ;;
  notthisca) fail \
    "That CA certificate is not the one this cluster signs with." \
    "" \
    "  yours:    ${FP1:-<none>}" \
    "  cluster:  ${FP2:-<could not read the CA Secret>}" \
    "" \
    "Two CAs with the same common name are two different authorities. If you" \
    "regenerated the keypair at some point, the Secret and your local files have" \
    "drifted apart -- take the certificate from the cluster:" \
    "  kubectl -n cert-manager get secret chiikawa-ca-key-pair -o jsonpath='{.data.tls\\.crt}' | base64 -d > /root/answers/ca.crt" ;;
  stillfails) fail \
    "The request verified against /root/answers/ca.crt still fails (curl exit ${WITHRC})." \
    "" \
    "  visit /root/answers/ca.crt" \
    "" \
    "Exit 60 with a correct CA file usually means the listener is serving a leaf" \
    "this CA did not sign. Exit 51 means the name does not match its SANs. Both" \
    "are visible in the handshake:" \
    "  servedcert" ;;
  wrongbackend) fail \
    "The request succeeded but the response did not come from hachiware." \
    "" \
    "  body: ${BODY:-<empty>}" \
    "" \
    "A 404 here is the listener terminating TLS with no route matching the" \
    "hostname -- TLS worked, routing did not:" \
    "  kubectl -n chiikawa describe httproute hachiware-route" ;;
  alreadytrusted) fail \
    "The request succeeds even with no CA file, which it must not." \
    "" \
    "Something has already been added to this machine's system trust store, or" \
    "the client is not verifying at all. This step is the difference between the" \
    "two requests, so it needs the plain one to fail:" \
    "  visit" \
    "  ls /usr/local/share/ca-certificates/" ;;
  *) fail "Unexpected state -- rerun the check." ;;
esac
