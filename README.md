# rocky-bootstrap

Reusable, modular bootstrap system for fresh **Rocky Linux 9.7** servers.

Run a single entry-point script to provision common roles:

- **base** — system updates, core packages, EPEL/CRB, dev tooling (fzf, zoxide, eza, btop, ripgrep, jq), Europe/Dublin TZ + .ie NTP, firewalld, fail2ban
- **docker** — Docker CE + Compose plugin
- **monitoring** — Grafana Alloy agent (placeholder, edit endpoints)
- **laravel** — PHP 8.3 + Composer + php-fpm (drops an nginx site stub if nginx happens to be installed)
- **nodejs** — Node.js (latest LTS, auto-detected from `nodejs.org/dist/index.json`) via NodeSource. Override with `NODE_MAJOR_OVERRIDE=20`.
- **bashrc** — curated `~/.bashrc` (PATH, NVM, conditional eza/zoxide/fzf, project aliases). Run before `starship`.
- **starship** — Starship prompt + FiraCode Nerd Font + `~/.bashrc` wiring
- **motd** — dynamic login banner (figlet hostname banner + conditional service summary). Run last so it can detect what's installed.

**Optional** (not part of `all` — call explicitly):

- **lamp** — wraps the upstream [rConfig LAMP installer](https://dl.rconfig.com/downloads/rconfig8_centos9.sh). Conflicts with the `laravel` role — run on its own host. Set `RCONFIG_DBPASS=...` for unattended MariaDB setup.

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
│   ├── bashrc                # curated ~/.bashrc template
│   └── login.sh              # dynamic login banner (deployed to /etc/profile.d/)
└── scripts/
    ├── common.sh              # shared helpers (logging, dnf wrappers, idempotency)
    ├── base.sh                # base system, EPEL/CRB, dev tools, TZ + NTP, firewall
    ├── install-docker.sh      # Docker CE + compose plugin
    ├── install-monitoring.sh  # Grafana Alloy (placeholder config)
    ├── install-laravel.sh     # PHP 8.3 + Composer + Laravel deps
    ├── install-nodejs.sh      # Node.js (latest LTS auto-detected) via NodeSource
    ├── install-bashrc.sh      # curated ~/.bashrc with conditional integrations
    ├── install-starship.sh    # Starship prompt + FiraCode Nerd Font
    ├── install-motd.sh        # /etc/profile.d/login.sh banner
    └── install-lamp.sh        # delegates to upstream rConfig LAMP installer (optional)
```

---

## CLI usage

```
./bootstrap.sh                 # interactive wizard
./bootstrap.sh <role> [...]    # run one or more roles
./bootstrap.sh all             # run every role in the recommended order
./bootstrap.sh -h | --help     # show help
```

Valid roles (in `all`): `base`, `docker`, `monitoring`, `laravel`, `nodejs`, `bashrc`, `starship`, `motd`.

Optional (callable but not in `all`): `lamp`.

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
