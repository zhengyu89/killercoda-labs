#!/bin/bash
#
# Builds the Orbital Noodle Station on a two-node kubeadm cluster. Nothing here
# is meant for the learner's eyes -- Killercoda runs it with output discarded
# and init/foreground.sh is what they watch. A finished setup touches
# /tmp/.initfinished; a setup that could not build something a step depends on
# also touches /tmp/.initbroken and leaves the reason in /root/.lab/init.log.

LAB=/root/.lab
mkdir -p "$LAB" /root/answers
INITLOG="$LAB/init.log"
: > "$INITLOG"
broken() { echo "$*" >> "$INITLOG"; touch /tmp/.initbroken; }

for IMG in \
  docker.io/library/nginx:1.27-alpine \
  docker.io/library/nginx:1.28-alpine \
  docker.io/library/alpine:3.20 \
  docker.io/curlimages/curl:8.11.1 \
  registry.k8s.io/e2e-test-images/agnhost:2.53 ; do
  ctr -n k8s.io images pull "$IMG" >/dev/null 2>&1 \
    || crictl pull "$IMG" >/dev/null 2>&1 \
    || true
done

kubectl wait --for=condition=Ready nodes --all --timeout=300s >/dev/null 2>&1

# Node names are looked up rather than assumed, so the same script works on any
# two-node cluster. Every later script finds the worker by the label set here.
CP=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
WORKER=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$CP" ] || [ -z "$WORKER" ]; then
  broken "This lab needs one control-plane node and one worker; found control-plane='${CP}' worker='${WORKER}'."
fi

# The control plane takes ordinary workloads in this lab. Without that, the
# drain in step 7 has nowhere to send evicted Pods, and step 2's affinity would
# be pinning Pods to the only node that accepts them anyway.
kubectl taint nodes "$CP" node-role.kubernetes.io/control-plane:NoSchedule- >/dev/null 2>&1 || true
kubectl label node "$CP" station.lab/deck=warm --overwrite >/dev/null 2>&1
kubectl label node "$WORKER" station.lab/deck=cold --overwrite >/dev/null 2>&1
# Step 2's subject. Tainted before any workload exists, so everything below that
# does not tolerate it lands on the control plane.
kubectl taint nodes "$WORKER" cryo=active:NoSchedule --overwrite >/dev/null 2>&1

for NS in galley cold-deck broth pantry ops comms lounge; do
  kubectl create namespace "$NS" >/dev/null 2>&1
done

# ---------------------------------------------------------------------------
# Step 1 -- galley: two Deployments, only one of which the bot may scale, and a
# Secret it must not be able to read.
# ---------------------------------------------------------------------------
cat <<'EOF' | kubectl apply -f - >/dev/null 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: noodle-line
  namespace: galley
spec:
  replicas: 2
  selector:
    matchLabels:
      app: noodle-line
  template:
    metadata:
      labels:
        app: noodle-line
    spec:
      containers:
      - name: noodle-line
        image: nginx:1.27-alpine
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dish-washer
  namespace: galley
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dish-washer
  template:
    metadata:
      labels:
        app: dish-washer
    spec:
      containers:
      - name: dish-washer
        image: nginx:1.27-alpine
EOF
kubectl -n galley create secret generic galley-safe \
  --from-literal=vault-code=7-7-3-1 >/dev/null 2>&1

# ---------------------------------------------------------------------------
# Step 3 -- broth: three revisions, applied one after another so the rollout
# history reads launch -> winter -> experimental. The last image tag does not
# exist, so that rollout stalls part-way with one healthy Pod already gone.
# ---------------------------------------------------------------------------
broth_rev() {
  cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: broth-api
  namespace: broth
  annotations:
    kubernetes.io/change-cause: "$2"
spec:
  replicas: 4
  selector:
    matchLabels:
      app: broth-api
  template:
    metadata:
      labels:
        app: broth-api
    spec:
      containers:
      - name: broth
        image: $1
        ports:
        - containerPort: 80
EOF
}
broth_rev nginx:1.27-alpine "launch menu"
kubectl -n broth rollout status deploy/broth-api --timeout=180s >/dev/null 2>&1
broth_rev nginx:1.28-alpine "winter menu"
kubectl -n broth rollout status deploy/broth-api --timeout=180s >/dev/null 2>&1
broth_rev nginx:1.28-spicy-broth "experimental spicy menu"

