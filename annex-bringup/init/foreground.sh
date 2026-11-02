#!/bin/bash

echo -n "Bolting the Dumpling Annex onto the station: starting Docker, wiping the network, re-initialising the cluster..."
while [ ! -f /tmp/.initfinished ]; do echo -n '.'; sleep 1; done
echo " done"
echo

if [ -f /tmp/.initbroken ]; then
  echo "!! Setup did not finish cleanly. The steps may not behave as described."
  echo "   What went wrong:"
  sed 's/^/     /' /root/.lab/init.log
  echo
fi
