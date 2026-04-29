# rocky-bootstrap

Reusable, modular bootstrap system for fresh **Rocky Linux 9.7** servers.

Run a single entry-point script to provision common roles:

- **base** — system updates, core packages, EPEL/CRB, dev tooling (fzf, zoxide, eza, btop, ripgrep, jq), Europe/Dublin TZ + .ie NTP, firewalld, fail2ban
- **docker** — Docker CE + Compose plugin
- **web** — Nginx with sane defaults
- **monitoring** — Grafana Alloy agent (placeholder, edit endpoints)
- **laravel** — PHP 8.3 + Composer + Nginx site stub
- **starship** — Starship prompt + FiraCode Nerd Font + `~/.bashrc` wiring
- **motd** — dynamic login banner (figlet hostname banner + conditional service summary). Run last so it can detect what's installed.

Designed to be idempotent: safe to re-run after a partial failure or on an already-provisioned host.

---

## Quick start

### Option A — one-shot curl (no git needed)

`bootstrap.sh` self-fetches the rest of the repo to `/opt/rocky-bootstrap` on first run, so you can pipe it straight to bash on a fresh box:

```bash
# Run a single role:
curl -fsSL https://raw.githubusercontent.com/stephenstack/rocky-bootstrap/main/bootstrap.sh \
  | sudo bash -s -- base

# Or run everything:
curl -fsSL https://raw.githubusercontent.com/stephenstack/rocky-bootstrap/main/bootstrap.sh \
  | sudo bash -s -- all
```

When piped without args (no tty), it defaults to `all`. When run with args, only those roles run.

### Option B — clone, then run

```bash
sudo dnf install -y git
sudo git clone https://github.com/stephenstack/rocky-bootstrap.git /opt/rocky-bootstrap
cd /opt/rocky-bootstrap

sudo ./bootstrap.sh             # interactive wizard
sudo ./bootstrap.sh base        # single role
sudo ./bootstrap.sh all         # everything
```

### Re-running

After the first run the repo lives at `/opt/rocky-bootstrap`. To pick up changes:

```bash
sudo git -C /opt/rocky-bootstrap pull && sudo /opt/rocky-bootstrap/bootstrap.sh base
```

Or just re-curl — `ensure_repo` in `bootstrap.sh` skips files already cached on disk. Delete `/opt/rocky-bootstrap` to force a clean fetch.

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
│   ├── motd                  # static login banner (legacy, cleared by motd role)
│   ├── starship.toml         # Starship prompt config (catppuccin_mocha)
│   └── login.sh              # dynamic login banner (deployed to /etc/profile.d/)
└── scripts/
    ├── common.sh              # shared helpers (logging, dnf wrappers, idempotency)
    ├── base.sh                # base system, EPEL/CRB, dev tools, TZ + NTP, firewall
    ├── install-docker.sh      # Docker CE + compose plugin
    ├── install-web.sh         # Nginx
    ├── install-monitoring.sh  # Grafana Alloy (placeholder config)
    ├── install-laravel.sh     # PHP 8.3 + Composer + Laravel deps
    ├── install-starship.sh    # Starship prompt + FiraCode Nerd Font
    └── install-motd.sh        # /etc/profile.d/login.sh banner
```

---

## CLI usage

```
./bootstrap.sh                 # interactive wizard
./bootstrap.sh <role> [...]    # run one or more roles
./bootstrap.sh all             # run every role in the recommended order
./bootstrap.sh -h | --help     # show help
```

Valid roles: `base`, `docker`, `web`, `monitoring`, `laravel`, `starship`, `motd`.

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
