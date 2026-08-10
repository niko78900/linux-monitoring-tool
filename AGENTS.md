# Repository Guidance

## Purpose and scope

This repository is a private homelab monitoring monorepo with five primary
components and several optional, security-isolated control services. Work from
the repository root unless a command below explicitly changes directories.

The authoritative overview is `README.md`. Read the README for the component
you are changing and the matching document under `docs/` before changing an
API, deployment boundary, or security-sensitive workflow. Some later sections
of `docs/EXTENSIVE_DOCUMENTATION.md` describe the older three-service design;
its opening ownership summary and the focused component documents take
precedence.

## Architecture and ownership

- `backend/`: FastAPI monitoring API on port 4040. It owns read-only system,
  GPU, Docker, and summary telemetry; SQLite history; alert evaluation and
  persistence; and Firebase mobile push delivery.
- `frontend/`: Angular 20 read-only dashboard on port 4041. It polls only the
  monitoring backend. It must not grow control-agent, SSH/SFTP, Wake-on-LAN,
  mobile-registration, or other privileged behavior without an explicit
  architecture decision.
- `bot/`: Discord presentation client. It reads monitoring and alert events
  from the backend. Alert thresholds and state belong to the backend; the bot
  retains only Discord delivery/scheduling state and a local backend-down
  warning.
- `control_agent/`: FastAPI control plane on port 4042 for authenticated,
  allowlisted Wake-on-LAN, host/device discovery, service actions, and
  benchmarks. It is deliberately separate from telemetry.
- `mobile/`: one Android-only Flutter package with separately installable
  `tablet` and `phone` flavors. Tablet (`com.niko.homelab_tablet`) consumes both
  APIs and directly provides SSH/SFTP. Phone is displayed as `Mobile Homelab`
  (`com.niko.homelab_monitor`, entry point `lib/main_phone.dart`) and is limited
  to read-only monitoring/history, widgets, mobile alerts, and the fixed WOL
  action. Sensitive tokens, keys/passphrases use secure storage; widget data
  must remain non-sensitive.
- `deploy/systemd/`, `deploy/scripts/`, and `deploy/sudoers/`: sanitized
  deployment and privilege-boundary templates. They are not automatically
  installed.

`control_agent/` also hosts three separate Dashboard-facing applications:

- `app.read_only_main`: read-only bridge, normally port 4043. It has its own
  token and source-network check and must never expose actions, Docker socket
  access, or sudo privileges.
- `app.action_main`: allowlisted asynchronous action service, normally port
  4044. It uses a dedicated token, registry, SQLite store, unprivileged account,
  and exact root-owned helper/sudo rule.
- `app.backup_main`: allowlisted backup orchestrator, normally port 4045. It
  accepts plan IDs rather than caller paths or commands and uses a separate
  token, registry, SQLite store, account, and exact helper/sudo rule.

Do not merge these applications or reuse credentials between them. Keep their
routers, authentication, network allowlists, registries, state, helpers,
accounts, ports, and systemd hardening independent.

## Key code paths

- FastAPI service composition lives in each service's `app/main.py` and
  `app/api/router.py`; route handlers should remain thin and delegate to
  `app/services/`.
- Python API contracts are Pydantic models under each `app/models/` directory.
  Settings are immutable dataclasses parsed from environment variables and
  cached with `get_settings()`.
- Backend system collection is split under `backend/app/services/system/`.
  Preserve graceful degradation when Docker, NVML, smartctl, dmidecode, sysfs,
  or other host facilities are unavailable.
- Backend history and alerts start background workers in the FastAPI lifespan.
  Ensure new tasks shut down cleanly and keep blocking host probes off the
  event loop.
- Angular API models and calls live in `frontend/src/app/core/`; dashboard
  orchestration is in `dashboard-facade.service.ts`; reusable presentation
  pieces live under `shared/components/`.
- Flutter follows feature-first `data` / `domain` / `presentation` folders.
  Shared routing, networking, security, formatting, theme, and widgets belong
  under `mobile/lib/core/`. Riverpod manages application state and `go_router`
  owns navigation.
- Flutter form-factor behavior is selected by `AppVariant`. Tablet routes live
  in `core/routing/app_router.dart`; the phone allowlist lives in
  `core/routing/phone_router.dart`. Do not add SSH, SFTP/Files, Hosts, Devices,
  Services, benchmarks, RDP, or broad Actions routes to the phone flavor. Its
  WOL client under `features/actions/data/` must remain limited to health and
  `wake-main-pc` and must never accept a caller-supplied MAC address.
- Discord commands live in `bot/src/commands/`; backend access is centralized
  in `monitoring_client.py`; background behavior lives under `services/`; and
  durable JSON state helpers live under `state/`.

## API and behavior changes

Treat Pydantic response models as contracts shared by multiple clients. When a
payload or route changes, inspect and update all affected consumers:

- Angular: `frontend/src/app/core/models/` and `core/services/`.
- Flutter: feature domain models, API clients/repositories, generated
  `*.g.dart` files, widgets, and model JSON tests.
- Discord: `monitoring_client.py`, formatters/commands, and alert consumer.
- Documentation, `.env.example` files, and tests for the owning component.

Prefer additive, backward-compatible response changes. Preserve explicit
unavailable/degraded states and sanitized user-facing reasons instead of
turning optional subsystem failures into whole-request failures. Never expose
raw exception text, subprocess output, tokens, filesystem contents, or
credentials in an API response, log, manifest, or durable history.

## Security invariants

- Keep telemetry read-only and privileged operations in the control plane.
- Privileged targets and operations must come from reviewed allowlists. Do not
  accept arbitrary shell commands, command arguments, units, containers,
  environment variables, source paths, destination paths, or restore/delete
  operations from callers.
