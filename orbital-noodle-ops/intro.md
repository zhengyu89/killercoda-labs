# 🍜 CKA-Style Practice: Orbital Noodle Station Ops

Welcome aboard the **Orbital Noodle Station**, the only ramen shop in low orbit! 🛰️✨

Chef Udon 👩‍🍳 runs the galley, Captain Miso 🧑‍✈️ runs the station, and both of them have just found out that the station's Kubernetes cluster has **no administrator**. You've got the job.

The shift starts badly:

- 🤖 **Ladle-9**, the order robot, has been using the chef's admin credentials *(yikes)*
- 🧊 the freezer sensors keep getting scheduled onto the warm deck
- 🍲 someone shipped an "experimental spicy" broth image, and it doesn't exist
- 📻 the station radio is broadcasting dead air
- 🔧 and the cold deck's hull is due for maintenance **today**

## 🎯 Objective

Work through seven independent tasks of the kind a Kubernetes administrator gets every day: access control, scheduling, rollouts, configuration, batch jobs, troubleshooting and node maintenance. Each one is checked against what the cluster actually *does* (who can do what, where Pods really run, what a client really receives), not just whether a YAML object was accepted.

## 🗺️ Your Mission

| | |
|---|---|
| 1️⃣ | 🔐 Give Ladle-9 its own **ServiceAccount** and a **Role** that lets it scale exactly one Deployment, and nothing more |
| 2️⃣ | 🧊 Keep the freezer monitor on the cold deck with a **toleration** plus **required node affinity** |
| 3️⃣ | ⏪ Read the **rollout history**, roll back to the last good broth, and stop a bad image from ever taking healthy Pods down again |
| 4️⃣ | 🧂 Generate the pantry's credentials with **Kustomize `secretGenerator`** and consume them as an env var and a locked-down file |
| 5️⃣ | ⏰ Schedule a time-zoned **CronJob** with sane history and failure limits, then trigger a run by hand |
| 6️⃣ | 📻 Diagnose why the radio's **Service** has no listeners and why its Pods keep **restarting**, then fix both |
| 7️⃣ | 🛠️ Protect the jukebox with a **PodDisruptionBudget**, then **cordon and drain** the cold-deck node for maintenance |

The steps don't depend on each other. If one is giving you trouble you can move on and come back, except step 7, which drains a node and is meant to go last.

## 🧰 What's Already Running

- A **two-node kubeadm cluster**: the control plane (labelled `station.lab/deck=warm`, and allowed to run normal workloads in this lab) and the worker `node01` (labelled `station.lab/deck=cold`, tainted `cryo=active:NoSchedule`)
- Namespaces `galley`, `cold-deck`, `broth`, `pantry`, `ops`, `comms` and `lounge`, some already holding workloads that each step introduces
- A Kustomize base in `/root/pantry/` and an empty `/root/answers/` directory for files a step asks you to write

| Helper | What it does |
|---|---|
| `why` | Prints the reason the last **CHECK** didn't pass |
| `k` | Alias for `kubectl`, with completion |

Everything else is plain `kubectl`. That's deliberate, since it's what you'll have in front of you on a real cluster.

## 📏 House Rules

Each step states the outcome required: names, namespaces, fields, and how to check it yourself. Try it from the docs first. A **Solution** is hidden under each step if you get stuck.

Each step is graded by the **CHECK** button. When a check doesn't pass, run `why`{{exec}}. Every check records exactly which condition it couldn't observe, and usually the command that shows you why. 🔍

> ℹ️ **About this lab.** This is an original, independent practice scenario written in the *style* of hands-on Kubernetes administrator tasks. It is not affiliated with, endorsed by, or derived from the Linux Foundation, the CNCF, or any certification exam, and contains no exam content. Its topics come from the public Kubernetes documentation.

Click **▶️ START** and let's get the station's noodles flowing again! 🍜🚀
