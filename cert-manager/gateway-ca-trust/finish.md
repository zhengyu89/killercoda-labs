
<br>

🍰 **The bakery has its padlock.** Usagi has stopped yelling. Here is what actually happened.

**A `ca` issuer is a pointer, not a factory.** cert-manager did not create your authority — `openssl` did, in two commands, and cert-manager only learned where the keypair was stored. Everything the ClusterIssuer could ever sign was decided by the extensions you set on that self-signed certificate: `CA:TRUE` and `keyCertSign`, neither of which can be added afterwards. A certificate without them loads fine, looks fine, and is refused by every verifier the moment it signs anything.

**A `ClusterIssuer` reads every Secret it needs from one fixed namespace, and will not tell you which.** It has no namespace of its own to resolve `secretName` against, so cert-manager gives it `--cluster-resource-namespace`, defaulting to wherever cert-manager runs. `secrets "chiikawa-ca-key-pair" not found` is true and useless in the same breath — the Secret is right there in the namespace you created it in, and cert-manager never looked. The same rule governs ACME account keys and cloud credentials.

**The private key of the leaf never left the namespace that needed it, and neither did the CA's.** cert-manager generated a key in `chiikawa`, sent a CSR to a signer whose key lives in `cert-manager`, and put the signature back. Nothing in `chiikawa` could read the authority, and nothing had to. That is the entire security argument for having an issuer at all rather than copying PEM files around.

**The `Gateway` object is the request for a data plane.** You wrote one object and NGINX Gateway Fabric created a Deployment, a Service, and an nginx configuration in your namespace, then kept them matching the listener. The listener references the Secret *by name* — so when cert-manager renews the certificate at 60 days, the same listener starts serving the new one and nobody edits the Gateway. That indirection is the only reason automated renewal is possible at all.

**`Ready: True` is a statement about issuance and says nothing about trust.** Step 3 ended with a valid certificate on a working listener, and step 4 began with `curl` exit 60, having changed nothing in between. Then one file made the identical request succeed. Getting a certificate signed and getting a client to believe the signer are two separate pieces of work, and **only the first one has a controller**.

**A trust store built from leaf certificates works, right up until it doesn't.** Handing a client `tls.crt` makes the handshake succeed — OpenSSL anchors on the exact certificate presented — so the mistake is invisible on the day it is made. It grants trust to one certificate with a 90-day life instead of to the authority behind it, and comes back as an outage at the first renewal. `ca.crt` is the file that gets distributed, and `CA:TRUE` is how you tell them apart, in a bundle exactly as much as on a laptop.

**A bundle carries certificates and only certificates.** It is copied into every namespace and mounted by every workload, so the one file that must never travel with it is the key. And the ConfigMap you made by hand is a copy, not a control loop: rotate the root and it still holds the old one, in that namespace, alongside every other copy anyone made. That is the problem [`trust-manager`](https://cert-manager.io/docs/trust/trust-manager/) exists to solve.

## 📚 Documentation used in this lab

- [cert-manager: CA issuers](https://cert-manager.io/docs/configuration/ca/) — the `openssl` commands, the Secret, the `Issuer`/`ClusterIssuer`, and the warnings about running a PKI
- [cert-manager: cluster resource namespace](https://cert-manager.io/docs/configuration/#cluster-resource-namespace) — where a `ClusterIssuer` looks for Secrets
- [cert-manager: Certificate resources](https://cert-manager.io/docs/usage/certificate/) — fields, defaults, renewal
- [cert-manager: trust-manager](https://cert-manager.io/docs/trust/trust-manager/) — distributing a CA as a control loop
- [cert-manager: Gateway API annotations](https://cert-manager.io/docs/usage/gateway/) — letting cert-manager write the `Certificate` for a `Gateway` (needs `ExperimentalGatewayAPISupport`)
- [Gateway API: TLS configuration](https://gateway-api.sigs.k8s.io/guides/user-guides/tls/) — `Terminate` vs `Passthrough`, `certificateRefs`, cross-namespace refs
- [Gateway API: `Gateway`](https://gateway-api.sigs.k8s.io/reference/api-types/gateway/) · [`HTTPRoute`](https://gateway-api.sigs.k8s.io/reference/api-types/httproute/) · [`GatewayClass`](https://gateway-api.sigs.k8s.io/reference/api-types/gatewayclass/)
- [NGINX Gateway Fabric: install with Helm](https://docs.nginx.com/nginx-gateway-fabric/install/helm/) · [securing traffic](https://docs.nginx.com/nginx-gateway-fabric/traffic-security/) · [basic routing](https://docs.nginx.com/nginx-gateway-fabric/traffic-management/basic-routing/)

## 🚀 Where to go next

- [`cert-manager/issuers-and-trust`](../issuers-and-trust/) — the same boundary from the other side: a cross-namespace `issuerRef` that applies cleanly and never issues, and a `trust-manager` `Bundle` that distributes the CA by label and refuses to carry the key
- [`ckne/gateway-tls`](../../ckne/gateway-tls/) — SNI serving two certificates on one port, a forced renewal the Gateway never hears about, and what `Passthrough` gives up
- [`cert-manager/certificate-renewal`](../certificate-renewal/) — what a renewal actually changes, and which of your workloads will never notice *(planned)*

> See [`cert-manager/README.md`](../README.md) for how this lab relates to the rest of the set. 🐭
