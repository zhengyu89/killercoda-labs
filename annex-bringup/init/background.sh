#!/bin/bash
#
# Turns Killercoda's ready-made one-node cluster back into a freshly built
# node: same kubeadm, kubelet and containerd, but
#   - a stale sysctl drop-in that will undo step 1 at the next boot,
#   - Docker running and no cri-dockerd anywhere (step 2),
#   - the cluster re-initialised with no CNI config and no CNI plugin
#     binaries, so the node is NotReady and CoreDNS is Pending (step 3).
# Step 4 needs nothing but the API server.
#
# Output is discarded -- the learner watches init/foreground.sh. A finished
# setup touches /tmp/.initfinished; a setup that could not build something a
# step depends on also touches /tmp/.initbroken, with the reason in
# /root/.lab/init.log.

LAB=/root/.lab
mkdir -p "$LAB" /root/answers /root/annex
INITLOG="$LAB/init.log"
: > "$INITLOG"
broken() { echo "$*" >> "$INITLOG"; touch /tmp/.initbroken; }

DOCKER_VERSION=29.9.2
POD_CIDR=10.77.0.0/16
CRI_SOCK=unix:///run/containerd/containerd.sock
export KUBECONFIG=/etc/kubernetes/admin.conf

# The cluster itself needs these whatever the learner does in step 1: kube-proxy
# only sees bridged Pod traffic with br_netfilter loaded.
modprobe overlay >/dev/null 2>&1
modprobe br_netfilter >/dev/null 2>&1
sysctl -w net.bridge.bridge-nf-call-iptables=1 net.ipv4.ip_forward=1 >/dev/null 2>&1

# ---------------------------------------------------------------------------
# Step 1 -- a drop-in from the annex's previous life. It sorts after the file
# the learner is told to create, so at boot its values win.
# ---------------------------------------------------------------------------
cat > /etc/sysctl.d/95-legacy-annex.conf <<'EOF'
# Tuning from when the annex was a storage locker. Nobody remembers why.
vm.max_map_count = 65530
fs.inotify.max_user_instances = 128
EOF
sysctl --system >/dev/null 2>&1

# ---------------------------------------------------------------------------
# Step 2 -- Docker running, cri-dockerd absent. A static Docker lives entirely
# under /opt/docker so its bundled containerd and runc never shadow the ones
# the kubelet uses; with iptables and the bridge off it cannot touch Pod
# networking either. It only needs to answer cri-dockerd.
# ---------------------------------------------------------------------------
if ! command -v dockerd >/dev/null 2>&1; then
  curl -fsSL -o /tmp/docker.tgz \
    "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" \
    && mkdir -p /opt/docker \
    && tar -xzf /tmp/docker.tgz -C /opt/docker \
    && mv /opt/docker/docker /opt/docker/bin \
    && ln -sf /opt/docker/bin/docker /usr/local/bin/docker
  cat > /etc/systemd/system/docker.service <<'EOF'
[Unit]
Description=Docker Engine (static build, backing cri-dockerd)
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
Environment=PATH=/opt/docker/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/opt/docker/bin/dockerd --iptables=false --ip6tables=false --bridge=none
Restart=always
Delegate=yes
KillMode=process
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
fi
# cri-docker.socket hands its socket to group docker; a packaged Docker
# creates it, a static one does not.
groupadd -f docker
# Images that run containerd for the kubelet sometimes ship Docker masked.
systemctl unmask docker.service docker.socket >/dev/null 2>&1
systemctl daemon-reload
systemctl enable --now docker >/dev/null 2>&1 || broken "Docker did not start: systemctl status docker"

# crictl's defaults point both endpoints at the kubelet's runtime. With an
# image-endpoint set, `crictl -r <other socket> pull` still pulls into
# containerd -- step 2 relies on that being the case on every image.
cat > /etc/crictl.yaml <<EOF
runtime-endpoint: ${CRI_SOCK}
image-endpoint: ${CRI_SOCK}
timeout: 10
EOF

# Whatever the base image shipped, the learner starts with no cri-dockerd.
systemctl disable --now cri-docker.socket cri-docker.service >/dev/null 2>&1
dpkg -r cri-dockerd >/dev/null 2>&1
rm -f /usr/bin/cri-dockerd /usr/local/bin/cri-dockerd \
  /etc/systemd/system/cri-docker.service /etc/systemd/system/cri-docker.socket \
  /lib/systemd/system/cri-docker.service /lib/systemd/system/cri-docker.socket
systemctl daemon-reload

