#!/bin/bash
#
# Every exit path below says why. Killercoda only reads the exit code, so the
# explanation is written to /root/.check and the learner reads it with `why`.
# The loop records the condition it is still waiting on in R, and if it runs
# out of attempts that is what the learner is told.
LOG=/root/.check
STEP="Step 3 · Put it on a listener"
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

for _ in $(seq 1 24); do
  GWCLASS=$(kubectl -n chiikawa get gateway chiikawa-gateway \
    -o jsonpath='{.spec.gatewayClassName}' 2>/dev/null)
  [ -n "$GWCLASS" ] || { R="nogateway"; sleep 5; continue; }
  [ "$GWCLASS" == "nginx" ] || { R="wrongclass"; sleep 5; continue; }

  PROTO=$(kubectl -n chiikawa get gateway chiikawa-gateway \
    -o jsonpath='{.spec.listeners[?(@.port==443)].protocol}' 2>/dev/null)
  [ "$PROTO" == "HTTPS" ] || { R="nohttps"; sleep 5; continue; }

  TLSMODE=$(kubectl -n chiikawa get gateway chiikawa-gateway \
    -o jsonpath='{.spec.listeners[?(@.port==443)].tls.mode}' 2>/dev/null)
  [ -z "$TLSMODE" ] || [ "$TLSMODE" == "Terminate" ] || { R="wrongmode"; sleep 5; continue; }

  CERTREF=$(kubectl -n chiikawa get gateway chiikawa-gateway \
    -o jsonpath='{.spec.listeners[?(@.port==443)].tls.certificateRefs[*].name}' 2>/dev/null)
  echo "$CERTREF" | grep -q "hachiware-tls" || { R="nocertref"; sleep 5; continue; }

  LCONDS=$(kubectl -n chiikawa get gateway chiikawa-gateway \
    -o jsonpath='{range .status.listeners[*]}{.name}{"="}{range .conditions[*]}{.type}:{.status}{" "}{end}{"\n"}{end}' 2>/dev/null)
  RESOLVED=$(kubectl -n chiikawa get gateway chiikawa-gateway \
    -o jsonpath='{.status.listeners[*].conditions[?(@.type=="ResolvedRefs")].status}' 2>/dev/null)
  echo "$RESOLVED" | grep -q "True" || { R="unresolved"; sleep 5; continue; }

  RPARENT=$(kubectl -n chiikawa get httproute hachiware-route \
    -o jsonpath='{.spec.parentRefs[*].name}' 2>/dev/null)
  [ -n "$RPARENT" ] || { R="noroute"; sleep 5; continue; }
  echo "$RPARENT" | grep -q "chiikawa-gateway" || { R="wrongparent"; sleep 5; continue; }

  RACCEPT=$(kubectl -n chiikawa get httproute hachiware-route \
    -o jsonpath='{.status.parents[*].conditions[?(@.type=="Accepted")].status}' 2>/dev/null)
  RMSG=$(kubectl -n chiikawa get httproute hachiware-route \
    -o jsonpath='{.status.parents[*].conditions[?(@.type=="Accepted")].message}' 2>/dev/null)
  echo "$RACCEPT" | grep -q "True" || { R="routenotaccepted"; sleep 5; continue; }

  BACKEND=$(kubectl -n chiikawa get httproute hachiware-route \
    -o jsonpath='{.spec.rules[*].backendRefs[*].name}' 2>/dev/null)
  echo "$BACKEND" | grep -q "hachiware" || { R="wrongbackend"; sleep 5; continue; }

  GWIP=$(gw_ip)
  [ -n "$GWIP" ] || { R="nodataplane"; sleep 5; continue; }

  # The only claim that cannot be faked by a well-formed object graph: what
  # comes back on the wire when something actually connects.
  SERVED=$(echo | timeout 5 openssl s_client -connect "$GWIP:443" \
    -servername hachiware.chiikawa.lab 2>/dev/null \
    | openssl x509 -noout -issuer -ext subjectAltName 2>/dev/null)
  echo "$SERVED" | grep -q "chiikawa-root-ca" || { R="nohandshake"; sleep 5; continue; }
  echo "$SERVED" | grep -q "DNS:hachiware.chiikawa.lab" || { R="wrongsan"; sleep 5; continue; }

  pass
done

