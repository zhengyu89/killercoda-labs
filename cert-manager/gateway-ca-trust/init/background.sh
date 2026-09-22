#!/bin/bash

CM_VERSION=v1.20.3
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

if ! kubectl -n cert-manager get deploy cert-manager >/dev/null 2>&1; then
  touch /tmp/.initbroken
fi
if ! kubectl get gatewayclass nginx >/dev/null 2>&1; then
  touch /tmp/.initbroken
fi

kubectl create namespace chiikawa >/dev/null 2>&1
kubectl create namespace usagi >/dev/null 2>&1

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

# Step 5's consumer. It mounts a ConfigMap that does not exist yet, on purpose:
# the learner creates it from their own CA, and until they do this Pod cannot
# start. Applied in step 5 rather than here.
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

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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

# The address of the nginx data plane NGINX Gateway Fabric creates for a
# Gateway. It is a Service in the Gateway's own namespace, not in
# nginx-gateway, and it does not exist until the Gateway does.
cat > /usr/local/bin/gwaddr <<'WRAP'
#!/bin/bash
GATEWAY=${1:-chiikawa-gateway}
NS=${2:-chiikawa}
IP=$(kubectl -n "$NS" get svc \
  -l gateway.networking.k8s.io/gateway-name="$GATEWAY" \
  -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null)
[ -z "$IP" ] && IP=$(kubectl -n "$NS" get svc "${GATEWAY}-nginx" \
  -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
echo "$IP"
WRAP
chmod +x /usr/local/bin/gwaddr

# The certificate the listener actually serves for one SNI name. No request is
# made -- this is the handshake and nothing else.
cat > /usr/local/bin/servedcert <<'WRAP'
#!/bin/bash
SNI=${1:-hachiware.chiikawa.lab}
GWIP=$(gwaddr)
if [ -z "$GWIP" ]; then
  echo "No nginx data plane Service yet -- has the Gateway been created?"
  echo "  kubectl -n chiikawa get gateway,svc"
  exit 1
fi
echo | timeout 5 openssl s_client -connect "$GWIP:443" -servername "$SNI" 2>/dev/null \
  | openssl x509 -noout -issuer -subject -ext basicConstraints -ext subjectAltName
WRAP
chmod +x /usr/local/bin/servedcert

# One HTTPS request to the bakery, from this node. With no argument the client
# trusts only the system store; with a file, it also trusts that file.
cat > /usr/local/bin/visit <<'WRAP'
#!/bin/bash
CA=$1
HOST=hachiware.chiikawa.lab
GWIP=$(gwaddr)
if [ -z "$GWIP" ]; then
  echo "No nginx data plane Service yet -- has the Gateway been created?"
  echo "  kubectl -n chiikawa get gateway,svc"
  exit 1
fi
if [ -n "$CA" ]; then
  curl -sS --cacert "$CA" --resolve "$HOST:443:$GWIP" "https://$HOST/hostname"
else
  curl -sS --resolve "$HOST:443:$GWIP" "https://$HOST/hostname"
fi
RC=$?
echo
echo "curl exit code: $RC"
WRAP
chmod +x /usr/local/bin/visit

# The same request, made from inside the cluster by the usagi Pod instead of
# from this node. The argument is a path inside that container.
cat > /usr/local/bin/insidecurl <<'WRAP'
#!/bin/bash
CA=$1
HOST=hachiware.chiikawa.lab
GWIP=$(gwaddr)
if [ -z "$GWIP" ]; then
  echo "No nginx data plane Service yet -- has the Gateway been created?"
  exit 1
fi
if ! kubectl -n usagi get deploy usagi >/dev/null 2>&1; then
  echo "There is no usagi Deployment yet:  kubectl apply -f /root/usagi.yaml"
  exit 1
fi
if [ -n "$CA" ]; then
  kubectl -n usagi exec deploy/usagi -- \
    curl -sS --cacert "$CA" --resolve "$HOST:443:$GWIP" "https://$HOST/hostname"
else
  kubectl -n usagi exec deploy/usagi -- \
    curl -sS --resolve "$HOST:443:$GWIP" "https://$HOST/hostname"
fi
RC=$?
echo
echo "curl exit code: $RC"
WRAP
chmod +x /usr/local/bin/insidecurl

touch /tmp/.initfinished
