## 📜 Teach the API a new word: author a CRD

📚 **Reference:**
- [Extend the Kubernetes API with CustomResourceDefinitions](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/), in particular *Validation*, *Defaulting*, *Additional printer columns*, *Subresources* and *Categories*
- [Custom Resources (concepts)](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)

Chef Udon is done with the menu living in a spreadsheet. 🧾 They want it **in the cluster**: `kubectl get menuitems` in the `annex` namespace, prices the API server refuses to accept if they're nonsense, and a "sold out" flag the kitchen robots can flip without being able to rewrite the dish itself.

None of that needs a single line of code. A **CustomResourceDefinition** teaches the API server a new resource type, its schema included.

### 🎯 Your Tasks

1. Create a **CustomResourceDefinition** for:

   | | |
   |---|---|
   | group | `kitchen.station.lab` |
   | kind / plural / singular | `MenuItem` / `menuitems` / `menuitem` |
   | short name | `mi` |
   | category | `kitchen` (so `kubectl get kitchen` lists them) |
   | scope | `Namespaced` |
   | version | `v1alpha1`, served and storage |

   With this schema (`spec` is required):

   | Field | Type | Rules |
   |---|---|---|
   | `spec.dish` | string | **required**, at least 3 characters |
   | `spec.priceCredits` | integer | **required**, from 1 to 500 |
   | `spec.spiceLevel` | string | one of `mild`, `medium`, `volcanic`; **defaults to `mild`** |
   | `status.soldOut` | boolean | |

   Also:
   - **printer columns** `Dish`, `Price` and `Spice` (from the three spec fields), followed by `Age`
   - the **status subresource** enabled

2. In namespace **`annex`**, create a MenuItem named **`tonkotsu`** with dish `Tonkotsu Ramen` and price `42`, and **no `spiceLevel`**. Let the default fill it in.
3. Try to create the order in `/root/annex/bad-dumpling.yaml`. The API server should **refuse** it.
4. Tonkotsu has sold out. Set `status.soldOut: true` on it **through the status subresource**.

### ✅ Validate it yourself

```plain
kubectl get crd menuitems.kitchen.station.lab
```{{exec}}

```plain
kubectl -n annex get mi
```{{exec}}

```plain
kubectl apply -f /root/annex/bad-dumpling.yaml
```{{exec}}

```plain
kubectl -n annex get menuitem tonkotsu -o yaml
```{{exec}}

The CHECK also sends the API server a set of good and bad MenuItems (as server-side dry runs, so nothing is stored) and expects each bad one to be refused.

> **If CHECK does not pass**, run `why`{{exec}}.

<br>

<details><summary>💡 Tip: why <code>kubectl apply</code> can't set the status</summary>

With the status subresource enabled, the API server splits the object in two. Writes to the main resource **ignore** `.status`, and writes to `/status` **ignore** everything except `.status`. RBAC can grant them separately too, which is exactly how a robot gets "may mark sold out" without "may rename the dish".

So `kubectl apply` with a `status:` block appears to succeed and changes nothing. Use `--subresource=status`:

```plain
kubectl patch --help | grep -A3 subresource
```{{exec}}

</details>

<details><summary>💡 Tip: defaults are applied by the API server</summary>

A `default:` in the schema is filled in when the object is read from the request and when it's read from storage. That's why `tonkotsu` shows `spiceLevel: mild` even though nobody wrote it, and why the check can tell your default works.

</details>

<details><summary>✅ Solution</summary>

```plain
kubectl apply -f - <<'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: menuitems.kitchen.station.lab
spec:
  group: kitchen.station.lab
  scope: Namespaced
  names:
    kind: MenuItem
    plural: menuitems
    singular: menuitem
    shortNames: ["mi"]
    categories: ["kitchen"]
  versions:
  - name: v1alpha1
    served: true
    storage: true
    subresources:
      status: {}
    additionalPrinterColumns:
    - name: Dish
      type: string
      jsonPath: .spec.dish
    - name: Price
      type: integer
      jsonPath: .spec.priceCredits
    - name: Spice
      type: string
      jsonPath: .spec.spiceLevel
    - name: Age
      type: date
      jsonPath: .metadata.creationTimestamp
    schema:
      openAPIV3Schema:
        type: object
        required: ["spec"]
        properties:
          spec:
            type: object
            required: ["dish", "priceCredits"]
            properties:
              dish:
                type: string
                minLength: 3
              priceCredits:
                type: integer
                minimum: 1
                maximum: 500
              spiceLevel:
                type: string
                enum: ["mild", "medium", "volcanic"]
                default: mild
          status:
            type: object
            properties:
              soldOut:
                type: boolean
EOF
```{{exec}}

```plain
kubectl wait --for=condition=Established crd/menuitems.kitchen.station.lab
```{{exec}}

```plain
kubectl apply -f - <<'EOF'
apiVersion: kitchen.station.lab/v1alpha1
kind: MenuItem
metadata:
  name: tonkotsu
  namespace: annex
spec:
  dish: Tonkotsu Ramen
  priceCredits: 42
EOF
```{{exec}}

```plain
kubectl apply -f /root/annex/bad-dumpling.yaml
```{{exec}}

```plain
kubectl -n annex patch menuitem tonkotsu --subresource=status --type=merge -p '{"status":{"soldOut":true}}'
kubectl -n annex get kitchen
```{{exec}}

</details>
