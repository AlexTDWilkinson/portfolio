# Deploying this site on a DigitalOcean droplet

One droplet hosts this site and any number of others. Caddy sits on ports 80/443
and routes by hostname; each app is a systemd service on its own local port.
Nothing is compiled on the droplet - `scripts/deploy.sh` runs plain
`cargo build --release` on your machine and copies the binary up. No Docker, no
cross-compiler, no extra tooling.

The binary links only `libc`, `libm` and `libgcc` (rustls, so no OpenSSL) and
needs at most `GLIBC_2.34`. Ubuntu 22.04 ships 2.35 and 24.04 ships 2.39, so it
runs on either. Only if you target something older do you need a static build:
`sudo apt install musl-tools`, and `deploy.sh` picks it up automatically and
switches to `x86_64-unknown-linux-musl`.

Why a droplet: the box already runs `sul.alex-wilkinson.ca` and
`nail.alex-wilkinson.ca`, and a $6/mo droplet runs many apps for one price
where App Platform charges per Web Service. This site idles around 10 MB RAM.

## How the box is organised

Setup splits in two, because the box outlives any one app:

| script | scope | run |
|---|---|---|
| `provision-base.sh` | the box: Caddy, ufw, fail2ban, swap | once per droplet |
| `add-app.sh` | one app: user, `/srv/<app>`, unit, Caddy fragment | once per app |

This whole `deploy/` directory is meant to be **copied into each app's repo**.
No repo is the "lead" - `provision-base.sh` is idempotent and refuses to
overwrite an already-configured box, so whichever repo runs first wins and the
rest are no-ops.

Isolation each app gets:

- its own unix user and `/srv/<app>` at mode 0750 - other apps cannot read it
- `127.0.0.1` binding only, so the app has no publicly reachable socket at all;
  the proxy is the sole entrance and `ufw` only opens 22/80/443
- a systemd sandbox: `ProtectSystem=strict`, `ReadWritePaths=/srv/<app>`,
  `PrivateTmp`, `NoNewPrivileges`
- a memory ceiling (`MemoryMax`, default 192M) so one leak cannot take the
  others down

## One-time setup

1. Create the droplet: Ubuntu 24.04 or newer, Basic / Regular. The $4 512 MB
   size is enough - nothing is ever built here.

2. Prepare the box (once, ever):

   ```bash
   scp -r deploy root@<droplet-ip>:/tmp/deploy
   ssh root@<droplet-ip> 'bash /tmp/deploy/provision-base.sh'
   ```

3. Register this app on it:

   ```bash
   ssh root@<droplet-ip> \
     'bash /tmp/deploy/add-app.sh --name portfolio --port 3002 --bin alex-portfolio --host "alex-wilkinson.ca, www.alex-wilkinson.ca" --mem 128M'
   ```

   Pass `--host` once DNS points here and HTTPS is automatic (multiple hostnames go in one comma-separated string).
   Without `--host` the app answers on the bare IP over HTTP; only one app on
   the box can hold that.

4. Deploy from your machine:

   ```bash
   ./scripts/deploy.sh --push-env
   ```

   Host comes from `DEPLOY_HOST` in `.env`. `--push-env` uploads your `.env` to
   `/srv/portfolio/env` (mode 0600, `DEPLOY_*` keys stripped - the droplet never
   receives its own password). Only needed the first time or when a secret
   changes.

5. Visit `http://<droplet-ip>/`.

## Adding the second, third, fourth app

From the *other* repo, with this `deploy/` directory copied into it:

```bash
scp -r deploy root@<droplet-ip>:/tmp/deploy
ssh root@<droplet-ip> 'bash /tmp/deploy/provision-base.sh'   # no-op, box already set up
ssh root@<droplet-ip> 'bash /tmp/deploy/add-app.sh --name blog --port 3001 --bin blog --host blog.example.com'
```

Then that repo's own deploy script ships its binary to `/srv/blog`. Nothing in
this repo changes, and neither app can see the other's files. `add-app.sh`
refuses a port another app already claimed.

A purely static site needs no app user at all - just a `root` + `file_server`
block in its own `/etc/caddy/sites.d/<name>.caddy`.

## If you use an SSH password instead of a key

Password auth works fine here. Two things make it comfortable and safe:

**1. Connection reuse, so a deploy asks once instead of four times.**
`deploy.sh` opens four SSH connections (rsync, scp, two `ssh`). Add this to
`~/.ssh/config` on your machine and the first one authenticates while the rest
ride the same tunnel:

```
Host sul
    HostName <droplet-ip>
    User root
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 10m
```

Then deploy with `./scripts/deploy.sh sul` - one password prompt, and none at
all for ten minutes after.

**2. Keep the password long and random.** 20+ characters out of a password
manager. `fail2ban` (installed by `provision-base.sh`) bans an IP for 15 minutes
after 5 failures, so guessing is hopeless against a password of that size.

One habit worth keeping: if SSH ever warns that the host key changed, stop and
find out why before typing the password. That warning is the one moment where
password auth can lose you the server and key auth cannot.

## Everyday deploy

```bash
./scripts/deploy.sh root@<droplet-ip>
```

Builds, uploads binary + `static/`, restarts the service, health-checks it, and
dumps the last 30 log lines if the check fails. Roughly 10-20 s warm. Put
`DEPLOY_HOST=root@<droplet-ip>` in `.env` and you can drop the argument.

## Adding a domain

1. DO control panel -> Networking -> Domains, add an A record for the hostname
   pointing at the droplet IP (AAAA for the IPv6 too, if you like).
2. Re-run `add-app.sh` with `--host <domain>` - it rewrites only this app's
   fragment, `/etc/caddy/sites.d/portfolio.caddy`, and reloads Caddy.
3. The HTTPS certificate is issued automatically within a few seconds. Nothing
   to renew, ever.

## Operating

```bash
systemctl status portfolio             # is it up
journalctl -u portfolio -f             # live logs
journalctl -u caddy -n 50        # cert / proxy problems
systemctl restart portfolio
```

## Notes

- `reqwest` uses rustls, not OpenSSL - no system TLS libraries to install on the
  droplet, and no `libssl` version to keep in sync.
- Build on a machine whose glibc is no newer than the droplet's. Ubuntu 22.04
  local -> Ubuntu 24.04 droplet is the safe direction; the reverse can fail with
  `version 'GLIBC_2.xx' not found`. `apt install musl-tools` removes the
  question entirely.
- Secrets live only in `/srv/portfolio/env`, read by systemd's `EnvironmentFile`. The
  app's `dotenvy` call finds no `.env` on the droplet, which is fine.
- The dictionary is cached in memory and refetched from the sheet on restart,
  so a deploy is also how you pick up sheet edits.
- `static/` is synced with `rsync --delete`: files removed locally are removed
  on the server.
