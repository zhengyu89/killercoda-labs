#!/bin/bash
#
# Every exit path below says why. Killercoda only reads the exit code, so the
# explanation is written to /root/.check and the learner reads it with `why`.
LOG=/root/.check
STEP="Step 4 · Teach the API a new word: author a CRD"
: > "$LOG"
fail() { { echo "x $STEP"; echo; printf '%s\n' "$@"; } | tee "$LOG"; exit 1; }
pass() { echo "OK $STEP -- passed." | tee "$LOG"; exit 0; }
R=""

CRD=menuitems.kitchen.station.lab
NS=annex
crd() { kubectl get crd "$CRD" -o jsonpath="{$1}" 2>/dev/null; }
mi() { kubectl -n $NS get menuitem tonkotsu -o jsonpath="{$1}" 2>/dev/null; }

# dryrun SPEC_YAML: asks the API server to validate a MenuItem without storing
# it. Exit 0 means it was accepted.
dryrun() {
  printf 'apiVersion: kitchen.station.lab/v1alpha1\nkind: MenuItem\nmetadata:\n  name: check-%s\n  namespace: %s\nspec:\n%s\n' \
    "$RANDOM" "$NS" "$1" | kubectl create --dry-run=server -f - >/dev/null 2>&1
}

GOOD='  dish: Pork Bun
  priceCredits: 500
  spiceLevel: volcanic'
BAD_CASES='price 0|  dish: Pork Bun\n  priceCredits: 0
price 501|  dish: Pork Bun\n  priceCredits: 501
price as a string|  dish: Pork Bun\n  priceCredits: "42"
spiceLevel nuclear|  dish: Pork Bun\n  priceCredits: 10\n  spiceLevel: nuclear
dish missing|  priceCredits: 10
priceCredits missing|  dish: Pork Bun
dish shorter than 3|  dish: Bo\n  priceCredits: 10'

for _ in $(seq 1 12); do
  kubectl get crd "$CRD" >/dev/null 2>&1 || { R="nocrd"; sleep 5; continue; }
  EST=$(crd '.status.conditions[?(@.type=="Established")].status')
  [ "$EST" == "True" ] || { R="notest"; sleep 5; continue; }

  BAD=""
  chk() { [ "$(crd "$1")" == "$2" ] || BAD="${BAD}  ${1}: '$(crd "$1")' (want '$2')"$'\n'; }
  chk .spec.group kitchen.station.lab
  chk .spec.scope Namespaced
  chk .spec.names.kind MenuItem
  chk .spec.names.plural menuitems
  chk .spec.names.singular menuitem
  chk '.spec.names.shortNames[*]' mi
  chk '.spec.names.categories[*]' kitchen
  chk '.spec.versions[*].name' v1alpha1
  chk '.spec.versions[0].served' true
  chk '.spec.versions[0].storage' true
  [ -z "$BAD" ] || { R="names"; sleep 5; continue; }

  COLS=$(crd '.spec.versions[0].additionalPrinterColumns[*].name' | tr ' ' ',')
  COLPATHS=$(crd '.spec.versions[0].additionalPrinterColumns[*].jsonPath' | tr ' ' ',')
  [ "$COLS" == "Dish,Price,Spice,Age" ] \
    && [ "$COLPATHS" == ".spec.dish,.spec.priceCredits,.spec.spiceLevel,.metadata.creationTimestamp" ] \
    || { R="columns"; sleep 5; continue; }

  STATUS_SUB=$(kubectl get crd "$CRD" -o jsonpath='{.spec.versions[0].subresources.status}' 2>/dev/null)
  [ -n "$STATUS_SUB" ] || { R="nostatussub"; sleep 5; continue; }

  # The schema, judged by what the API server accepts and refuses.
  dryrun "$GOOD" || { R="goodrejected"; sleep 5; continue; }
  LETIN=""
  while IFS='|' read -r LABEL BODY; do
    dryrun "$(printf '%b' "$BODY")" && LETIN="${LETIN}  - ${LABEL}"$'\n'
  done <<< "$BAD_CASES"
  [ -z "$LETIN" ] || { R="badaccepted"; sleep 5; continue; }

  kubectl -n $NS get menuitem tonkotsu >/dev/null 2>&1 || { R="nomi"; sleep 5; continue; }
  [ "$(mi .spec.dish)" == "Tonkotsu Ramen" ] && [ "$(mi .spec.priceCredits)" == "42" ] \
    || { R="mispec"; sleep 5; continue; }
  SPICE=$(mi .spec.spiceLevel)
  [ "$SPICE" == "mild" ] || { R="nodefault"; sleep 5; continue; }

  kubectl -n $NS get menuitem lava-dumpling >/dev/null 2>&1 && { R="lavaexists"; sleep 5; continue; }

  SOLD=$(mi .status.soldOut)
  [ "$SOLD" == "true" ] || { R="notsold"; sleep 5; continue; }

  pass
done

case "$R" in
  nocrd) fail \
    "There is no CustomResourceDefinition named ${CRD}." \
    "" \
    "A CRD's name must be <plural>.<group>." ;;
  notest) fail \
    "CRD ${CRD} exists but is not Established." \
    "" \
    "  kubectl get crd ${CRD} -o jsonpath='{.status.conditions}'" \
    "" \
    "A NamesAccepted=False condition there means the names clash with something." ;;
  names) fail \
    "The CRD's identity doesn't match:" \
    "" \
    "$BAD" ;;
  columns) fail \
    "Printer columns are not Dish, Price, Spice, Age from the right fields." \
    "" \
    "  names: ${COLS:-<none>}" \
    "  paths: ${COLPATHS:-<none>}" \
    "" \
    "Once you define any additionalPrinterColumns, the defaults are replaced --" \
    "Age has to be listed too (type: date, .metadata.creationTimestamp)." ;;
  nostatussub) fail \
    "The status subresource is not enabled on v1alpha1." \
    "" \
    "  versions[0].subresources.status: {}" ;;
  goodrejected) fail \
    "The API server refuses a valid MenuItem:" \
    "" \
    "$(echo "$GOOD" | sed 's/^/  /')" \
    "" \
    "See why with a dry run of your own:" \
    "  kubectl -n annex create --dry-run=server -f <file>" ;;
  badaccepted) fail \
    "The API server accepts MenuItems it should refuse:" \
    "" \
    "$LETIN" \
    "Each one needs a rule in the schema: required, minLength, minimum," \
    "maximum, enum, or the right type." ;;
  nomi) fail \
    "There is no MenuItem named tonkotsu in namespace annex." ;;
  mispec) fail \
    "tonkotsu has dish '$(mi .spec.dish)' and price '$(mi .spec.priceCredits)'." \
    "Want 'Tonkotsu Ramen' and 42." ;;
  nodefault) fail \
    "tonkotsu has spiceLevel '${SPICE:-<unset>}', not the default 'mild'." \
    "" \
    "Leave spiceLevel out of the object, and put default: mild on the field" \
    "in the schema -- the API server fills it in." ;;
  lavaexists) fail \
    "lava-dumpling exists -- the schema should have refused it." \
    "" \
    "Tighten the schema, then remove it:" \
    "  kubectl -n annex delete menuitem lava-dumpling" ;;
  notsold) fail \
    "tonkotsu has status.soldOut='${SOLD:-<unset>}', not true." \
    "" \
    "With the status subresource on, ordinary writes ignore .status. Write to" \
    "the subresource itself:" \
    "  kubectl -n annex patch menuitem tonkotsu --subresource=status --type=merge -p '{\"status\":{\"soldOut\":true}}'" ;;
  *) fail "Unexpected state -- rerun the check." ;;
esac
