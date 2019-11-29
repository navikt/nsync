#!/usr/bin/env bash
ENDPOINT="${1}"
RETRIES="${2:-60}"
SLEEP_DURATION="${3:-1}"
EXPECTED_STATUS="${4:-200}"
LAST_OUTPUT="${5:-./uptimed_last_output}"
rm -f "$LAST_OUTPUT"

echo "Calling $ENDPOINT $RETRIES times (sleeping ${SLEEP_DURATION}s between each), will exit if HTTP status != $EXPECTED_STATUS"

for i in $(seq 1 "$RETRIES"); do
  status=$(curl -k -s -o "$LAST_OUTPUT" -w "%{http_code}" "$ENDPOINT")
  echo "$i: $status"
  if [ "$EXPECTED_STATUS" != "$status" ]; then
    echo "curl failed, last output below:"
    cat "$LAST_OUTPUT"
    # cange to exit 1 when things are working
    exit 1
  fi

  sleep "$SLEEP_DURATION"
done
echo "Timed out after $RETRIES retries."