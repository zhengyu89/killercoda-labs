# Killercoda Labs

Hands-on Kubernetes labs for the part that usually gets hand-waved away: the moment configuration meets a real client.

This repository is a growing set of guided [Killercoda](https://killercoda.com/) scenarios. Each lab starts with a working cluster, gives you a problem rather than a copy-paste recipe, and checks the outcome on the wire—not merely whether a YAML object was accepted.

## Start here

### [🍞 cert-manager CA & TLS Trust: Chiikawa's Bakery HTTPS Lab](gateway-ca-trust/)

Chiikawa’s bakery has an HTTP site, an internal-only hostname, and no public CA that can validate it. You become the CA, then take the service all the way to trusted HTTPS.

You will:

1. Create a proper root CA with OpenSSL and connect it to cert-manager.
2. Issue a leaf certificate into a workload namespace.
3. Serve it through an NGINX Gateway Fabric HTTPS listener.
4. See the exact same request fail without trust and succeed with the correct CA.
5. Mount that trust into a second workload—without ever distributing a private key.

Along the way, the lab makes the important boundaries visible:

| Boundary | What you discover |
| --- | --- |
| CA creation → cert-manager | A `ca` issuer points at an authority; it does not create one. |
| ClusterIssuer → Secret | Cluster-scoped issuers read their backing Secret from cert-manager’s cluster resource namespace. |
| Certificate → Gateway | cert-manager writes the Secret; the Gateway references it and can pick up renewal without a Gateway edit. |
| Valid certificate → trusted connection | Issuance and client trust are separate jobs. A ready `Certificate` does not make clients believe it. |
| CA certificate → client workload | Trust bundles may travel; private keys never should. |

The scenario uses cert-manager v1.20.3, Gateway API v1.6.1, and NGINX Gateway Fabric v2.7.2. It is designed for a one-node Kubernetes environment provided by Killercoda.

### [🍜 CKA-Style Practice: Orbital Noodle Station Ops](orbital-noodle-ops/)

The station's cluster has no administrator, and now you're it. Seven independent, everyday admin tasks on a two-node kubeadm cluster, each checked by what the cluster actually does:

| # | Task | What the check observes |
| --- | --- | --- |
| 1 | RBAC for a bot that may scale one Deployment and nothing else | `kubectl auth can-i` for every required *and* forbidden action |
| 2 | Pin a workload to a tainted node with a toleration plus required node affinity | the node each Pod actually runs on; blanket tolerations rejected |
| 3 | Roll back a stuck rollout to a named revision and harden its strategy | image, availability, and the revision number *before* rollback |
| 4 | Generate a Secret with Kustomize and consume it as env var and file | the hashed Secret name, and the env, file, and file mode inside the Pod |
| 5 | A time-zoned CronJob with history and failure limits, run by hand | every field at its proper layer, plus a completed Job from the template |
| 6 | Troubleshoot a Service with no endpoints and a probe killing healthy Pods | an in-cluster `curl`, unchanged Service UID, restart counts holding still |
| 7 | PodDisruptionBudget plus cordon and drain | node empty of workload Pods, budget respected, replicas Ready elsewhere |

It is designed for Killercoda's two-node kubeadm environment. It is an original practice scenario, not affiliated with or derived from any certification exam.

### [🥟 CKA-Style Practice: Dumpling Annex Bring-up](annex-bringup/)

A freshly built node, brought up from the bottom of the stack: the three plug-in points under every cluster, each built by hand.

| # | Task | What the check observes |
| --- | --- | --- |
| 1 | Kernel modules and sysctls in drop-in files, with a stale file that wins at boot | values now, then again after `sysctl --system` replays the boot order |
| 2 | cri-dockerd from its release tarball, hand-installed systemd units, socket activation | the running process's flags, and an image pulled over CRI landing in Docker |
| 3 | Install the reference CNI plugins and hand-write a `bridge` network config | node `Ready`, Pod IPs from the node's own `podCIDR`, a probe Pod reaching the API |
| 4 | Author a CRD with validation, a default, printer columns and a status subresource | the API server refusing bad objects, the default applied, status set via `/status` |

The setup re-initialises Killercoda's one-node kubeadm cluster with no CNI, so step 3 starts from a `NotReady` node. Pinned versions: cri-dockerd v0.4.10, CNI plugins v1.9.1, Docker 29.9.2 (static, only if the image has no Docker).

## What makes these labs different

- **Learn by diagnosis.** Steps lead with the objective. Tips and full solutions are there when you need them, not before.
- **Checks explain themselves.** Press **CHECK**, then run `why` in the terminal for the precise missing condition and a useful next command.
- **Verify the thing that matters.** A listener is checked by its actual TLS handshake; a trust bundle is checked from a Pod that mounts it.
- **Teach the tempting wrong answer.** For example, trusting the leaf certificate can make today’s `curl` pass—and guarantees pain at renewal. The lab distinguishes it from trusting the CA.

## Repository layout

```text
gateway-ca-trust/
├── index.json              # Killercoda scenario definition
├── intro.md                # story, mission, and environment
├── init/                   # cluster bootstrap and learner helpers
├── step1/ ... step5/       # learner instructions and outcome checks
└── finish.md               # recap and source material
```

Every scenario is self-contained: `index.json` is the entry point, `init/` prepares the environment, and each step pairs learner-facing Markdown with a verifier script.

## Running a scenario

Use the Killercoda scenario workflow to open the directory’s `index.json`, or host the repository through your Killercoda authoring setup. The scenario provisions its own dependencies, so learners should not need to install cert-manager or a Gateway controller first.

Once it starts, read the task, work from the terminal, and press **CHECK** after each step. If a check fails:

```bash
why
```

That is deliberately more useful than a generic red cross: it reports the condition the verifier could not observe.

## Contributing a lab

Keep a new scenario small, runnable, and honest:

1. Add a directory with an `index.json`, intro, finish, initialization scripts, and numbered step folders.
2. Make each step ask for an observable outcome, not just a resource to apply.
3. Provide a `verify.sh` that checks the behavior users care about and writes actionable failure context to `/root/.check` for `why` to display.
4. Include a tip and a solution, explaining *why* the solution works and where the common near-miss fails.
5. Pin infrastructure versions in the initializer so the scenario remains reproducible.

The goal is not a pile of manifests. It is the confidence to understand a Kubernetes failure when it happens outside the happy path.

## References

The lab’s finish page links to the primary documentation behind it, including [cert-manager CA issuers](https://cert-manager.io/docs/configuration/ca/), [Certificate resources](https://cert-manager.io/docs/usage/certificate/), [Gateway API TLS](https://gateway-api.sigs.k8s.io/guides/user-guides/tls/), and [trust-manager](https://cert-manager.io/docs/trust/trust-manager/).
