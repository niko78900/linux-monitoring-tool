#!/bin/sh
set -eu

usage() {
  echo "usage: $0 [--check] <dashboard-bridge-gateway> <dashboard-subnet>" >&2
  exit 64
}

check_only=false
if [ "${1:-}" = "--check" ]; then
  check_only=true
  shift
fi

[ "$#" -eq 2 ] || usage

bridge_host=$1
allowed_network=$2
config_dir=/etc/linux-monitor
target_path=$config_dir/dashboard-control-action.env

for command_name in python3 openssl install mktemp stat find; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "missing required command: $command_name" >&2
    exit 69
  }
done

python3 - "$bridge_host" "$allowed_network" <<'PY'
import ipaddress
import sys

try:
    address = ipaddress.ip_address(sys.argv[1])
    network = ipaddress.ip_network(sys.argv[2], strict=False)
except ValueError as error:
    raise SystemExit(f"invalid bridge address or network: {error}") from error

if address.version != 4 or network.version != 4:
    raise SystemExit("the tracked systemd unit currently requires an IPv4 bridge")
if address not in network:
    raise SystemExit("the bridge gateway must belong to the allowed Dashboard subnet")
PY

if [ "$check_only" = true ]; then
  echo "dashboard action environment inputs validated"
  exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "provisioning must run as root" >&2
  exit 77
fi

if [ -e "$target_path" ]; then
  echo "refusing to overwrite existing $target_path" >&2
  exit 73
fi

if [ -d "$config_dir" ]; then
  [ "$(stat -c '%U:%G' "$config_dir")" = "root:root" ] || {
    echo "$config_dir must be owned by root:root" >&2
    exit 77
  }
  if find "$config_dir" -maxdepth 0 -perm /022 -print -quit | grep -q .; then
    echo "$config_dir must not be writable by group or other" >&2
    exit 77
  fi
else
  install -d -o root -g root -m 0751 "$config_dir"
fi

umask 077
temporary_path=$(mktemp "$config_dir/.dashboard-control-action.env.XXXXXX")
trap 'rm -f -- "$temporary_path"' 0 HUP INT TERM
token=$(openssl rand -hex 32)
{
  printf 'DASHBOARD_CONTROL_ACTION_TOKEN=%s\n' "$token"
  printf 'DASHBOARD_CONTROL_ACTION_HOST=%s\n' "$bridge_host"
  printf 'DASHBOARD_CONTROL_ACTION_PORT=4044\n'
  printf 'DASHBOARD_CONTROL_ACTION_ALLOWED_NETWORKS=%s\n' "$allowed_network"
  printf 'DASHBOARD_ACTION_DB_PATH=/var/lib/linux-monitor/dashboard-actions/dashboard-actions.db\n'
  printf 'DASHBOARD_ACTION_HELPER_PATH=/usr/local/libexec/linux-monitor-dashboard-action-helper\n'
  printf 'DASHBOARD_ACTION_WORKERS=1\n'
  printf 'DASHBOARD_ACTION_QUEUE_SIZE=32\n'
  printf 'DASHBOARD_ACTION_RETENTION_RECORDS=1000\n'
  printf 'DASHBOARD_ACTION_RETENTION_DAYS=90\n'
} > "$temporary_path"
token=
chown root:root "$temporary_path"
chmod 0600 "$temporary_path"
mv -T "$temporary_path" "$target_path"
trap - 0 HUP INT TERM

echo "installed protected action environment at $target_path"
