#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: homelab-service-control <service-id> <action>" >&2
  exit 64
fi

service_id="$1"
action="$2"

case "$service_id:$action" in
  jellyfin:start) exec docker start jellyfin ;;
  jellyfin:stop) exec docker stop jellyfin ;;
  jellyfin:restart) exec docker restart jellyfin ;;
  hfs:start) exec systemctl start hfs.service ;;
  hfs:stop) exec systemctl stop hfs.service ;;
  hfs:restart) exec systemctl restart hfs.service ;;
  *)
    echo "rejected" >&2
    exit 65
    ;;
esac
