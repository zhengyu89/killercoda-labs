
# 🍞 cert-manager CA & TLS Trust: Chiikawa's Bakery Goes HTTPS

Welcome to the **Nantoka Bakery Platform**! 🐭✨

Hachiware ⚔️ runs the bakery's website. It serves cake photos on port 80, in plaintext, to anyone who asks — and Usagi 🐰 keeps yelling **「ウラ！」** every time the browser says *Not Secure*.

So today the bakery goes HTTPS. There's just one problem: **nobody will sell Chiikawa a certificate.** 🥲

- `hachiware.chiikawa.lab` is not a real domain
- nothing in this cluster is reachable from the internet
- Let's Encrypt cannot validate a name it cannot see

No public CA. No ACME. No shortcuts. 🚫

**So you're going to be the certificate authority.** 👑

## 🎯 Objective

By the end of this lab, you will have built a working, self-signed PKI in front of a real Kubernetes workload: a root CA you generate yourself, a `ClusterIssuer` and `Certificate` that turn it into a live HTTPS listener, a hands-on look at *why* a valid certificate still isn't enough for a client to trust it, and a `trust-manager` `Bundle` that distributes that trust to every namespace that needs it — automatically, instead of by hand.

## 🗺️ Your Mission

Take the bakery from plaintext to a real TLS handshake, and then take that trust from your own laptop to the whole cluster:

| | |
|---|---|
| 1️⃣ | 🔑 Forge the bakery's root CA with `openssl`, store it as a Secret, and wire it to a **`ClusterIssuer`** |
| 2️⃣ | 📜 Ask it for a **`Certificate`** — a waiting `Gateway` picks up the Secret the moment cert-manager writes it |
| 3️⃣ | 🔒 Understand why the exact same HTTPS request **fails, then succeeds**, with nothing changed on the server |
| 4️⃣ | 🤝 Hand Usagi's Pod the CA certificate **by hand**, one namespace at a time |
| 5️⃣ | ⚙️ Replace that by hand copy with a **`trust-manager` `Bundle`** that keeps every labeled namespace in sync on its own |

## 🧰 What's Already Running

- **Gateway API** v1.6.1 CRDs, standard channel — `GatewayClass`, `Gateway`, `HTTPRoute`
- **NGINX Gateway Fabric** 2.7.2, owner of the `nginx` `GatewayClass` 🐙
- A `Gateway` named `chiikawa-gateway` and an `HTTPRoute` in namespace `chiikawa`, **already built for you** — the listener already names a TLS Secret, `hachiware-tls`, that does not exist yet. This lab is about the CA and the trust chain behind that Secret, not about Gateway API wiring.
- **cert-manager** v1.20.3 — installed, with **no issuers of any kind**
- **trust-manager** v0.25.0 — installed, with **no `Bundle` yet**
- `hachiware`, a plain HTTP Service in namespace `chiikawa`; namespaces `usagi` and `kitchen`, both empty and waiting

Four helpers are on your `PATH`, and each step says when to reach for them:

| Helper | What it does |
|---|---|
| `servedcert` | the certificate the Gateway listener *actually serves* — handshake only, no request |
| `visit` | one HTTPS request from this node; with a file argument, trusting that file |
| `insidecurl` | the same request, made from **inside** the cluster by Usagi's Pod |
| `why` | after a failed CHECK, prints exactly which condition it wasn't happy with |

`kubectl` is also aliased to **`k`**, with the same completions, if you'd rather type less.

## 📏 House Rules

Every command you need is given directly in the step — this lab is a walkthrough, not a guessing game. Where a step asks you to work something out yourself, it says so, and a **Tip** is there if you get stuck.

Each step is graded with the **CHECK** button. When a check doesn't pass, run `why`{{exec}} in the terminal — every check in this lab writes down exactly which condition it wasn't happy with, rather than leaving you to guess. 🔍

Click **▶️ START** and let's get Hachiware that padlock! 🔐🍰
