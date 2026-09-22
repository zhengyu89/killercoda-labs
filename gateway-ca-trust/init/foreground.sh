#!/bin/bash

echo -n "Installing Gateway API CRDs, NGINX Gateway Fabric, cert-manager and trust-manager..."
while [ ! -f /tmp/.initfinished ]; do echo -n '.'; sleep 1; done
echo " done"
echo
