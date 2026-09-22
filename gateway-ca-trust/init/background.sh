#!/bin/bash

CM_VERSION=v1.20.3
TM_VERSION=v0.25.0
NGF_VERSION=2.7.2
GWAPI_VERSION=v1.6.1

if ! command -v helm >/dev/null 2>&1; then
  curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  bash /tmp/get_helm.sh >/dev/null 2>&1
fi

for IMG in \
  registry.k8s.io/e2e-test-images/agnhost:2.53 \
  docker.io/curlimages/curl:8.11.1 \
  "ghcr.io/nginx/nginx-gateway-fabric:${NGF_VERSION}" \
  "ghcr.io/nginx/nginx-gateway-fabric/nginx:${NGF_VERSION}" ; do
  ctr -n k8s.io images pull "$IMG" >/dev/null 2>&1 \
    || crictl pull "$IMG" >/dev/null 2>&1 \
    || true
done

# Gateway API is not part of Kubernetes -- the CRDs ship separately, and the
# version has to be one the controller supports. NGINX Gateway Fabric 2.7.2
# pins Gateway API 1.6.1, standard channel.
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GWAPI_VERSION}/standard-install.yaml" >/dev/null 2>&1

helm install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --version "$NGF_VERSION" \
  --namespace nginx-gateway --create-namespace \
  --set nginx.service.type=NodePort \
  --wait --timeout 5m >/dev/null 2>&1

helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1
helm repo update jetstack >/dev/null 2>&1

helm install cert-manager jetstack/cert-manager \
  --version "$CM_VERSION" \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true \
  --wait --timeout 5m >/dev/null 2>&1

# trust-manager distributes a CA's certificate to namespaces by label --
# step 5's subject. It goes in beside cert-manager, with no Bundle yet, the
# same way cert-manager goes in with no issuer yet.
helm install trust-manager oci://quay.io/jetstack/charts/trust-manager \
  --version "$TM_VERSION" \
  --namespace cert-manager \
  --set defaultPackage.enabled=false \
  --wait --timeout 5m >/dev/null 2>&1

kubectl create namespace chiikawa >/dev/null 2>&1
kubectl create namespace usagi >/dev/null 2>&1
# Step 5's extra target namespace: nobody touches this one by hand, so a CA
# certificate landing in it only happens because the Bundle put it there.
kubectl create namespace kitchen >/dev/null 2>&1

# The site that is about to get a certificate. Plain HTTP, port 80, no TLS of
# its own anywhere -- everything this lab does about TLS happens in front of it.
cat <<'EOF' | kubectl apply -f - >/dev/null 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hachiware
  namespace: chiikawa
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hachiware
  template:
    metadata:
      labels:
        app: hachiware
    spec:
      containers:
      - name: hachiware
        image: registry.k8s.io/e2e-test-images/agnhost:2.53
        args: ["netexec", "--http-port=8080"]
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: hachiware
  namespace: chiikawa
spec:
  selector:
    app: hachiware
  ports:
  - port: 80
    targetPort: 8080
EOF

kubectl -n chiikawa rollout status deployment/hachiware --timeout=180s >/dev/null 2>&1

# The front door, built for the learner rather than by them -- this lab is
# about the CA and the trust chain, not Gateway API mechanics. It already
# names the Secret cert-manager has not written yet: the listener sits at
# ResolvedRefs=False until step 2's Certificate produces "hachiware-tls",
# and then starts serving it with nothing here touched again.
cat <<'EOF' | kubectl apply -f - >/dev/null 2>&1
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: chiikawa-gateway
  namespace: chiikawa
spec:
  gatewayClassName: nginx
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: hachiware.chiikawa.lab
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: hachiware-tls
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hachiware-route
  namespace: chiikawa
spec:
  parentRefs:
  - name: chiikawa-gateway
  hostnames:
  - hachiware.chiikawa.lab
  rules:
  - backendRefs:
    - name: hachiware
      port: 80
EOF

kubectl -n chiikawa rollout status deploy/chiikawa-gateway-nginx --timeout=120s >/dev/null 2>&1 || true

# Step 4's consumer. It mounts a ConfigMap that does not exist yet, on purpose:
# the learner creates it from their own CA, and until they do this Pod cannot
# start. Applied in step 4 rather than here.
cat > /root/usagi.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: usagi
  namespace: usagi
spec:
  replicas: 1
  selector:
    matchLabels:
      app: usagi
  template:
    metadata:
      labels:
        app: usagi
    spec:
      containers:
      - name: usagi
        image: curlimages/curl:8.11.1
        command: ["sleep", "infinity"]
        volumeMounts:
        - name: trust
          mountPath: /etc/trust
          readOnly: true
      volumes:
      - name: trust
        configMap:
          name: chiikawa-ca-bundle
EOF

mkdir -p /root/answers /root/ca

# `k` for `kubectl`, with completion, in every interactive shell from here on.
cat >> /root/.bashrc <<'RC'
if command -v kubectl >/dev/null 2>&1; then
  source <(kubectl completion bash)
  alias k=kubectl
  complete -o default -F __start_kubectl k
fi
RC

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
# Only one helper: reading back why a check failed. Every other command in
# this lab (kubectl, curl, openssl) is typed out in full in the step text, on
# purpose -- wrapping them in scripts would hide the exact commands a learner
# needs when debugging this for real.

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
