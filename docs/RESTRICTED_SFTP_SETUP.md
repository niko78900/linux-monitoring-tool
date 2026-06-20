# Restricted SFTP Setup

This repository does not apply server changes automatically. Use this document to review and manually configure the restricted SFTP account required by the Android tablet app.

Current mobile behavior:

- The app connects directly with `dartssh2`; file contents are not proxied
  through either FastAPI service.
- The Settings page includes an `SFTP background timeout` option: disconnect
  immediately, 1 minute, 5 minutes, 15 minutes, 30 minutes, or keep until manual
  disconnect.
- Text/code previews are capped client-side. PDF and Office files are downloaded
  to app cache and opened through Android external-app intents.
- Server-side chroot or equivalent restrictions remain mandatory. The mobile
  virtual root is a usability guard, not a security boundary.

## Goal

Expose only warm storage to the mobile app:

```text
Actual data path:        /mnt/warm
Restricted chroot root:  /srv/tablet-sftp
Visible mobile root:     /warm
```

The tablet must not be able to browse:

```text
/
/etc
/home
/mnt/storage
Docker configuration
SSH configuration
```

## Recommended account

Create a dedicated restricted account. Do not reuse the unrestricted shell account.

Suggested account:

```text
tablet_files
```

Use a dedicated SSH key pair for this account.

## Directory layout

Create a root-owned chroot and bind-mount only warm storage into it:

```text
/srv/tablet-sftp
/srv/tablet-sftp/warm
```

Recommended ownership:

```text
/srv/tablet-sftp        root:root   755
/srv/tablet-sftp/warm   root:root   755
```

The bind-mounted content may remain owned by the existing storage owners underneath `/mnt/warm`.

## Read-only bind mount

Initial release is download-focused. Keep the bind mount read-only.

Example commands for manual review:

```bash
sudo mkdir -p /srv/tablet-sftp/warm
sudo mount --bind /mnt/warm /srv/tablet-sftp/warm
sudo mount -o remount,bind,ro /srv/tablet-sftp/warm
```

Persist the mount in `/etc/fstab` only after review.

Example:

```fstab
/mnt/warm  /srv/tablet-sftp/warm  none  bind,ro  0  0
```

## OpenSSH configuration

Add a restricted `Match` block to `sshd_config` after review:

```text
Match User tablet_files
    ChrootDirectory /srv/tablet-sftp
    ForceCommand internal-sftp
    PermitTTY no
    X11Forwarding no
    AllowTcpForwarding no
    PasswordAuthentication no
    PubkeyAuthentication yes
    AuthorizedKeysFile /etc/ssh/authorized_keys/%u
```

Notes:

- `ChrootDirectory` and every parent directory must be owned by `root`.
- Keep the shell disabled for this account.
- Store the authorized key outside the user home if the home would break chroot ownership requirements.

## Account creation checklist

1. Create the system user without a shell.
2. Install only the restricted SFTP public key for that user.
3. Validate chroot permissions before restarting SSH.
4. Restart or reload `sshd`.
5. Test from another host with the restricted key.

## Validation

Confirm all of the following manually:

```text
[ ] The user can log in through SFTP with its dedicated key
[ ] The user cannot open an interactive shell
[ ] The SFTP root shows /warm only
[ ] The user cannot escape above the chroot
[ ] /mnt/storage is not visible
[ ] Download works
[ ] Upload, rename, delete, and mkdir are not available
```

## Mobile app expectations

Configure the Files profile in the app with:

```text
Host:          <server-magicdns-host> or Tailscale IP
Port:          22
Username:      tablet_files
Virtual root:  /warm
```

Import the dedicated restricted private key through the Settings screen.

## Storage display note

The monitoring backend and mobile Storage page hide restricted SFTP bind-mount
paths such as `/srv/sftp/tablet_sftp/WarmStorage` from normal disk displays.
This avoids duplicate storage cards for `/mnt/warm` and its SFTP bind mount.
