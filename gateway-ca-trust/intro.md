
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

By the end of this lab you will have made your own root certificate, used it to sign a real HTTPS certificate for a Kubernetes `Gateway`, seen why a valid certificate is still not enough for a client to trust it, and set up `trust-manager` so the certificate is copied to every namespace that needs it — automatically, instead of by hand.

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

There are no wrapper scripts for `curl` or `kubectl get` in this lab — every command you run is the real thing, typed out in full, so what you practice here is what you'd actually type when debugging this on a real cluster. The one helper on your `PATH` is `why`, which prints the reason the last CHECK failed.

`kubectl` is also aliased to **`k`**, with the same completions, if you'd rather type less.

## 📏 House Rules

Each step tells you exactly what to build (name, namespace, fields) and how to check it yourself. Try writing the command or YAML from that description first — a **Solution** is there if you get stuck, hidden so it doesn't spoil the attempt.

Each step is graded with the **CHECK** button. When a check doesn't pass, run `why`{{exec}} in the terminal — every check in this lab writes down exactly which condition it wasn't happy with, rather than leaving you to guess. 🔍

Click **▶️ START** and let's get Hachiware that padlock! 🔐🍰
