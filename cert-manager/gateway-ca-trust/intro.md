
# 🍞 cert-manager CA & TLS Trust: Chiikawa's Bakery Goes HTTPS

Welcome to the **Nantoka Bakery Platform**! 🐭✨

Hachiware ⚔️ runs the bakery's website. It serves cake photos on port 80, in plaintext, to anyone who asks — and Usagi 🐰 keeps yelling **「ウラ！」** every time the browser says *Not Secure*.

So today the bakery goes HTTPS. There's just one problem: **nobody will sell Chiikawa a certificate.** 🥲

- `hachiware.chiikawa.lab` is not a real domain
- nothing in this cluster is reachable from the internet
- Let's Encrypt cannot validate a name it cannot see

No public CA. No ACME. No shortcuts. 🚫

**So you're going to be the certificate authority.** 👑

## 🎯 Your Mission

Take the bakery from plaintext to a real TLS handshake, the whole chain, by hand:

| | |
|---|---|
| 1️⃣ | 🔑 Forge the bakery's root CA with `openssl`, store it as a Secret, and wire it to a **`ClusterIssuer`** |
| 2️⃣ | 📜 Ask it for a **`Certificate`** — and watch the Secret appear, signed by *your* CA |
| 3️⃣ | 🚪 Put it on an **NGINX `Gateway`** listener and route `hachiware.chiikawa.lab` to the bakery |
| 4️⃣ | 🔒 Make the exact same HTTPS request **fail**, then **succeed** — with nothing changed on the server |
| 5️⃣ | 🤝 Hand the trust bundle to Usagi's Pod so the cluster believes you too |

## 🧰 What's Already Running

- **Gateway API** v1.6.1 CRDs, standard channel — `GatewayClass`, `Gateway`, `HTTPRoute`
- **NGINX Gateway Fabric** 2.7.2, owner of the `nginx` `GatewayClass` 🐙
- **cert-manager** v1.20.3 — installed, and with **no issuers of any kind**
- `hachiware`, a plain HTTP Service in namespace `chiikawa`; namespace `usagi`, empty and waiting

Four helpers are on your `PATH`, and each step says when to reach for them:

| Helper | What it does |
|---|---|
| `gwaddr` | the address of the nginx data plane, once a Gateway exists |
| `servedcert` | the certificate the listener *actually serves* — handshake only, no request |
| `visit` | one HTTPS request from this node; with a file argument, trusting that file |
| `insidecurl` | the same request, made from **inside** the cluster by Usagi's Pod |

## 📏 House Rules

Every step here gives you a **task, not a solution** — work it out yourself first, open the **Tip** if you're stuck, and read the **Solution** only once you've tried. 💪

Each step is graded with the **CHECK** button. When a check doesn't pass, run `why`{{exec}} in the terminal — every check in this lab writes down exactly which condition it wasn't happy with, rather than leaving you to guess. 🔍

Click **▶️ START** and let's get Hachiware that padlock! 🔐🍰
