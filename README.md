# rocky-bootstrap

Reusable, modular bootstrap system for fresh **Rocky Linux 9.7** servers.

Run a single entry-point script to provision common roles:

- **base** — system updates, core packages, admin user, SSH hardening
- **docker** — Docker CE + Compose plugin
- **web** — Nginx with sane defaults
- **monitoring** — Grafana Alloy agent (placeholder, edit endpoints)
- **laravel** — PHP 8.3 + Composer + Nginx site stub

Designed to be idempotent: safe to re-run after a partial failure or on an already-provisioned host.

---

## Quick start

```bash
# As root (or via sudo) on a fresh Rocky 9.7 host:
git clone https://github.com/youruser/rocky-bootstrap.git /opt/rocky-bootstrap
cd /opt/rocky-bootstrap
chmod +x bootstrap.sh scripts/*.sh

# Interactive wizard:
./bootstrap.sh

# Or non-interactive (single role):
./bootstrap.sh base
./bootstrap.sh docker

# Or run everything:
./bootstrap.sh all
```

All output is mirrored to `/var/log/bootstrap.log`.

---

## Repo layout

```
rocky-bootstrap/
├── bootstrap.sh              # main entry point (wizard + CLI)
├── packages.txt              # base package list (one per line, # comments ok)
├── README.md
├── .gitignore
├── files/                    # config files copied to target system
│   ├── sshd_config           # hardened sshd config (review before deploying!)
│   └── motd                  # login banner
└── scripts/
    ├── common.sh             # shared helpers (logging, dnf wrappers, idempotency)
    ├── base.sh               # base system + admin user + SSH
    ├── install-docker.sh     # Docker CE + compose plugin
    ├── install-web.sh        # Nginx
    ├── install-monitoring.sh # Grafana Alloy (placeholder config)
    └── install-laravel.sh    # PHP 8.3 + Composer + Laravel deps
```

---

## CLI usage

```
./bootstrap.sh                 # interactive wizard
./bootstrap.sh <role> [...]    # run one or more roles
./bootstrap.sh all             # run every role in the recommended order
./bootstrap.sh -h | --help     # show help
```

Valid roles: `base`, `docker`, `web`, `monitoring`, `laravel`.

You can chain them: `./bootstrap.sh base docker web`.

`base` is implied — every other role calls it first if it has not run.

---

## Customising

- **Packages:** edit [packages.txt](packages.txt). One package per line, `#` for comments.
- **SSH config:** edit [files/sshd_config](files/sshd_config) before running `base`. The shipped config disables password auth — **make sure your SSH key is in `~/.ssh/authorized_keys` first** or you will lock yourself out.
- **Admin user:** override the default by exporting `ADMIN_USER=ops` (or similar) before running.
- **Monitoring endpoints:** edit [scripts/install-monitoring.sh](scripts/install-monitoring.sh) to point Alloy at your Prometheus/Loki targets.

---

## Re-running

Every script checks whether work is already done before doing it (`rpm -q`, `systemctl is-enabled`, `id -u`, etc.). Re-running is safe and cheap.

Logs append to `/var/log/bootstrap.log` — rotate or truncate as you see fit.

---

## Tested on

- Rocky Linux 9.7 (x86_64), minimal install
- Should work on RHEL 9 / AlmaLinux 9 derivatives with no changes
