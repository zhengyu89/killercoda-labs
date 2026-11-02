## 🧂 Pantry credentials

📚 **Reference:**
- [Declarative Management of Kubernetes Objects Using Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/), in particular *Generating Resources → secretGenerator*
- [Secrets: using Secrets as environment variables](https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets-as-environment-variables) · [as files from a Pod](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/#project-secret-keys-to-specific-file-paths)

The pantry ledger talks to the supply ship's API. It needs two credentials: a vendor ID, which the app reads from an **environment variable**, and an API token, which it reads from a **file**. The pantry's manifests live in a Kustomize base:

```plain
ls -R /root/pantry && cat /root/pantry/kustomization.yaml
```{{exec}}

The token is already on disk at `/root/pantry/secrets/api-token.txt`. It's random for your session, so no copying it from anywhere else! 🙂

### 🎯 Your Tasks

Work in `/root/pantry` and deploy with **`kubectl apply -k /root/pantry`**. Don't create the Secret by hand.

1. Add a **`secretGenerator`** named `pantry-creds` to the kustomization, with two keys:
   - `vendor-id`, the literal value `ORBIT-7731`
   - `api-token`, read from the file `secrets/api-token.txt`
2. Wire the `ledger` container of the `pantry-ledger` Deployment to it:
   - env var **`VENDOR_ID`** from key `vendor-id`
   - mount the Secret **read-only** at **`/etc/pantry`**, projecting **only** the key `api-token`, as a file named **`token`**, with mode **`0400`**
3. Apply it. The Deployment ends up in namespace `pantry` with one ready Pod.

You can edit `deployment.yaml` directly, or add a patch in the kustomization. Either works.

### ✅ Validate it yourself

Preview what Kustomize will send, without applying it:

```plain
kubectl kustomize /root/pantry
```{{exec}}

Look at the Secret's name in that output, and at the name the Deployment refers to. Then, after applying:

```plain
kubectl -n pantry exec deploy/pantry-ledger -- sh -c 'echo "VENDOR_ID=$VENDOR_ID"; ls -l /etc/pantry/; cat /etc/pantry/token; echo'
```{{exec}}

> **If CHECK does not pass**, run `why`{{exec}}.

<br>

<details><summary>💡 Tip: the hash suffix is the point</summary>

`secretGenerator` names the Secret `pantry-creds-<hash>`, where the hash is computed from its contents, and rewrites every reference to `pantry-creds` in the same kustomization to match. Change the token, and the Secret gets a **new name**. The Deployment's Pod template then changes too, so the Pods roll automatically and pick up the new value.

A hand-made Secret called plain `pantry-creds` loses all of that: update it and running Pods keep the old env var until something restarts them. The check looks for the hashed name for exactly this reason.

</details>

<details><summary>💡 Tip: <code>ls -l</code> shows a symlink, and that's fine</summary>

Secret volumes are written as symlinks into a hidden, timestamped directory (that's how they're swapped atomically on update). `ls -l /etc/pantry` shows `token -> ..data/token`. To see the real file's mode, follow the link: `stat -L -c %a /etc/pantry/token`.

</details>

<details><summary>✅ Solution</summary>

```plain
cat > /root/pantry/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: pantry
resources:
- deployment.yaml
secretGenerator:
- name: pantry-creds
  literals:
  - vendor-id=ORBIT-7731
  files:
  - api-token=secrets/api-token.txt
EOF
```{{exec}}

```plain
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
        env:
        - name: VENDOR_ID
          valueFrom:
            secretKeyRef:
              name: pantry-creds
              key: vendor-id
        volumeMounts:
        - name: creds
          mountPath: /etc/pantry
          readOnly: true
      volumes:
      - name: creds
        secret:
          secretName: pantry-creds
          defaultMode: 0400
          items:
          - key: api-token
            path: token
EOF
```{{exec}}

```plain
kubectl apply -k /root/pantry
```{{exec}}

```plain
kubectl -n pantry rollout status deploy/pantry-ledger
```{{exec}}

In YAML, `0400` with a leading zero is octal, which the API stores as decimal `256`. Writing `400` without the zero would mean decimal 400, a completely different mode.

</details>
