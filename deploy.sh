#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-/opt/linux-monitor}"
BACKEND_DIR="${BACKEND_DIR:-$ROOT_DIR/backend}"
FRONTEND_DIR="${FRONTEND_DIR:-$ROOT_DIR/frontend}"
BOT_DIR="${BOT_DIR:-$ROOT_DIR/bot}"

BACKEND_SERVICE="${BACKEND_SERVICE:-linux-monitor-backend}"
BOT_SERVICE="${BOT_SERVICE:-linux-monitor-discord-bot}"
NGINX_SERVICE="${NGINX_SERVICE:-nginx}"

BACKEND_HEALTH_URL="${BACKEND_HEALTH_URL:-http://127.0.0.1:4040/api/health}"
FRONTEND_HEALTH_URL="${FRONTEND_HEALTH_URL:-http://127.0.0.1:4041/api/health}"
FRONTEND_WEB_ROOT="${FRONTEND_WEB_ROOT:-/var/www/linux-monitor/browser}"

RUN_FRONTEND_TESTS="${RUN_FRONTEND_TESTS:-1}"
ALERT_GRACE_DEFAULT="${ALERT_GRACE_DEFAULT:-300}"


log() {
  printf '[deploy] %s\n' "$*"
}


require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf '[deploy] missing required command: %s\n' "$cmd" >&2
    exit 1
  fi
}


require_path() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    printf '[deploy] missing required path: %s\n' "$path" >&2
    exit 1
  fi
}


wait_for_http() {
  local url="$1"
  local label="$2"
  local attempts="${3:-30}"
  local sleep_seconds="${4:-2}"

  for ((i = 1; i <= attempts; i += 1)); do
    if curl -fsS "$url" >/dev/null; then
      log "$label is healthy at $url"
      return 0
    fi
    sleep "$sleep_seconds"
  done

  printf '[deploy] %s health check failed after %s attempts: %s\n' "$label" "$attempts" "$url" >&2
  return 1
}


ensure_frontend_permissions() {
  # Fix common EACCES errors after mixed sudo/non-sudo npm/ng runs.
  if [[ -e "$FRONTEND_DIR/node_modules" ]]; then
    sudo chown -R "$USER:$USER" "$FRONTEND_DIR/node_modules"
  fi
  if [[ -e "$FRONTEND_DIR/dist" ]]; then
    sudo chown -R "$USER:$USER" "$FRONTEND_DIR/dist"
  fi
  if [[ -e "$FRONTEND_DIR/.angular" ]]; then
    sudo chown -R "$USER:$USER" "$FRONTEND_DIR/.angular"
  fi
}


main() {
  require_cmd git
  require_cmd curl
  require_cmd npm
  require_cmd rsync
  require_cmd sudo

  require_path "$ROOT_DIR/.git"
  require_path "$BACKEND_DIR/.venv/bin/python"
  require_path "$BOT_DIR/.venv/bin/python"

  log "Pulling latest code"
  cd "$ROOT_DIR"
  git pull --ff-only origin main

  log "Deploying backend"
  cd "$BACKEND_DIR"
  .venv/bin/pip install -r requirements.txt
  sudo systemctl restart "$BACKEND_SERVICE"
  if ! wait_for_http "$BACKEND_HEALTH_URL" "backend" 45 2; then
    sudo systemctl status "$BACKEND_SERVICE" --no-pager -l || true
    sudo journalctl -u "$BACKEND_SERVICE" -n 120 --no-pager || true
    exit 1
  fi

  log "Deploying frontend"
  cd "$FRONTEND_DIR"
  ensure_frontend_permissions
  npm ci
  if [[ "$RUN_FRONTEND_TESTS" == "1" ]]; then
    npm test
  else
    log "Skipping frontend tests (RUN_FRONTEND_TESTS=$RUN_FRONTEND_TESTS)"
  fi
  npm run check:build
  sudo rsync -a --delete "$FRONTEND_DIR/dist/linux-monitoring-ui/browser/" "$FRONTEND_WEB_ROOT/"
  sudo nginx -t
  sudo systemctl reload "$NGINX_SERVICE"
  if ! wait_for_http "$FRONTEND_HEALTH_URL" "frontend/api" 30 2; then
    sudo tail -n 120 /var/log/nginx/error.log || true
    exit 1
  fi

  log "Deploying bot"
  cd "$BOT_DIR"
  .venv/bin/pip install -r requirements.txt
  if [[ -f .env ]] && ! grep -q '^ALERT_GRACE_SECONDS=' .env; then
    echo "ALERT_GRACE_SECONDS=$ALERT_GRACE_DEFAULT" >> .env
    log "Added ALERT_GRACE_SECONDS=$ALERT_GRACE_DEFAULT to bot/.env"
  fi
  sudo systemctl restart "$BOT_SERVICE"
  sudo systemctl status "$BOT_SERVICE" --no-pager -l

  log "Deployment completed successfully"
}


main "$@"
