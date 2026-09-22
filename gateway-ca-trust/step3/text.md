
## 🔒 Understand Client Trust

📚 **Reference:**
- [cert-manager: CA issuers](https://cert-manager.io/docs/configuration/ca/)
- [OpenSSL `x509` command](https://docs.openssl.org/master/man1/openssl-x509/)

Everything is correct, and it fails anyway. The certificate is valid, the Gateway serves it, the route is attached, the backend is up. Make a request:

```plain
visit
```{{exec}}

That fails, and **nothing is wrong with it**. The server is serving exactly what step 2 built:

```plain
servedcert
```{{exec}}

`curl` exit code 60 is `SSL certificate problem: unable to get local issuer certificate`. It is not a server error and it has no HTTP status code, because the request was never sent — the client hung up during the handshake. Nothing has ever given this machine a reason to believe `chiikawa-root-ca`: you made that CA yourself, on this same box, and the system trust store has never heard of it.

### 🎯 Your Task: find the file that fixes it

You have the certificate in more than one place. Compare them:

```plain
openssl x509 -in /root/ca/ca.crt -noout -fingerprint -sha256
```{{exec}}

```plain
kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -noout -fingerprint -sha256
```{{exec}}

```plain
kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -enddate -ext basicConstraints
```{{exec}}

**Two of these three will make `curl` succeed. Only one is the right answer**, and the check knows the difference. Work out which, write it to `/root/answers/ca.crt`, and prove it:

```plain
visit /root/answers/ca.crt
```{{exec}}

A pass here is the response body coming back — `hachiware-...`, the backend Pod's own name, over HTTPS.

> **If CHECK does not pass**, run `why`{{exec}} — it prints the exact condition that was not met, and usually the command that shows you why.

<br>

<details><summary>✅ Solution (try it yourself first!)</summary>

```plain
kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > /root/answers/ca.crt
```{{exec}}

(`cp /root/ca/ca.crt /root/answers/ca.crt` is the same file — the CA you generated, and the CA cert-manager published next to the leaf, are one certificate. Their fingerprints from the two commands above should match.)

```plain
visit /root/answers/ca.crt
```{{exec}}

Nothing changed on the server between the two `visit` calls. Same nginx, same listener, same certificate on the wire, same connection. The only thing that moved was **what the client was willing to believe**, and it moved because you handed it one file. That is the whole of "HTTPS fails without the CA, and succeeds with it": a TLS failure of this kind is never repaired on the server, because the server was never the problem.

**Why not `tls.crt`.** Handing the client the leaf also works — OpenSSL will anchor on the exact certificate presented, so `curl` returns 200 and the setup looks finished. It is a trap rather than an alternative: the leaf is `CA:FALSE` and expires in 90 days, and cert-manager will replace it at 60. A trust store built out of leaves has to be rebuilt on every renewal, of every service, separately — and it grants trust to exactly one certificate rather than to the authority that issues them. The CA is `CA:TRUE`, lives ten years, and covers every certificate it will ever sign, including ones that do not exist yet. That is what makes steps 4 and 5 possible at all.

</details>
