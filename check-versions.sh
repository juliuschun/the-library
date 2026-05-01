#!/usr/bin/env bash
# check-versions.sh — read-only drift check across all customer VMs.
#
# For each customer in library.yaml:
#   1. curl https://<domain>/api/health   → actual (live)
#   2. read customers.<name>.current_version → expected (recorded)
#   3. compare & print table
#
# Exit codes: 0 = all in sync, 1 = at least one drift / unreachable.
#
# Usage:
#   bash check-versions.sh              # all customers
#   bash check-versions.sh okusystem    # single customer
#   bash check-versions.sh --write      # update current_version in library.yaml to live value
#
# NOTE: --write only updates the recorded value. It does NOT deploy anything.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBRARY_YAML="${SCRIPT_DIR}/library.yaml"

WRITE_MODE=0
FILTER=""

for arg in "$@"; do
  case "$arg" in
    --write) WRITE_MODE=1 ;;
    --help|-h)
      head -20 "$0" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
    *) FILTER="$arg" ;;
  esac
done

# List customers via python (yaml available on every server).
mapfile -t CUSTOMERS < <(python3 -c "
import yaml, sys
with open('$LIBRARY_YAML') as f:
    data = yaml.safe_load(f)
for name in (data.get('customers') or {}):
    print(name)
")

printf '%-18s %-30s %-14s %-14s %-8s\n' "CUSTOMER" "DOMAIN" "EXPECTED" "LIVE" "STATUS"
printf '%-18s %-30s %-14s %-14s %-8s\n' "--------" "------" "--------" "----" "------"

drift_found=0
declare -A LIVE_VERSIONS

for name in "${CUSTOMERS[@]}"; do
  if [[ -n "$FILTER" && "$name" != "$FILTER" ]]; then continue; fi

  meta=$(python3 -c "
import yaml
with open('$LIBRARY_YAML') as f:
    data = yaml.safe_load(f)
c = data['customers']['$name']
print(c.get('domain') or '')
print(c.get('current_version') or 'null')
")
  domain=$(echo "$meta" | sed -n 1p)
  expected=$(echo "$meta" | sed -n 2p)

  if [[ -z "$domain" ]]; then
    printf '%-18s %-30s %-14s %-14s %-8s\n' "$name" "(no domain)" "$expected" "-" "SKIP"
    continue
  fi

  http_code=$(curl -s --max-time 5 -o /tmp/.tower-health-$$ -w '%{http_code}' "https://${domain}/api/health" 2>/dev/null || echo "000")
  live_json=$(cat /tmp/.tower-health-$$ 2>/dev/null || echo "")
  rm -f /tmp/.tower-health-$$

  if [[ "$http_code" == "401" ]]; then
    # /health is behind authMiddleware → this VM is still on < 1.0.0
    printf '%-18s %-30s %-14s %-14s %-8s\n' "$name" "$domain" "$expected" "< 1.0.0" "STALE"
    drift_found=1
    continue
  fi
  if [[ "$http_code" != "200" || -z "$live_json" ]]; then
    printf '%-18s %-30s %-14s %-14s %-8s\n' "$name" "$domain" "$expected" "HTTP ${http_code}" "DOWN"
    drift_found=1
    continue
  fi

  live=$(echo "$live_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('version','unknown'))" 2>/dev/null || echo "unknown")
  LIVE_VERSIONS["$name"]="$live"

  status="OK"
  if [[ "$expected" == "null" || "$expected" == "None" ]]; then
    status="NEW"
    drift_found=1
  elif [[ "$expected" != "$live" ]]; then
    status="DRIFT"
    drift_found=1
  fi

  printf '%-18s %-30s %-14s %-14s %-8s\n' "$name" "$domain" "$expected" "$live" "$status"
done

if [[ $WRITE_MODE -eq 1 ]]; then
  # Serialize live values into a small JSON dict for python to merge
  tmp_json=$(mktemp)
  {
    echo "{"
    first=1
    for name in "${!LIVE_VERSIONS[@]}"; do
      [[ $first -eq 0 ]] && echo ","
      printf '  "%s": "%s"' "$name" "${LIVE_VERSIONS[$name]}"
      first=0
    done
    echo ""
    echo "}"
  } > "$tmp_json"

  python3 <<PY
import yaml, json, datetime
from pathlib import Path
live = json.loads(Path("$tmp_json").read_text())
p = Path("$LIBRARY_YAML")
data = yaml.safe_load(p.read_text())
now = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
for name, version in live.items():
    if name in data.get("customers", {}):
        data["customers"][name]["current_version"] = version
        data["customers"][name]["version_last_checked"] = now
# Preserve ordering: dump with default_flow_style=False
p.write_text(yaml.safe_dump(data, sort_keys=False, allow_unicode=True))
print("📝 library.yaml updated.")
PY
  rm -f "$tmp_json"
fi

exit $drift_found
