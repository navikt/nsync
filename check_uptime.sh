#!/usr/bin/env bash
echo "Checking uptimed.sh - $(date)"
if [ -d /proc/$(cat pid) ]; then
    echo "uptimed.sh [$(cat pid)] is still running...";
    kill $(cat pid)
    exit 0;
else
    echo "uptimed.sh is not running...";
    cat ./uptimed_last_output
    echo "----- nohup.out -----"
    cat nohup.out
    exit 0;
fi