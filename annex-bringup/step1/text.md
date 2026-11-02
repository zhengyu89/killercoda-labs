## 🐧 Kernel prep that survives a reboot

⏱️ **Setup takes 2–4 minutes.** It re-initialises the cluster from scratch. Wait for `done` in the terminal before starting.

📚 **Reference:**
- [Container Runtimes: install and configure prerequisites](https://kubernetes.io/docs/setup/production-environment/container-runtimes/#install-and-configure-prerequisites)
- [`sysctl.d(5)`](https://man7.org/linux/man-pages/man5/sysctl.d.5.html), in particular the section on file order · [`modules-load.d(5)`](https://man7.org/linux/man-pages/man5/modules-load.d.5.html)

The annex will run some heavy workloads: a search index that maps a lot of memory, and build agents that watch a lot of files. Engineer Wonton wants the kernel ready for both, **permanently**. "Permanently" means *after a reboot*. That's when the kernel forgets every `sysctl -w` and every `modprobe`, and rebuilds its settings from files.

```plain
ls /etc/sysctl.d/ /etc/modules-load.d/
```{{exec}}

### 🎯 Your Tasks

1. In **`/etc/modules-load.d/annex.conf`**, list the modules `overlay` and `br_netfilter` so they're loaded at every boot. Make sure both are loaded right now too.
2. In **`/etc/sysctl.d/90-annex.conf`** (exactly that file), set:

   | Parameter | Value |
   |---|---|
   | `vm.max_map_count` | `262144` |
   | `fs.inotify.max_user_instances` | `8192` |
   | `fs.inotify.max_user_watches` | `524288` |
   | `net.bridge.bridge-nf-call-ip6tables` | `1` |

3. Apply them to the running system now.
4. Make sure all four values **would still be in effect after a reboot.** Look carefully at what else is in `/etc/sysctl.d/`.

### ✅ Validate it yourself

`sysctl --system` loads every drop-in file in the same order the boot process does, and prints each file as it goes:

```plain
sysctl --system
```{{exec}}

```plain
sysctl vm.max_map_count fs.inotify.max_user_instances fs.inotify.max_user_watches net.bridge.bridge-nf-call-ip6tables
```{{exec}}

The CHECK does exactly this: it reads your values, runs `sysctl --system` as a reboot would, and reads them again.

> **If CHECK does not pass**, run `why`{{exec}}. It names the file that overrode you.

<br>

<details><summary>💡 Tip: who wins when two files set the same key</summary>

All files from `/etc/sysctl.d/`, `/run/sysctl.d/` and `/usr/lib/sysctl.d/` are sorted **by file name**, regardless of directory, and applied in that order. When two files set the same key, **the later one wins**. `95-legacy-annex.conf` sorts after `90-annex.conf`, so at every boot the legacy values overwrite yours, even though `sysctl -p` made everything look fine today.

Either remove the stale lines from the legacy file, or remove the legacy file entirely. Renaming your own file isn't an option here.

</details>

<details><summary>💡 Tip: why the module list matters to a sysctl</summary>

`net.bridge.*` keys only exist while the `br_netfilter` module is loaded. At boot, `systemd-modules-load` runs before `systemd-sysctl`, so a module listed in `modules-load.d` is there in time for its sysctl. A module loaded by hand with `modprobe` is gone after a reboot, and so is any `net.bridge.*` setting that depended on it.

</details>

<details><summary>✅ Solution</summary>

```plain
printf 'overlay\nbr_netfilter\n' > /etc/modules-load.d/annex.conf
modprobe overlay
modprobe br_netfilter
```{{exec}}

```plain
cat > /etc/sysctl.d/90-annex.conf <<'EOF'
vm.max_map_count = 262144
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
net.bridge.bridge-nf-call-ip6tables = 1
EOF
```{{exec}}

The legacy file would undo two of these at boot. Take its stale lines out (or delete the file):

```plain
sed -i -E '/^(vm\.max_map_count|fs\.inotify\.max_user_instances)[[:space:]]*=/d' /etc/sysctl.d/95-legacy-annex.conf
```{{exec}}

```plain
sysctl --system
```{{exec}}

</details>
