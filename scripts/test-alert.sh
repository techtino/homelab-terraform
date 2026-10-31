#!/usr/bin/env bash
# Send a test alert straight to Alertmanager and wait for it to reach Pushover.
# The alert expires after a few minutes, so a "resolved" notification follows
# within about 5 minutes of that (Alertmanager's group_interval).
#
# Usage: scripts/test-alert.sh [warning|critical]   (default: warning)
set -euo pipefail

severity="${1:-warning}"
case "$severity" in
  warning | critical) ;;
  *)
    echo "Usage: $0 [warning|critical]" >&2
    exit 1
    ;;
esac

port="${LOCAL_PORT:-19093}"
am="http://localhost:$port"

kubectl port-forward -n observability svc/vmalertmanager-alertmanager "$port:9093" >/dev/null &
pf_pid=$!
trap 'kill "$pf_pid" 2>/dev/null || true' EXIT

for _ in $(seq 1 20); do
  curl -sf "$am/-/ready" >/dev/null && break
  sleep 0.5
done

sent_count() {
  curl -sf "$am/metrics" |
    awk '/^alertmanager_notifications_total\{integration="pushover"\}/ { print $2 }'
}

failed_count() {
  curl -sf "$am/metrics" |
    awk '/^alertmanager_notifications_failed_total\{integration="pushover"/ { sum += $2 } END { print sum + 0 }'
}

sent_before="$(sent_count)"
failed_before="$(failed_count)"
ends_at="$(date -u -d '+3 minutes' +%Y-%m-%dT%H:%M:%SZ)"

curl -sf -H 'Content-Type: application/json' "$am/api/v2/alerts" -d @- <<EOF
[{
  "labels": {
    "alertname": "PushoverTest",
    "severity": "$severity",
    "namespace": "observability",
    "test_run": "$(date +%s)"
  },
  "annotations": {
    "summary": "Test alert from scripts/test-alert.sh",
    "description": "Manual test of Alertmanager to Pushover. It resolves on its own after $ends_at."
  },
  "endsAt": "$ends_at"
}]
EOF
echo "Sent a $severity test alert; waiting for Alertmanager to notify Pushover..."

# A new alert group is sent after group_wait (30s). If an earlier test alert is
# still in the group, the unique test_run label makes this a new alert, which
# goes out at the group's next group_interval (up to 5m) instead.
for _ in $(seq 1 110); do
  sleep 3
  if [ "$(failed_count)" != "$failed_before" ]; then
    echo "Pushover notification failed; check the Alertmanager logs:" >&2
    echo "  kubectl logs -n observability vmalertmanager-alertmanager-0 -c alertmanager" >&2
    exit 1
  fi
  if [ "$(sent_count)" != "$sent_before" ]; then
    echo "Pushover notification sent. A resolved notification follows after $ends_at."
    exit 0
  fi
done

echo "No Pushover notification after 5.5 minutes." >&2
exit 1
