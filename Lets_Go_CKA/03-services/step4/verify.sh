#!/bin/bash
grep -q "hello from web-" /root/pod-output.txt &&
grep -q "hello from web-" /root/svc-output.txt
