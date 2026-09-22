
## 📜 The Gateway Asks for Its Certificate

📚 **Reference:**
- [cert-manager: Certificate resources](https://cert-manager.io/docs/usage/certificate/)
- [Gateway API: TLS configuration](https://gateway-api.sigs.k8s.io/guides/user-guides/tls/)

The front door is already built. Look at what's already in namespace `chiikawa`:

```plain
kubectl -n chiikawa get gateway,httproute
```{{exec}}

A `Gateway` named `chiikawa-gateway` with an HTTPS listener, and an `HTTPRoute` sending `hachiware.chiikawa.lab` to the bakery's Service — both built for you, so this lab stays about the CA and the trust chain, not Gateway API wiring. The listener already names a Secret, `hachiware-tls`, that doesn't exist:

```plain
kubectl -n chiikawa get gateway chiikawa-gateway -o jsonpath='{.status.listeners[0].conditions}' | tr ',' '\n'
```{{exec}}

`ResolvedRefs=False` — the Gateway is asking for a certificate it cannot have yet. That's your task.

### 🎯 Your Task

#### Create the Certificate

- **Name**: `hachiware-cert`
- **Namespace**: `chiikawa`
- **DNS name**: `hachiware.chiikawa.lab`
- **Secret name**: `hachiware-tls` — the exact name the listener above is waiting for
- **issuerRef**: `chiikawa-ca-issuer`, `kind: ClusterIssuer` (from step 1)

```plain
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: hachiware-cert
  namespace: chiikawa
spec:
  secretName: hachiware-tls
  dnsNames:
  - hachiware.chiikawa.lab
  issuerRef:
    name: chiikawa-ca-issuer
    kind: ClusterIssuer
EOF
```{{exec}}

`issuerRef` has no namespace field. A `Certificate` may name an `Issuer` in its own namespace, or a `ClusterIssuer` in none — yours is the second, so `kind: ClusterIssuer` is not optional decoration.

### ✅ Validate it yourself

The Certificate and the Secret it wrote:

```plain
kubectl -n chiikawa get certificate,secret hachiware-tls
```{{exec}}

What your CA actually signed — issuer, SAN, and `CA:FALSE` this time:

```plain
kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data.tls\.crt}' | base64 -d \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName -ext basicConstraints
```{{exec}}

And the same Gateway, now resolved and serving it — nothing about the Gateway was touched, it just started working the moment the Secret appeared:

```plain
kubectl -n chiikawa get gateway chiikawa-gateway
```{{exec}}

```plain
servedcert
```{{exec}}

`servedcert` is a check for this step: a handshake against the listener, showing the certificate it actually presents — no HTTP request, just the TLS layer. **Passing this step needs both**: the Secret cert-manager wrote, and the listener serving it live.

> **If CHECK does not pass**, run `why`{{exec}} — it prints the exact condition that was not met, and usually the command that shows you why.

<br>

<details><summary>Tip: if the Certificate never goes Ready</summary>

If the `Certificate` sits there saying it is issuing, it is not the object with the answer on it. Every attempt to satisfy a `Certificate` creates a `CertificateRequest`, and the failure is recorded there:

```plain
kubectl -n chiikawa describe certificaterequest
```{{exec}}

</details>

<details><summary>Tip: what the Secret actually contains</summary>

```plain
kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data}' | tr ',' '\n'
```{{exec}}

Three keys, and the third one matters for the rest of this lab:

- `tls.key` — the leaf's private key. Generated **in the cluster**, for this certificate, and never sent anywhere.
- `tls.crt` — the leaf certificate, signed by `chiikawa-root-ca`, with a 90-day life and `CA:FALSE`.
- `ca.crt` — the certificate of whatever signed it. A `ca` issuer publishes this; steps 3, 4 and 5 are all about this one file.

Nothing in namespace `chiikawa` can read the CA's private key, and nothing needed to — the CSR went to cert-manager, the signature came back, and the key that made it never left the `cert-manager` namespace.

</details>
