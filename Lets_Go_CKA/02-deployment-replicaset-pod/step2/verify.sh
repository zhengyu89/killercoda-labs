#!/bin/bash
[ "$(kubectl -n workloads get rs web-rs -o jsonpath='{.status.readyReplicas}')" = "3" ]