# ---------------------------------------------------------------------------
# Step 4 -- pantry: a Kustomize base the learner extends. The token is random
# per session, so the check can only pass with the bytes from this file.
# ---------------------------------------------------------------------------
mkdir -p /root/pantry/secrets
head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' > /root/pantry/secrets/api-token.txt
cat > /root/pantry/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: pantry
resources:
- deployment.yaml
EOF
cat > /root/pantry/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pantry-ledger
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pantry-ledger
  template:
    metadata:
      labels:
        app: pantry-ledger
    spec:
      containers:
      - name: ledger
        image: nginx:1.27-alpine
EOF

# ---------------------------------------------------------------------------
# Step 6 -- comms: the radio and the Pod that listens to it. Two faults are
# planted: the Service selects a label no Pod carries and targets a port nothing
# listens on, and the liveness probe checks that same wrong port.
# ---------------------------------------------------------------------------
cat <<'EOF' | kubectl apply -f - >/dev/null 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: radio
  namespace: comms
spec:
  replicas: 2
  selector:
    matchLabels:
      app: radio
  template:
    metadata:
      labels:
        app: radio
        tier: comms
    spec:
      containers:
      - name: radio
        image: registry.k8s.io/e2e-test-images/agnhost:2.53
        args: ["netexec", "--http-port=9090"]
        ports:
        - name: http
          containerPort: 9090
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
          failureThreshold: 2
---
apiVersion: v1
kind: Service
metadata:
  name: radio
  namespace: comms
spec:
  selector:
    app: radio-tx
  ports:
  - name: http
    port: 80
    targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: listener
  namespace: comms
spec:
  replicas: 1
  selector:
    matchLabels:
      app: listener
  template:
    metadata:
      labels:
        app: listener
    spec:
      containers:
      - name: listener
        image: curlimages/curl:8.11.1
        command: ["sleep", "infinity"]
EOF
# Step 6 forbids replacing the Service; its UID is how the check tells.
kubectl -n comms get svc radio -o jsonpath='{.metadata.uid}' > "$LAB/radio-svc-uid" 2>/dev/null

# ---------------------------------------------------------------------------
# Step 7 -- lounge: a jukebox that tolerates the cold deck and is spread across
# both nodes, so draining the worker has real Pods of it to evict.
# nodeTaintsPolicy: Honor leaves a cordoned node out of the skew calculation;
# without it, DoNotSchedule would keep evicted replicas Pending forever.
# ---------------------------------------------------------------------------
cat <<'EOF' | kubectl apply -f - >/dev/null 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jukebox
  namespace: lounge
spec:
  replicas: 3
  selector:
    matchLabels:
      app: jukebox
  template:
    metadata:
      labels:
        app: jukebox
    spec:
      tolerations:
      - key: cryo
        operator: Equal
        value: active
        effect: NoSchedule
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        nodeTaintsPolicy: Honor
        labelSelector:
          matchLabels:
            app: jukebox
      containers:
      - name: jukebox
        image: nginx:1.28-alpine
EOF

for D in galley/noodle-line galley/dish-washer comms/listener lounge/jukebox; do
  kubectl -n "${D%/*}" rollout status "deploy/${D#*/}" --timeout=240s >/dev/null 2>&1 \
    || broken "Deployment ${D} did not become ready."
done
REVS=$(kubectl -n broth get rs -l app=broth-api --no-headers 2>/dev/null | wc -l)
[ "$REVS" -ge 3 ] || broken "broth-api has ${REVS} ReplicaSets, expected 3."
[ -s "$LAB/radio-svc-uid" ] || broken "Service comms/radio was not created."

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