# ---------------------------------------------------------------------------
# Step 3 -- re-initialise the cluster with no CNI at all.
# ---------------------------------------------------------------------------
K8S_VERSION=$(kubeadm version -o short 2>/dev/null)
# Keep the kubelet's cgroup driver: it has to match containerd's, and the
# running kubelet is the one setting already known to.
CGROUP_DRIVER=$(awk '/^cgroupDriver:/ {print $2}' /var/lib/kubelet/config.yaml 2>/dev/null)
[ -n "$CGROUP_DRIVER" ] || CGROUP_DRIVER=systemd
KAPI=$(kubeadm config print init-defaults 2>/dev/null | awk '/^apiVersion: kubeadm/ {print $2; exit}')
[ -n "$KAPI" ] || KAPI=kubeadm.k8s.io/v1beta4

kubeadm reset -f --cri-socket "$CRI_SOCK" > "$LAB/kubeadm-reset.log" 2>&1

# What `kubeadm reset` tells you to clean up yourself: CNI config, CNI state,
# interfaces left by whichever CNI the image came with, and iptables.
rm -rf /etc/cni/net.d /var/lib/cni /root/.kube /opt/cni/bin
mkdir -p /etc/cni/net.d /opt/cni/bin
for IF in $(ip -o link show | awk -F': ' '{print $2}' | cut -d@ -f1 \
    | grep -E '^(cni0|flannel\.|vxlan\.calico|cali|weave|cilium_|kube-ipvs0|veth)'); do
  ip link delete "$IF" >/dev/null 2>&1
done
# Only the rules kube-proxy and the old CNI wrote. A blanket flush would also
# take out NAT rules the host itself relies on -- DNS among them.
for IPT in iptables ip6tables; do
  "${IPT}-save" 2>/dev/null \
    | grep -vE -- '(KUBE-|cali-|CALI-|FLANNEL|flannel|CILIUM|cilium|WEAVE|weave|CNI-)' \
    | "${IPT}-restore" >/dev/null 2>&1
  $IPT -P FORWARD ACCEPT >/dev/null 2>&1
done

cat > "$LAB/kubeadm.yaml" <<EOF
apiVersion: ${KAPI}
kind: InitConfiguration
nodeRegistration:
  criSocket: ${CRI_SOCK}
  ignorePreflightErrors: ["all"]
---
apiVersion: ${KAPI}
kind: ClusterConfiguration
kubernetesVersion: ${K8S_VERSION}
networking:
  podSubnet: ${POD_CIDR}
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: ${CGROUP_DRIVER}
failSwapOn: false
EOF

if kubeadm init --config "$LAB/kubeadm.yaml" > "$LAB/kubeadm-init.log" 2>&1; then
  mkdir -p /root/.kube
  cp /etc/kubernetes/admin.conf /root/.kube/config
else
  broken "kubeadm init failed -- see /root/.lab/kubeadm-init.log"
fi

for _ in $(seq 1 60); do
  [ -n "$(kubectl get nodes -o name 2>/dev/null)" ] && break
  sleep 2
done
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[ -n "$NODE" ] || broken "The re-initialised cluster has no Node object."
kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule- >/dev/null 2>&1 || true

# The controller-manager hands the node its slice of the Pod CIDR; step 3's
# config has to use exactly that slice.
for _ in $(seq 1 30); do
  [ -n "$(kubectl get node "$NODE" -o jsonpath='{.spec.podCIDR}' 2>/dev/null)" ] && break
  sleep 2
done
[ -n "$(kubectl get node "$NODE" -o jsonpath='{.spec.podCIDR}' 2>/dev/null)" ] \
  || broken "Node ${NODE} was never assigned a podCIDR."

# Step 3's check runs a probe Pod from this image; pulled now so it is cached.
crictl --runtime-endpoint "$CRI_SOCK" --image-endpoint "$CRI_SOCK" \
  pull docker.io/curlimages/curl:8.11.1 >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Step 4 -- a namespace for the menu, and an order that should never get in.
# ---------------------------------------------------------------------------
kubectl create namespace annex >/dev/null 2>&1
cat > /root/annex/bad-dumpling.yaml <<'EOF'
apiVersion: kitchen.station.lab/v1alpha1
kind: MenuItem
metadata:
  name: lava-dumpling
  namespace: annex
spec:
  dish: Lava Dumpling
  priceCredits: 9000
  spiceLevel: nuclear
EOF

# `k` for `kubectl`, with completion, in every interactive shell from here on.
cat >> /root/.bashrc <<'RC'
if command -v kubectl >/dev/null 2>&1; then
  source <(kubectl completion bash)
  alias k=kubectl
  complete -o default -F __start_kubectl k
fi
RC

# Killercoda shows only pass/fail, never a verify script's output, so each
# check writes its reason to /root/.check and `why` prints it.
cat > /usr/local/bin/why <<'WRAP'
#!/bin/bash
if [ -s /root/.check ]; then
  cat /root/.check
else
  echo "No check has run yet -- press CHECK, then run 'why' again."
fi
WRAP
chmod +x /usr/local/bin/why

touch /tmp/.initfinished
