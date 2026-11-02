# 🥟 CKA-Style Practice: Dumpling Annex Bring-up

The **Orbital Noodle Station** is growing! 🛰️ A brand-new module, the **Dumpling Annex**, has just been bolted onto the hull, and its node arrived the way new hardware always does: *almost* ready.

Engineer Wonton 🧑‍🔧 ran `kubeadm init` and went for lunch. Here's what they left behind:

- 🐧 the kernel is tuned for the annex's old life as a storage locker, and a reboot would bring that tuning back
- 🐳 Docker is running, but nothing lets Kubernetes-style tooling talk to it over **CRI**
- 🕸️ there's **no CNI at all**: the node is `NotReady` and CoreDNS is stuck `Pending`
- 📜 Chef Udon wants the menu stored *in the cluster*, as a real Kubernetes resource with real validation

You're bringing the annex up from the bottom of the stack to the top. 🔧

## 🎯 Objective

Understand the three plug-in points underneath every Kubernetes cluster by building each one yourself: the **container runtime** behind CRI, the **network plugin** behind CNI, and the **API extension** behind a CRD. Each check observes the real outcome: what a reboot would load, what answers on a CRI socket, which IP a Pod actually gets, and what the API server actually rejects.

## 🗺️ Your Mission

| | |
|---|---|
| 1️⃣ | 🐧 Persist kernel modules and sysctls in **drop-in files** that still win after a reboot |
| 2️⃣ | 🐳 Install **cri-dockerd** from its release tarball, wire up its systemd **socket activation**, and talk to Docker over **CRI** with `crictl` |
| 3️⃣ | 🕸️ Install the reference **CNI plugins** and hand-write a `bridge` network config, until the node goes `Ready` and Pods get real IPs |
| 4️⃣ | 📜 Author a **CustomResourceDefinition** with schema validation, a default, printer columns and a **status subresource** |

Steps 1 and 2 are about the node. Step 3 is the one the cluster is waiting on. Step 4 only needs the API server, so you can do it any time.

## 🧰 What's Already Running

- A **one-node kubeadm cluster**, freshly re-initialised with Pod network `10.77.0.0/16` and **no CNI**
- **containerd** as the kubelet's runtime, which stays that way
- **Docker** (`systemctl status docker`), running but unused
- `crictl`, `kubectl`, `kubeadm`, `curl` and `python3`, plus `/root/annex/` and `/root/answers/` for files the steps mention

| Helper | What it does |
|---|---|
| `why` | Prints the reason the last **CHECK** didn't pass |
| `k` | Alias for `kubectl`, with completion |

Steps 2 and 3 download release files from GitHub. If a download is slow, just run it again.

## 📏 House Rules

Each step states the outcome required and how to check it yourself. Try it from the docs first. A **Solution** is hidden under each step.

Each step is graded by the **CHECK** button. When a check doesn't pass, run `why`{{exec}}. 🔍

> ℹ️ **About this lab.** This is an original, independent practice scenario written in the *style* of hands-on Kubernetes administrator tasks. It is not affiliated with, endorsed by, or derived from the Linux Foundation, the CNCF, or any certification exam, and contains no exam content. Its topics come from the public Kubernetes and project documentation.

Click **▶️ START** and let's get the dumplings steaming! 🥟♨️
