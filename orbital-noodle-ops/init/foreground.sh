#!/bin/bash

echo -n "Docking at the Orbital Noodle Station: labelling decks, pulling images, starting the galley..."
while [ ! -f /tmp/.initfinished ]; do echo -n '.'; sleep 1; done
echo " done"
echo

if [ -f /tmp/.initbroken ]; then
  echo "!! Setup did not finish cleanly. The steps may not behave as described."
  echo "   What went wrong:"
  sed 's/^/     /' /root/.lab/init.log
  echo
  echo "   Look around with:  kubectl get nodes; kubectl get pods -A"
  echo
fi
