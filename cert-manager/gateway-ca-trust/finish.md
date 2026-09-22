
<br>

🍰 **The bakery has its padlock, and it scales.** Usagi has stopped yelling. Here is what actually happened.

## 🧩 Quick recap: what each piece is, and why you needed it

- **CA (Certificate Authority)** — a certificate and private key where the certificate has `CA:TRUE`. That bit is the only thing that lets it sign other certificates and be trusted by anything downstream. You made yours with two `openssl` commands in step 1.
- **Issuer / ClusterIssuer** — cert-manager's pointer at a signer. `Issuer` is namespaced; `ClusterIssuer` is cluster-scoped and reads its Secrets from one fixed namespace (`--cluster-resource-namespace`, default wherever cert-manager runs). Neither *is* a CA — both just say where to find one and what type it is (`ca`, `acme`, `vault`, ...).
- **Certificate** — a standing request: "keep a valid, signed keypair for this name in this Secret." cert-manager watches it, issues via a `CertificateRequest`, and renews it automatically before it expires. You never handle the private key directly; cert-manager writes it straight into the Secret.
- **trust-manager / `Bundle`** — the distribution half of the same problem. cert-manager gets you *a* signed certificate; `Bundle` gets *the CA that signs it* into every namespace that needs to verify one, kept in sync as a control loop instead of a one-time copy.
- **Why you need all four together**: an issuer without a CA has nothing to sign with; a Certificate without an issuer has no way to be granted; and a valid Certificate on a working listener still fails at the client until something distributes the CA that vouches for it. Step 3 is the proof — nothing on the server was ever broken.

## 🔍 The details behind that recap

**A `ca` issuer is a pointer, not a factory.** cert-manager did not create your authority — `openssl` did, in two commands, and cert-manager only learned where the keypair was stored. Everything the ClusterIssuer could ever sign was decided by the extensions you set on that self-signed certificate: `CA:TRUE` and `keyCertSign`, neither of which can be added afterwards. A certificate without them loads fine, looks fine, and is refused by every verifier the moment it signs anything.

**A `ClusterIssuer` reads every Secret it needs from one fixed namespace, and will not tell you which.** It has no namespace of its own to resolve `secretName` against, so cert-manager gives it `--cluster-resource-namespace`, defaulting to wherever cert-manager runs. `secrets "chiikawa-ca-key-pair" not found` is true and useless in the same breath — the Secret is right there in the namespace you created it in, and cert-manager never looked. The same rule governs ACME account keys and cloud credentials.

**The private key of the leaf never left the namespace that needed it, and neither did the CA's.** cert-manager generated a key in `chiikawa`, sent a CSR to a signer whose key lives in `cert-manager`, and put the signature back. Nothing in `chiikawa` could read the authority, and nothing had to. That is the entire security argument for having an issuer at all rather than copying PEM files around.

**The `Gateway`'s listener references the Secret *by name*.** It sat at `ResolvedRefs=False` for exactly as long as `hachiware-tls` didn't exist, and started serving the moment step 2's `Certificate` produced it — nobody touched the Gateway itself. That indirection is the only reason automated renewal is possible at all: when cert-manager renews at 60 days, the same listener starts serving the new certificate on its own.

**`Ready: True` is a statement about issuance and says nothing about trust.** Step 2 ended with a valid certificate on a working listener, and step 3 began with `curl` exit 60, having changed nothing in between. Then one file made the identical request succeed. Getting a certificate signed and getting a client to believe the signer are two separate pieces of work, and **only the first one has a controller** — until step 5.

**A trust store built from leaf certificates works, right up until it doesn't.** Handing a client `tls.crt` makes the handshake succeed — OpenSSL anchors on the exact certificate presented — so the mistake is invisible on the day it is made. It grants trust to one certificate with a 90-day life instead of to the authority behind it, and comes back as an outage at the first renewal. `ca.crt` is the file that gets distributed, and `CA:TRUE` is how you tell them apart, in a bundle exactly as much as on a laptop.

**A bundle carries certificates and only certificates.** It is copied into every namespace and mounted by every workload, so the one file that must never travel with it is the key. The ConfigMap you made by hand in step 4 was a copy, not a control loop: rotate the root and it still holds the old one, in that namespace, alongside every other copy anyone made. `trust-manager`'s `Bundle` is the fix — a source, a target, and a `namespaceSelector`, kept in sync on its own. `kitchen` never got a manual copy from you at all; it got one because it carried the right label.

## 📚 Documentation used in this lab

- [cert-manager: CA issuers](https://cert-manager.io/docs/configuration/ca/) — the `openssl` commands, the Secret, the `Issuer`/`ClusterIssuer`, and the warnings about running a PKI
- [cert-manager: cluster resource namespace](https://cert-manager.io/docs/configuration/#cluster-resource-namespace) — where a `ClusterIssuer` looks for Secrets
- [cert-manager: Certificate resources](https://cert-manager.io/docs/usage/certificate/) — fields, defaults, renewal
- [cert-manager: trust-manager](https://cert-manager.io/docs/trust/trust-manager/) · [Bundle API reference](https://cert-manager.io/docs/trust/trust-manager/bundle/) — distributing a CA as a control loop
- [Gateway API: TLS configuration](https://gateway-api.sigs.k8s.io/guides/user-guides/tls/) — `Terminate` vs `Passthrough`, `certificateRefs`, cross-namespace refs
- [Gateway API: `Gateway`](https://gateway-api.sigs.k8s.io/reference/api-types/gateway/) · [`HTTPRoute`](https://gateway-api.sigs.k8s.io/reference/api-types/httproute/) · [`GatewayClass`](https://gateway-api.sigs.k8s.io/reference/api-types/gatewayclass/)
- [NGINX Gateway Fabric: securing traffic](https://docs.nginx.com/nginx-gateway-fabric/traffic-security/)

## 🚀 Where to go next

- [`ckne/gateway-tls`](../../ckne/gateway-tls/) — SNI serving two certificates on one port, a forced renewal the Gateway never hears about, and what `Passthrough` gives up
- [`cert-manager/certificate-renewal`](../certificate-renewal/) — what a renewal actually changes, and which of your workloads will never notice *(planned)*

> See [`cert-manager/README.md`](../README.md) for how this lab relates to the rest of the set. 🐭
