## ⏰ Stock count

📚 **Reference:**
- [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/), in particular *Time zones*, *Concurrency policy* and *Jobs history limits*
- [Jobs: Pod backoff failure policy](https://kubernetes.io/docs/concepts/workloads/controllers/job/#pod-backoff-failure-policy) · [Job termination and cleanup](https://kubernetes.io/docs/concepts/workloads/controllers/job/#job-termination-and-cleanup)

Every six hours someone has to count the noodle stock. Captain Miso keeps station time on **Malaysia time**, the station's home port, so "six hours past midnight" has to mean *Kuala Lumpur* midnight, not whatever clock the node happens to run on. 🕰️

### 🎯 Your Tasks

1. Create a **CronJob** named `stock-count` in namespace **`ops`**:

   | Field | Value |
   |---|---|
   | schedule | at minute **15** of every **6th** hour (`15 */6 * * *`) |
   | time zone | `Asia/Kuala_Lumpur` |
   | concurrency | never start a run while the previous one is still going |
   | missed-run deadline | `120` seconds (`startingDeadlineSeconds`) |
   | history kept | **2** successful Jobs, **1** failed Job |
   | per-Job retries | `backoffLimit: 2` |
   | per-Job time limit | `activeDeadlineSeconds: 90` |
   | Pod | `restartPolicy: Never`, container `counter`, image `alpine:3.20` |
   | command | `sh -c 'echo "stock-count: all shelves sealed"; date -u'` |

2. Don't wait six hours. **Trigger a run now** from the CronJob's own template, as a Job named `stock-count-manual` in `ops`, and let it complete.

### ✅ Validate it yourself

```plain
kubectl -n ops get cronjob stock-count
```{{exec}}

```plain
kubectl -n ops get jobs
```{{exec}}

```plain
kubectl -n ops logs job/stock-count-manual
```{{exec}}

> **If CHECK does not pass**, run `why`{{exec}}.

<br>

<details><summary>💡 Tip: which limit lives where</summary>

A CronJob is three layers, and each setting belongs to exactly one of them:

- **CronJob spec**: `schedule`, `timeZone`, `concurrencyPolicy`, `startingDeadlineSeconds`, `successfulJobsHistoryLimit`, `failedJobsHistoryLimit` (when to make Jobs, and how many to keep)
- **`jobTemplate.spec`** (the Job): `backoffLimit`, `activeDeadlineSeconds` (how hard one run may try, and for how long)
- **`jobTemplate.spec.template.spec`** (the Pod): `restartPolicy`, `containers` (what actually runs)

`kubectl create cronjob` only covers the image, schedule, command and restart policy, so generate a skeleton with `--dry-run=client -o yaml` and add the rest.

</details>

<details><summary>✅ Solution</summary>

```plain
kubectl apply -f - <<'EOF'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: stock-count
  namespace: ops
spec:
  schedule: "15 */6 * * *"
  timeZone: Asia/Kuala_Lumpur
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 120
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 90
      template:
        spec:
          restartPolicy: Never
          containers:
          - name: counter
            image: alpine:3.20
            command: ["sh", "-c", "echo \"stock-count: all shelves sealed\"; date -u"]
EOF
```{{exec}}

```plain
kubectl -n ops create job stock-count-manual --from=cronjob/stock-count
```{{exec}}

```plain
kubectl -n ops wait --for=condition=complete job/stock-count-manual --timeout=90s && kubectl -n ops logs job/stock-count-manual
```{{exec}}

</details>
