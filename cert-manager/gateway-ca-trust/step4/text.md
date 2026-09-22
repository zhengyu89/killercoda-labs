
🔒 **Everything is correct. And it fails anyway.**

The certificate is valid, the listener serves it, the route is attached, the backend is up. Make a request:

```plain
visit
```{{exec}}

That fails, and **nothing is wrong with it**. The server is serving exactly what you built:

```plain
servedcert
```{{exec}}

Work out which side is refusing and why, then **write the certificate that fixes it to `/root/answers/ca.crt`** and prove it:

```plain
visit /root/answers/ca.crt
```{{exec}}

A pass here is the response body coming back — `hachiware-...`, the backend Pod's own name, over HTTPS.

Two different files on this machine will make that request succeed. **Only one of them is the answer**, and the check knows the difference.

> **If CHECK does not pass**, run `why`{{exec}} — it prints the exact condition that was not met, and usually the command that shows you why.

<br>

<details><summary>Tip</summary>

`curl` exit code 60 is `SSL certificate problem: unable to get local issuer certificate`. It is not a server error and it has no HTTP status code, because the request was never sent — the client hung up during the handshake.

Nothing has ever given this machine a reason to believe `chiikawa-root-ca`. You made that CA half an hour ago on this same box; the system trust store has never heard of it.

You have the certificate in two places, and they are the same bytes:

```plain
openssl x509 -in /root/ca/ca.crt -noout -fingerprint -sha256
```{{exec}}

```plain
kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -noout -fingerprint -sha256
```{{exec}}

And `tls.crt` from that same Secret will *also* make `curl` succeed. Compare the three before you choose:

```plain
kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -enddate -ext basicConstraints
```{{exec}}

</details>

<details><summary>Solution</summary>

```plain
kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > /root/answers/ca.crt
```{{exec}}

(`cp /root/ca/ca.crt /root/answers/ca.crt` is the same file — the CA you generated, and the CA cert-manager published next to the leaf, are one certificate.)

```plain
visit /root/answers/ca.crt
```{{exec}}

Nothing changed on the server between the two requests. Same nginx, same listener, same certificate on the wire, same connection. The only thing that moved was **what the client was willing to believe**, and it moved because you handed it one file.

That is the whole of "HTTPS fails without the CA, and succeeds with it": a TLS failure of this kind is never repaired on the server, because the server was never the problem.

**Why not `tls.crt`.** Handing the client the leaf also works — OpenSSL will anchor on the exact certificate presented, so `curl` returns 200 and the setup looks finished. It is a trap rather than an alternative:

```plain
kubectl -n chiikawa get secret hachiware-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -enddate -ext basicConstraints
```{{exec}}

```plain
openssl x509 -in /root/answers/ca.crt -noout -subject -enddate -ext basicConstraints
```{{exec}}

The leaf is `CA:FALSE` and expires in 90 days, and cert-manager will replace it at 60. A trust store built out of leaves has to be rebuilt on every renewal, of every service, separately — and it grants trust to exactly one certificate rather than to the authority that issues them. The CA is `CA:TRUE`, lives ten years, and covers every certificate it will ever sign, including ones that do not exist yet.

That is what makes the next step possible at all.

</details>
