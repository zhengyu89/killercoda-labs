#!/bin/bash
#
# Every exit path below says why. Killercoda only reads the exit code, so the
# explanation is written to /root/.check and the learner reads it with `why`.
# The loop records the condition it is still waiting on in R, and if it runs
# out of attempts that is what the learner is told.
LOG=/root/.check
STEP="Step 2 · Ask it for a certificate"
: > "$LOG"
fail() { { echo "x $STEP"; echo; printf '%s\n' "$@"; } | tee "$LOG"; exit 1; }
pass() { echo "OK $STEP -- passed." | tee "$LOG"; exit 0; }
R=""

for _ in $(seq 1 18); do
  SECNAME=$(kubectl -n chiikawa get certificate hachiware-cert \
    -o jsonpath='{.spec.secretName}' 2>/dev/null)
  [ -n "$SECNAME" ] || { R="nocert"; sleep 5; continue; }
  [ "$SECNAME" == "hachiware-tls" ] || { R="wrongsecret"; sleep 5; continue; }

  REF=$(kubectl -n chiikawa get certificate hachiware-cert \
    -o jsonpath='{.spec.issuerRef.name}' 2>/dev/null)
  KIND=$(kubectl -n chiikawa get certificate hachiware-cert \
    -o jsonpath='{.spec.issuerRef.kind}' 2>/dev/null)
  [ "$REF" == "chiikawa-ca-issuer" ] || { R="wrongissuer"; sleep 5; continue; }
  [ "$KIND" == "ClusterIssuer" ] || { R="wrongkind"; sleep 5; continue; }

  DNS=$(kubectl -n chiikawa get certificate hachiware-cert \
    -o jsonpath='{.spec.dnsNames}' 2>/dev/null)
  echo "$DNS" | grep -q "hachiware.chiikawa.lab" || { R="dnsnames"; sleep 5; continue; }

  CREADY=$(kubectl -n chiikawa get certificate hachiware-cert \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  CRMSG=$(kubectl -n chiikawa get certificaterequest \
    -o jsonpath='{.items[-1:].status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)
  [ "$CREADY" == "True" ] || { R="certnotready"; sleep 5; continue; }

  LEAF=$(kubectl -n chiikawa get secret hachiware-tls \
    -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null)
  echo "$LEAF" | grep -q "BEGIN CERTIFICATE" || { R="nosecret"; sleep 5; continue; }

  # Derive the signer from the certificate itself rather than trusting
  # issuerRef -- a leaf signed by something else would otherwise pass on the
  # strength of a name in a field.
  LISS=$(echo "$LEAF" | openssl x509 -noout -issuer 2>/dev/null)
  echo "$LISS" | grep -q "chiikawa-root-ca" || { R="notsignedbyca"; sleep 5; continue; }

  SAN=$(echo "$LEAF" | openssl x509 -noout -ext subjectAltName 2>/dev/null)
  echo "$SAN" | grep -q "DNS:hachiware.chiikawa.lab" || { R="nosan"; sleep 5; continue; }

  kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data.ca\.crt}' 2>/dev/null \
    | grep -q . || { R="nocacrt"; sleep 5; continue; }

  pass
done

case "$R" in
  nocert) fail \
    "There is no Certificate 'hachiware-cert' in namespace chiikawa." \
    "" \
    "  kubectl -n chiikawa get certificate" \
    "" \
    "  https://cert-manager.io/docs/usage/certificate/" ;;
  wrongsecret) fail \
    "'hachiware-cert' writes to Secret '${SECNAME}', not 'hachiware-tls'." \
    "" \
    "Step 3's Gateway listener references that Secret by name." ;;
  wrongissuer) fail \
    "'hachiware-cert' names issuer '${REF:-<none>}', not 'chiikawa-ca-issuer'." \
    "" \
    "  kubectl -n chiikawa get certificate hachiware-cert -o jsonpath='{.spec.issuerRef}'" ;;
  wrongkind) fail \
    "issuerRef.kind is '${KIND:-<empty>}', which means an Issuer in namespace chiikawa." \
    "" \
    "There is no such Issuer -- yours is cluster-scoped. issuerRef has no" \
    "namespace field, so kind is the only thing distinguishing the two:" \
    "  kubectl explain certificate.spec.issuerRef" ;;
  dnsnames) fail \
    "'hachiware-cert' does not ask for hachiware.chiikawa.lab." \
    "" \
    "  dnsNames now: ${DNS:-<none>}" \
    "" \
    "That is the name the Gateway listener will serve and the name the client" \
    "will ask for in step 4. A certificate for any other name fails there, and" \
    "the failure looks nothing like this one." ;;
  certnotready) fail \
    "'hachiware-cert' is not Ready (Ready=${CREADY:-<none>})." \
    "" \
    "The Certificate is a standing wish; each attempt to grant it is a" \
    "CertificateRequest, and that is where the reason is written:" \
    "  kubectl -n chiikawa describe certificaterequest" \
    "" \
    "Latest request says:" \
    "  ${CRMSG:-<nothing yet>}" ;;
  nosecret) fail \
    "Certificate 'hachiware-cert' is Ready but Secret 'hachiware-tls' has no" \
    "readable tls.crt." \
    "" \
    "  kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data}' | tr ',' '\\n'" ;;
  notsignedbyca) fail \
    "The certificate in 'hachiware-tls' was not signed by your CA." \
    "" \
    "  issuer on the actual certificate: ${LISS:-<could not read it>}" \
    "" \
    "It should read CN=chiikawa-root-ca. A selfSigned issuer would produce a" \
    "working Ready certificate that nothing else in this lab can trust:" \
    "  kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data.tls\\.crt}' | base64 -d | openssl x509 -noout -issuer -subject" ;;
  nosan) fail \
    "The issued certificate has no subjectAltName for hachiware.chiikawa.lab." \
    "" \
    "  ${SAN:-<no subjectAltName at all>}" \
    "" \
    "Clients match the requested hostname against the SANs; a commonName alone" \
    "has not been accepted by anything modern for years." ;;
  nocacrt) fail \
    "Secret 'hachiware-tls' has no ca.crt key." \
    "" \
    "  kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data}' | tr ',' '\\n'" \
    "" \
    "A ca issuer publishes the signing certificate alongside the leaf, and steps" \
    "4 and 5 both need it. If it is absent, this Secret was not written by" \
    "cert-manager from a ca issuer at all." ;;
  *) fail "Unexpected state -- rerun the check." ;;
esac
