
## 📜 The Gateway Asks for Its Certificate

📚 **Reference:**
- [cert-manager: Certificate resources](https://cert-manager.io/docs/usage/certificate/)
- [Gateway API: TLS configuration](https://gateway-api.sigs.k8s.io/guides/user-guides/tls/)

The front door is already built. Look at what's already in namespace `chiikawa`:

```plain
kubectl -n chiikawa get gateway,httproute
```{{exec}}

A `Gateway` named `chiikawa-gateway` with an HTTPS listener, and an `HTTPRoute` sending `hachiware.chiikawa.lab` to the bakery's Service — both built for you, so this lab stays focused on the CA and the certificate, not on Gateway API setup. The listener already names a Secret, `hachiware-tls`, that doesn't exist:

```plain
kubectl -n chiikawa get gateway chiikawa-gateway -o jsonpath='{.status.listeners[0].conditions}' | tr ',' '\n'
```{{exec}}

`ResolvedRefs=False` — the Gateway is waiting for a certificate it doesn't have yet. That's your task.

### 🎯 Your Task

#### Create the Certificate

- **Name**: `hachiware-cert`
- **Namespace**: `chiikawa`
- **DNS name**: `hachiware.chiikawa.lab`
- **Secret name**: `hachiware-tls` — the exact name the listener above is waiting for
- **issuerRef**: `chiikawa-ca-issuer`, `kind: ClusterIssuer` (from step 1)

`issuerRef` has no namespace field. A `Certificate` can name an `Issuer` in its own namespace, or a `ClusterIssuer` with none — yours is the second, so `kind: ClusterIssuer` matters.

Try writing the YAML yourself first — the full command is in the **Solution** below.

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

And the same Gateway, now resolved — nothing about the Gateway was touched, it just started working the moment the Secret appeared:

```plain
kubectl -n chiikawa get gateway chiikawa-gateway
```{{exec}}

To see the certificate the Gateway is actually handing out on the wire, find the Service NGINX Gateway Fabric made for it, then connect to port 443 directly:

```plain
kubectl -n chiikawa get svc
```{{exec}}

```plain
GWIP=$(kubectl -n chiikawa get svc chiikawa-gateway-nginx -o jsonpath='{.spec.clusterIP}')
echo | openssl s_client -connect "$GWIP:443" -servername hachiware.chiikawa.lab 2>/dev/null \
  | openssl x509 -noout -issuer -subject -ext basicConstraints -ext subjectAltName
```{{exec}}

This is a real TLS handshake, no HTTP request involved — just checking what certificate the listener presents. **This step needs both**: the Secret cert-manager wrote, and the listener serving it live.

> **If CHECK does not pass**, run `why`{{exec}} — it prints the exact condition that was not met, and usually the command that shows you why.

<br>

<details><summary>✅ Solution</summary>

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

</details>

<details><summary>Tip: if the Certificate never goes Ready</summary>

If the `Certificate` sits there saying it is issuing, look at the `CertificateRequest` it created — that's where the actual reason is written:

```plain
kubectl -n chiikawa describe certificaterequest
```{{exec}}

</details>

<details><summary>Tip: what the Secret actually contains</summary>

```plain
kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data}' | tr ',' '\n'
```{{exec}}

Three keys, and the third one matters for the rest of this lab:

- `tls.key` — the leaf's private key. Made **in the cluster**, for this certificate, and never sent anywhere.
- `tls.crt` — the leaf certificate, signed by `chiikawa-root-ca`, with a 90-day life and `CA:FALSE`.
- `ca.crt` — the certificate of whatever signed it. A `ca` issuer publishes this; steps 3, 4 and 5 are all about this one file.

Nothing in namespace `chiikawa` can read the CA's private key, and nothing needed to — the request went to cert-manager, the signature came back, and the key that made it never left the `cert-manager` namespace.

</details>

<details><summary>Another way to do this: annotate the Gateway instead of writing a Certificate</summary>

This lab has you write the `Certificate` object yourself, because seeing it directly is how you learn what cert-manager is actually doing. But cert-manager can also watch a `Gateway` directly and create the `Certificate` for you, one per TLS listener, using an annotation:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: chiikawa-gateway
  annotations:
    cert-manager.io/cluster-issuer: chiikawa-ca-issuer
spec:
  gatewayClassName: nginx
  listeners:
  - name: https
    hostname: hachiware.chiikawa.lab
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
      - name: hachiware-tls
```

cert-manager sees the annotation and the listener's `certificateRefs`, and creates a matching `Certificate` on its own — same result, no separate object to write. This is **not** what this step asks you to do; it's worth knowing about for real clusters, where you may prefer one Gateway annotation over a `Certificate` per listener. See [cert-manager: securing Gateway resources](https://cert-manager.io/docs/usage/gateway/).

</details>
