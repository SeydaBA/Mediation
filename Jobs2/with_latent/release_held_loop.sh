#!/bin/bash
while true; do
  held_ids=$(squeue -u $USER -h -o "%i %r" | grep -E "JobHeldUser|user env retrieval|launch_failure" | awk '{print $1}')
  if [ -n "$held_ids" ]; then
    count=$(echo "$held_ids" | wc -l)
    echo "$(date): releasing $count held"
    echo "$held_ids" | while read jid; do
      scontrol release "$jid" >/dev/null 2>&1
    done
  fi
  sleep 60
done