case "$R" in
  nogateway) fail \
    "There is no Gateway 'chiikawa-gateway' in namespace chiikawa." \
    "" \
    "  kubectl get gatewayclass" \
    "  kubectl -n chiikawa get gateway" \
    "" \
    "  https://gateway-api.sigs.k8s.io/reference/api-types/gateway/" ;;
  wrongclass) fail \
    "'chiikawa-gateway' asks for gatewayClassName '${GWCLASS}'." \
    "" \
    "The only class with a controller behind it here is 'nginx'. A Gateway on a" \
    "class nobody implements stays in Unknown forever and nothing tells you:" \
    "  kubectl get gatewayclass nginx -o jsonpath='{.spec.controllerName}'" ;;
  nohttps) fail \
    "'chiikawa-gateway' has no HTTPS listener on port 443 (protocol=${PROTO:-<none>})." \
    "" \
    "  kubectl -n chiikawa get gateway chiikawa-gateway -o jsonpath='{.spec.listeners}'" \
    "" \
    "A listener of protocol HTTP on 443 is legal and will not terminate" \
    "anything -- the port number carries no meaning by itself." ;;
  wrongmode) fail \
    "The listener's tls.mode is '${TLSMODE}', not Terminate." \
    "" \
    "Passthrough hands the encrypted bytes to the backend untouched, which means" \
    "the Gateway never uses the Secret at all -- and on most controllers an" \
    "HTTPRoute cannot attach to such a listener:" \
    "  https://gateway-api.sigs.k8s.io/guides/user-guides/tls/" ;;
  nocertref) fail \
    "The 443 listener does not reference Secret 'hachiware-tls'." \
    "" \
    "  certificateRefs now: ${CERTREF:-<none>}" \
    "" \
    "  kubectl -n chiikawa get gateway chiikawa-gateway -o jsonpath='{.spec.listeners[*].tls}'" ;;
  unresolved) fail \
    "The listener's references did not resolve (ResolvedRefs is not True)." \
    "" \
    "Per-listener conditions:" \
    "  ${LCONDS:-<none reported yet>}" \
    "" \
    "The Secret has to exist in the Gateway's own namespace and be a TLS Secret." \
    "A certificateRef pointing into another namespace needs a ReferenceGrant" \
    "there, and fails exactly like this without one:" \
    "  kubectl -n chiikawa describe gateway chiikawa-gateway" ;;
  noroute) fail \
    "There is no HTTPRoute 'hachiware-route' in namespace chiikawa." \
    "" \
    "The listener can complete a handshake with no route attached, and then" \
    "return 404 to every request. Both objects are needed:" \
    "  https://gateway-api.sigs.k8s.io/reference/api-types/httproute/" ;;
  wrongparent) fail \
    "'hachiware-route' attaches to '${RPARENT}', not to 'chiikawa-gateway'." \
    "" \
    "  kubectl -n chiikawa get httproute hachiware-route -o jsonpath='{.spec.parentRefs}'" ;;
  routenotaccepted) fail \
    "'hachiware-route' was not accepted by the Gateway (Accepted=${RACCEPT:-<none>})." \
    "" \
    "What the parent says:" \
    "  ${RMSG:-<nothing yet>}" \
    "" \
    "A hostname on the route that does not intersect the listener's hostname is" \
    "the usual cause, and it is reported here rather than at apply time:" \
    "  kubectl -n chiikawa describe httproute hachiware-route" ;;
  wrongbackend) fail \
    "'hachiware-route' does not send traffic to the 'hachiware' Service." \
    "" \
    "  backendRefs now: ${BACKEND:-<none>}" ;;
  nodataplane) fail \
    "No nginx data plane Service exists for this Gateway yet." \
    "" \
    "NGINX Gateway Fabric creates a Deployment and a Service per Gateway, in the" \
    "Gateway's namespace, named after it:" \
    "  kubectl -n chiikawa get deploy,svc,pods" \
    "  kubectl -n nginx-gateway logs deploy/ngf-nginx-gateway-fabric --tail=30" ;;
  nohandshake) fail \
    "Nothing served a certificate from your CA on port 443." \
    "" \
    "  gateway address: ${GWIP:-<none>}" \
    "  handshake returned: ${SERVED:-<no certificate at all>}" \
    "" \
    "Try it by hand and read the whole thing:" \
    "  servedcert" \
    "  kubectl -n chiikawa get pods" ;;
  wrongsan) fail \
    "The listener is serving a certificate without a SAN for hachiware.chiikawa.lab." \
    "" \
    "  ${SERVED}" \
    "" \
    "The listener is using some other Secret than the one step 2 produced." ;;
  *) fail "Unexpected state -- rerun the check." ;;
esac