- Execute helpers with fixed argument arrays and bounded JSON protocols; never
  introduce shell interpolation. Keep request sizes, output sizes, timeouts,
  queues, concurrency, and history bounded.
- Retain bearer authentication, direct peer/source-network validation, strict
  Pydantic schemas (`extra="forbid"` where used), rate limiting, redacted
  errors, idempotency, and busy-target/plan exclusion.
- `CONTROL_API_TOKEN` is the full tablet/control-plane credential.
  `WAKE_API_TOKEN` is the phone credential and may authenticate only control
  health and the fixed WOL route. Keep them distinct; never authorize host,
  device, service, or benchmark routes with the Wake credential.
- Do not broaden service bind addresses, CORS, Docker access, supplementary
  groups, sudoers entries, systemd capabilities, `ReadWritePaths`, or
  executable allowlists as a convenience fix.
- Backup changes must remain non-destructive: no restores, snapshot deletion,
  source deletion, overwrite, or copying live PostgreSQL storage. Preserve the
  fresh privileged preflight; the assessment cache is observational, never an
  authorization boundary.
- A change to Dashboard action or backup behavior requires its focused docs,
  registry example, helper, systemd/sudoers template, and security tests to be
  reviewed together.

## Configuration and repository hygiene

Use only tracked `.env.example`, `*.example.yaml`, and `*.example.yml` files for
development instructions and fixtures. Never commit or print live `.env`
files, API or Discord tokens, Firebase credentials, SSH keys, Android signing
material, machine-specific registries, databases, logs, or state files.

Generated/dependency/runtime directories such as `.venv/`, `__pycache__/`,
`.pytest_cache/`, `frontend/node_modules/`, `frontend/dist/`,
`frontend/.angular/`, `.dart_tool/`, and `mobile/build/` are ignored and should
not be hand-edited. The Flutter `*.g.dart` model files are tracked; regenerate
them after changing their annotated source models:

```bash
cd mobile
dart run build_runner build --delete-conflicting-outputs
```

Production configuration and mutable state live outside Git. The canonical
layout is documented in `docs/CANONICAL_DEPLOYMENT.md`, primarily under
`/etc/linux-monitor/` and `/var/lib/linux-monitor/`. The source checkout is
`/mnt/warm/homelab/linux-monitoring` in the tracked systemd templates. There is
no active repository Docker Compose deployment.

`deploy.sh` is a separate, mutating deployment workflow: it pulls Git changes,
installs dependencies, restarts services, runs `rsync --delete`, and reloads
Nginx. Never run it as a build/check command or against a live host unless the
user explicitly requests a reviewed maintenance-window deployment. Likewise,
do not install units, sudoers files, provision live configuration, enable or
restart services, change firewall rules, or alter live databases as part of a
normal code change.

## Development and verification

Create component-local environments and run commands from the component
directory so the local `app`/`src` imports resolve correctly.

Backend:

```bash
cd backend
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m pytest -q
.venv/bin/python run.py
```

Control agent:

```bash
cd control_agent
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m pytest -q
.venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 4042
```

Bot:

```bash
cd bot
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m unittest discover tests -v
.venv/bin/python src/bot.py
```

Frontend:

```bash
cd frontend
npm ci
npm test
npm run check:build
```

`npm test` requires Chrome/Chromium through Karma. `npm run check:build` is the
non-production development build; `npm run build` also checks production
budgets.

Mobile:

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter test test test_extended
flutter build apk --debug --flavor phone --target lib/main_phone.dart
```

The default Flutter flavor is `tablet`. Phone Firebase configuration belongs at
`mobile/android/app/src/phone/google-services.json`; tablet configuration
belongs under `src/tablet/`. Both files are local credentials and ignored.
The optimized phone artifact is built with
`flutter build apk --release --flavor phone --target lib/main_phone.dart` and
is named `app-phone-release.apk` before any operator-facing rename.

The tracked `mobile/.metadata` revision corresponds to Flutter 3.41.2 stable
and Dart 3.11.0. Prefer that SDK when reproducing the current lockfile. A newer
Flutter SDK can rewrite SDK-pinned test transitive dependencies in
`pubspec.lock`; treat that diff as a deliberate toolchain upgrade, not routine
dependency installation.

The default Flutter suite intentionally excludes the heavier
`test_extended/` cases. Run the extended suite when changing charts, Android
widgets, server-widget snapshots, or mobile alerts. Android build/signing and
release audit instructions are in `docs/ANDROID_RELEASE_GUIDE.md`.

From the repository root, `./scripts/check-core.sh` runs backend and control
agent pytest plus Flutter analyze/default tests. It does not cover the Angular
frontend, Discord bot, or Flutter extended suite. Run the smallest relevant
tests while iterating and the full affected-component checks before handoff.
Tests must use temporary config/state and mocks; do not point them at live
services, registries, databases, Docker workloads, backup storage, Discord, or
Firebase.

## Change discipline

- Preserve unrelated work in a dirty tree and do not rewrite generated lock
  files unless dependency changes require it.
- Match existing formatting: Python uses type hints and small service/model
  units; Angular uses standalone components, dependency injection, RxJS, and
  Prettier's single quotes/100-column setting; Dart follows `flutter_lints`.
- Add regression tests with behavior changes, especially for parsing,
  authentication, redaction, allowlist validation, state transitions,
  persistence, concurrency, and unavailable subsystem handling.
- Update focused documentation when behavior, environment variables, API
  contracts, external paths, deployment steps, or security assumptions change.
- Report checks that were run and any checks skipped because required tooling
  or host facilities were unavailable.
