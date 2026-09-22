#!/bin/bash
#
# Every exit path below says why. Killercoda only reads the exit code, so the
# explanation is written to /root/.check and the learner reads it with `why`.
# The loop records the condition it is still waiting on in R, and if it runs
# out of attempts that is what the learner is told.
LOG=/root/.check
STEP="Step 1 · Create the Chiikawa Bakery CA"
: > "$LOG"
fail() { { echo "x $STEP"; echo; printf '%s\n' "$@"; } | tee "$LOG"; exit 1; }
pass() { echo "OK $STEP -- passed." | tee "$LOG"; exit 0; }
R=""

for _ in $(seq 1 18); do
  TYPE=$(kubectl -n cert-manager get secret chiikawa-ca-key-pair \
    -o jsonpath='{.type}' 2>/dev/null)
  if [ -z "$TYPE" ]; then
    ELSEWHERE=$(kubectl get secret --all-namespaces \
      -o jsonpath='{range .items[?(@.metadata.name=="chiikawa-ca-key-pair")]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | tr '\n' ' ')
    R="nosecret"; sleep 5; continue
  fi
  [ "$TYPE" == "kubernetes.io/tls" ] || { R="wrongtype"; sleep 5; continue; }

  CRT=$(kubectl -n cert-manager get secret chiikawa-ca-key-pair \
    -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null)
  echo "$CRT" | grep -q "BEGIN CERTIFICATE" || { R="nocrt"; sleep 5; continue; }
  kubectl -n cert-manager get secret chiikawa-ca-key-pair \
    -o jsonpath='{.data.tls\.key}' 2>/dev/null | grep -q . || { R="nokey"; sleep 5; continue; }

  SUBJ=$(echo "$CRT" | openssl x509 -noout -subject 2>/dev/null)
  ISS=$(echo "$CRT" | openssl x509 -noout -issuer 2>/dev/null)
  BC=$(echo "$CRT" | openssl x509 -noout -ext basicConstraints 2>/dev/null)

  echo "$SUBJ" | grep -q "CN *= *chiikawa-root-ca" || { R="badcn"; sleep 5; continue; }
  echo "$BC" | grep -q "CA:TRUE" || { R="notca"; sleep 5; continue; }
  [ "${SUBJ#subject=}" == "${ISS#issuer=}" ] || { R="notselfsigned"; sleep 5; continue; }

  REFSECRET=$(kubectl get clusterissuer chiikawa-ca-issuer \
    -o jsonpath='{.spec.ca.secretName}' 2>/dev/null)
  [ -n "$REFSECRET" ] || { R="noissuer"; sleep 5; continue; }
  [ "$REFSECRET" == "chiikawa-ca-key-pair" ] || { R="wrongsecretname"; sleep 5; continue; }

  IREADY=$(kubectl get clusterissuer chiikawa-ca-issuer \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  IMSG=$(kubectl get clusterissuer chiikawa-ca-issuer \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)
  [ "$IREADY" == "True" ] || { R="issuernotready"; sleep 5; continue; }

  pass
done

case "$R" in
  nosecret)
    if [ -n "${ELSEWHERE// /}" ]; then
      fail \
        "There is no Secret 'chiikawa-ca-key-pair' in namespace cert-manager." \
        "" \
        "There is one in: ${ELSEWHERE}" \
        "" \
        "A ClusterIssuer has no namespace of its own, so it cannot resolve a" \
        "secretName against yours. cert-manager reads every Secret a ClusterIssuer" \
        "names from one fixed namespace, and will not tell you which one:" \
        "  kubectl -n cert-manager get deploy cert-manager -o jsonpath='{.spec.template.spec.containers[0].args}' | tr ',' '\\n'" \
        "" \
        "Recreate it there:" \
        "  kubectl create secret tls chiikawa-ca-key-pair --cert=/root/ca/ca.crt --key=/root/ca/ca.key -n cert-manager"
    else
      fail \
        "There is no Secret 'chiikawa-ca-key-pair' anywhere in the cluster." \
        "" \
        "Make the keypair with openssl first, then:" \
        "  kubectl create secret tls chiikawa-ca-key-pair --cert=<ca.crt> --key=<ca.key> -n cert-manager" \
        "" \
        "  https://cert-manager.io/docs/configuration/ca/"
    fi ;;
  wrongtype) fail \
    "'chiikawa-ca-key-pair' is type '${TYPE}', not kubernetes.io/tls." \
    "" \
    "cert-manager reads the keys 'tls.crt' and 'tls.key'. 'kubectl create secret" \
    "tls' writes exactly those; 'kubectl create secret generic' will not, unless" \
    "you name them yourself:" \
    "  kubectl -n cert-manager delete secret chiikawa-ca-key-pair" \
    "  kubectl create secret tls chiikawa-ca-key-pair --cert=/root/ca/ca.crt --key=/root/ca/ca.key -n cert-manager" ;;
  nocrt) fail \
    "The Secret has no readable certificate under tls.crt." \
    "" \
    "  kubectl -n cert-manager get secret chiikawa-ca-key-pair -o jsonpath='{.data}' | tr ',' '\\n'" ;;
  nokey) fail \
    "The Secret has a certificate but no tls.key." \
    "" \
    "A ca issuer signs -- it needs the private key, not just the certificate." ;;
  badcn) fail \
    "The CA certificate's common name is not 'chiikawa-root-ca'." \
    "" \
    "  it is: ${SUBJ:-<could not read it>}" \
    "" \
    "Regenerate it with -subj \"/CN=chiikawa-root-ca/O=Nantoka Bakery\", then" \
    "replace the Secret. Later steps match on this name." ;;
  notca) fail \
    "The certificate in the Secret is not a CA certificate." \
    "" \
    "  basicConstraints: ${BC:-<none at all>}" \
    "" \
    "A certificate without CA:TRUE cannot sign anything, and every verifier" \
    "checks that bit before it will accept a signature from this key. Add it at" \
    "generation time -- it cannot be added afterwards:" \
    "  openssl req -x509 ... -addext \"basicConstraints=critical,CA:TRUE\" -addext \"keyUsage=critical,keyCertSign,cRLSign\"" ;;
  notselfsigned) fail \
    "The certificate is not self-signed -- its issuer is not itself." \
    "" \
    "  subject: ${SUBJ}" \
    "  issuer:  ${ISS}" \
    "" \
    "'openssl req -x509' produces a root: no CSR, no second party, the key signs" \
    "a certificate for itself." ;;
  noissuer) fail \
    "There is no ClusterIssuer 'chiikawa-ca-issuer' with a spec.ca.secretName." \
    "" \
    "It has to be of type 'ca' -- backed by a keypair that already exists -- not" \
    "selfSigned, which would invent a new unrelated root per certificate:" \
    "  kubectl get clusterissuer" \
    "  kubectl explain clusterissuer.spec.ca" \
    "" \
    "  https://cert-manager.io/docs/configuration/ca/" ;;
  wrongsecretname) fail \
    "'chiikawa-ca-issuer' points at Secret '${REFSECRET}', not 'chiikawa-ca-key-pair'." \
    "" \
    "  kubectl get clusterissuer chiikawa-ca-issuer -o jsonpath='{.spec.ca}'" ;;
  issuernotready) fail \
    "ClusterIssuer 'chiikawa-ca-issuer' is not Ready (Ready=${IREADY:-<none>})." \
    "" \
    "What it says:" \
    "  ${IMSG:-<no message yet>}" \
    "" \
    "If that reads 'secrets ... not found', notice the namespace it does NOT" \
    "name. If it complains about the keypair itself, the certificate and the key" \
    "in the Secret are not a matching pair:" \
    "  openssl x509 -in /root/ca/ca.crt -noout -modulus | openssl md5" \
    "  openssl rsa -in /root/ca/ca.key -noout -modulus | openssl md5" ;;
  *) fail "Unexpected state -- rerun the check." ;;
esac
