
## 🔒 Understand Client Trust

📚 **Reference:**
- [cert-manager: CA issuers](https://cert-manager.io/docs/configuration/ca/)
- [OpenSSL `x509` command](https://docs.openssl.org/master/man1/openssl-x509/)

Everything is correct, and the request still fails. The certificate is valid, the Gateway serves it, the route is attached, the backend is up. Try it:

```plain
GWIP=$(kubectl -n chiikawa get svc chiikawa-gateway-nginx -o jsonpath='{.spec.clusterIP}')
curl -sS --resolve hachiware.chiikawa.lab:443:$GWIP https://hachiware.chiikawa.lab/hostname
```{{exec}}

`curl` exit code 60 is `SSL certificate problem: unable to get local issuer certificate`. This is not a server error — the request never went out, the connection was refused during the handshake. Nothing on this machine has ever been told to trust `chiikawa-root-ca`. You made that CA yourself, on this same box, a few minutes ago; the system doesn't know about it.

### 🎯 Your Task

Get the CA certificate out of the `hachiware-tls` Secret, and save it as a plain file:

- Read the `ca.crt` field from Secret `hachiware-tls` in namespace `chiikawa`
- Decode it from base64
- Save it to `/root/answers/ca.crt`

Try this yourself first — the command is in the **Solution** below.

### ✅ Validate it yourself

Run the same request again, this time telling `curl` to trust your file:

```plain
GWIP=$(kubectl -n chiikawa get svc chiikawa-gateway-nginx -o jsonpath='{.spec.clusterIP}')
curl -sS --cacert /root/answers/ca.crt --resolve hachiware.chiikawa.lab:443:$GWIP https://hachiware.chiikawa.lab/hostname
```{{exec}}

A pass is the response body coming back — `hachiware-...`, the backend Pod's own name, over HTTPS.

> **If CHECK does not pass**, run `why`{{exec}} — it prints the exact condition that was not met, and usually the command that shows you why.

<br>

<details><summary>✅ Solution</summary>

```plain
kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > /root/answers/ca.crt
```{{exec}}

Nothing changed on the server between the two `curl` calls. Same nginx, same listener, same certificate on the wire. The only thing that changed was **what the client was told to trust**, and that changed because you gave it one file.

</details>

<details><summary>Tip: why not use tls.crt instead?</summary>

The Secret also has a `tls.crt` key — the leaf certificate itself, not the CA. Using that file with `--cacert` also makes `curl` succeed today, but it's the wrong file:

```plain
kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -enddate -ext basicConstraints
```{{exec}}

`tls.crt` is `CA:FALSE` and expires in 90 days — trusting it directly means redoing this by hand every time cert-manager renews it. `ca.crt` is `CA:TRUE`, lives ten years, and covers every certificate this CA will ever sign, including ones that don't exist yet. That's the file steps 4 and 5 both build on.

</details>
