#!/usr/bin/env bash
set -euo pipefail

check_contains() {
  local name="$1"
  local url="$2"
  local expected="$3"
  local response=""

  for _attempt in {1..6}; do
    if response="$(curl --fail --silent --show-error --connect-timeout 3 --max-time 10 "$url" 2>/dev/null)"; then
      if [[ "$response" == *"$expected"* ]]; then
        echo "$name: ready"
        return
      fi
    fi
    sleep 5
  done

  echo "$name did not become ready: $url" >&2
  exit 1
}

for port in 8000 8001 8002 8003 8004 8005 8006 8007; do
  check_contains "metrics:$port" "http://localhost:$port/metrics" "whispre_service_info"
done

check_contains "Prometheus" "http://localhost:9090/-/ready" "Prometheus Server is Ready"
check_contains "Loki" "http://localhost:3100/ready" "ready"
check_contains "Alloy" "http://localhost:12345/-/ready" "Alloy is ready"
check_contains "Grafana" "http://localhost:3000/api/health" '"database": "ok"'

targets="$(
  curl --fail --silent --show-error --connect-timeout 3 --max-time 10 \
    --get \
    --data-urlencode 'query=count(up{job="whispre-services"} == 1)' \
    http://localhost:9090/api/v1/query
)"

python3 - "$targets" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
results = payload.get('data', {}).get('result', [])
up_count = int(float(results[0]['value'][1])) if results else 0
if up_count != 8:
    raise SystemExit(f'Expected 8 healthy Whispre scrape targets, got {up_count}')
print('Prometheus scrape targets: 8/8 up')
PY

echo "OBSERVABILITY CHECK PASSED"
