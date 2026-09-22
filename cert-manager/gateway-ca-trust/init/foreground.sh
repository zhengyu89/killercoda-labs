#!/bin/bash

echo -n "Installing Gateway API CRDs, NGINX Gateway Fabric and cert-manager..."
while [ ! -f /tmp/.initfinished ]; do echo -n '.'; sleep 1; done
echo " done"

if [ -f /tmp/.initbroken ]; then
  echo
  echo "!! The install did not complete cleanly. Nothing in this lab will work."
  echo "!! Check with:  kubectl -n cert-manager get pods; kubectl get gatewayclass"
fi
echo
