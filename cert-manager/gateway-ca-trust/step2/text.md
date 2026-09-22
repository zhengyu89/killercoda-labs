
📜 **The CA exists and cert-manager trusts it to sign. Nothing has asked it for anything yet.**

Write a `Certificate` in namespace **`chiikawa`**:

- named `hachiware-cert`
- for the DNS name `hachiware.chiikawa.lab`
- writing its result to a Secret called `hachiware-tls`
- issued by the `ClusterIssuer` you built in step 1

Reference: [cert-manager: Certificate resources](https://cert-manager.io/docs/usage/certificate/).

The check for this step is the one you would use in real life — **the Secret appears, and the certificate inside it was signed by your CA**:

```plain
kubectl -n chiikawa get certificate,secret hachiware-tls
```{{exec}}

> **If CHECK does not pass**, run `why`{{exec}} — it prints the exact condition that was not met, and usually the command that shows you why.

<br>

<details><summary>Tip</summary>

`issuerRef` has no namespace field. A `Certificate` may name an `Issuer` in its own namespace, or a `ClusterIssuer` in none — and yours is the second, so `kind: ClusterIssuer` is not optional decoration.

If the `Certificate` sits there saying it is issuing, it is not the object with the answer on it. Every attempt to satisfy a `Certificate` creates a `CertificateRequest`, and the failure is recorded there:

```plain
kubectl -n chiikawa describe certificaterequest
```{{exec}}

</details>

<details><summary>Solution</summary>

```plain
kubectl apply -f - <<'YAML'
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
YAML
```{{exec}}

```plain
kubectl -n chiikawa get certificate hachiware-cert
```{{exec}}

The Secret it wrote:

```plain
kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data}' | tr ',' '\n'
```{{exec}}

Three keys, and the third one is the point of this step:

- `tls.key` — the leaf's private key. Generated **in the cluster**, for this certificate, and never sent anywhere.
- `tls.crt` — the leaf certificate, signed by `chiikawa-root-ca`.
- `ca.crt` — the certificate of whatever signed it. A `ca` issuer publishes it; a public ACME issuer generally will not, because the chain is already in every trust store on earth. Steps 4 and 5 are both about this file.

Look at what your CA actually signed:

```plain
kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data.tls\.crt}' | base64 -d \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName -ext basicConstraints
```{{exec}}

`issuer=CN=chiikawa-root-ca, O=Nantoka Bakery`, a `subjectAltName` of `DNS:hachiware.chiikawa.lab`, `CA:FALSE`, and 90 days of life rather than your CA's ten years. Note what did **not** happen: nothing in namespace `chiikawa` can read the CA's private key, and nothing needed to. The CSR went to cert-manager, the signature came back, and the key that made it never left the `cert-manager` namespace.

The 90 days are cert-manager's default, not a property of your CA, and cert-manager will renew at two-thirds of that without being asked.

</details>
