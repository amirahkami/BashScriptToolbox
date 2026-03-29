# Ubuntu Server Hardening Script

Automated security hardening for fresh Ubuntu Server 24.04 LTS installations.

## Requirements

- Ubuntu Server **24.04 LTS** (x64)
- Root or sudo access
- An SSH public key

## Generating an SSH Key Pair

If you already have an SSH key, skip this section.

On your **local machine** (Mac, Linux, or Windows with Git Bash):

```bash
ssh-keygen -t ed25519 -C "you@company" -f ~/.ssh/you_ed25519
```

Replace `you` with your name or identifier. The `-f` flag names the key file so you can identify it at a glance (e.g., `alice_ed25519`, `bob_ed25519`).

When prompted:

- **Passphrase:** enter a passphrase for extra security, or press Enter for none

This creates two files:

- `~/.ssh/you_ed25519` — your **private key** (never share this)
- `~/.ssh/you_ed25519.pub` — your **public key** (this goes on the server)

To view your public key:

```bash
cat ~/.ssh/you_ed25519.pub
```

Copy the entire output — you'll need it when running the script.

## Uploading the Scripts

Copy the scripts to your server and SSH in:

```bash
scp harden.sh verify.sh root@<server-ip>:/root/
ssh root@<server-ip>
```

## Quick Start

### Interactive (recommended for first use)

```bash
bash harden.sh
```

Prompts before each step. You'll be asked for an admin username and your SSH public key.

### Semi-auto (prompts for user and key only)

```bash
bash harden.sh --auto
```

Runs all 15 sections automatically. Still prompts for the admin username and SSH public key.

### Fully unattended (CI/CD, cloud-init, Terraform)

```bash
# Inline key (replace 'deployer' with your chosen username)
bash harden.sh --auto --user deployer --key "ssh-ed25519 AAAA..."

# Key from file
bash harden.sh --auto --user deployer --key-file /root/pubkey.txt
```

`deployer` is an example — use whatever username you want for your admin account (e.g., `alice`, `ops`).

Zero prompts. Suitable for automation pipelines where the key is provided as a secret or dropped on the server before the script runs.

## What the Script Does

### Section 1 — System Update

Updates package lists, upgrades all installed packages, removes unused packages and cached files. Uses `DEBIAN_FRONTEND=noninteractive` to avoid interactive prompts during upgrades.

### Section 2 — Essential Tools

Installs a curated set of tools. No bloat — each one has a specific purpose.

| Tool | Purpose |
|------|---------|
| `htop` | Interactive process viewer for quick triage |
| `ncdu` | Interactive disk usage analyzer |
| `curl` / `wget` | HTTP clients |
| `dnsutils` | DNS troubleshooting (`dig`, `nslookup`) |
| `tmux` | Terminal multiplexer — sessions survive SSH drops |
| `lsof` | Shows which process holds a file or port |
| `jq` | JSON processor for APIs and logs |
| `rsync` | Efficient file sync between servers |
| `zip` / `unzip` | Archive support |
| `nano` | Simple text editor |
| `micro` | Modern terminal editor (syntax highlighting, mouse support, familiar keybindings) |
| `tree` | Directory viewer |
| `git` | Version control |
| `ufw` | Firewall (installed here, configured in section 10) |

### Section 3 — fail2ban

Protects SSH against brute-force attacks. Configuration:

- SSH jail: 3 failed attempts within 10 minutes = 1-hour ban
- Config stored in `/etc/fail2ban/jail.local` (survives package updates)

Useful commands:

```bash
sudo fail2ban-client status sshd      # Check banned IPs
sudo fail2ban-client set sshd unbanip <ip>  # Unban an IP
```

### Section 4 — Disable IPv6

Disables IPv6 on all interfaces via `/etc/sysctl.d/60-disable-ipv6.conf`. Reduces attack surface when IPv6 is not in use.

### Section 5 — Automatic Security Updates

Installs `unattended-upgrades` for security patches only. Auto-reboot is disabled — you decide when to restart.

### Section 6 — Kernel & Network Hardening

Applies sysctl rules via `/etc/sysctl.d/70-hardening.conf`:

| Protection | What It Does |
|-----------|-------------|
| Reverse path filtering | Drops spoofed packets |
| Source route rejection | Blocks attacker-defined routing |
| ICMP broadcast blocking | Prevents smurf attacks |
| ICMP redirect blocking | Prevents traffic rerouting |
| SYN flood protection | Enables syncookies |
| Martian packet logging | Logs impossible source addresses |
| ASLR | Randomizes memory layout |
| IP forwarding disabled | Server is not a router |

**Note:** If a server later becomes a VPN gateway, re-enable `net.ipv4.ip_forward = 1`.

### Section 7 — Secure Shared Memory

Adds `noexec`, `nosuid`, `nodev` flags to `/run/shm` in `/etc/fstab`. Prevents certain privilege escalation techniques. Takes effect after reboot.

### Section 8 — Login Warning Banner

Writes a legal warning to `/etc/issue.net` and wires it into sshd. Displayed to anyone attempting to connect via SSH.

### Section 9 — Timezone & Locale

- **Timezone:** UTC for consistent timestamps across servers
- **Locale:** `en_US.UTF-8` for English system messages and proper character encoding
- **NTP:** Verifies `systemd-timesyncd` is active, enables it if not

### Section 10 — Default-Deny Firewall

Enables UFW with:

- Default deny all incoming traffic
- Default allow all outgoing traffic
- SSH (port 22/tcp) allowed

Everything else is blocked until explicitly opened.

```bash
sudo ufw status verbose                          # Check rules
sudo ufw allow 5432/tcp comment "PostgreSQL"     # Open a port
sudo ufw allow from 10.0.0.0/24 to any port 5432 proto tcp  # Restrict by source
sudo ufw delete allow 5432/tcp                   # Remove a rule
```

### Section 11 — SSH Hardening

Creates a dedicated admin user with passwordless sudo and sets up SSH key authentication.

Ubuntu 24.04 uses drop-in config files in `/etc/ssh/sshd_config.d/`. The script writes hardening as `01-hardening.conf` and removes conflicting cloud-init drop-ins.

**Flow:**

1. Creates the user (or skips if already exists), adds to sudo group, grants passwordless sudo
2. Accepts the SSH public key (prompt, `--key`, or `--key-file`)
3. Sets up `~/.ssh/authorized_keys` with correct permissions (700/600)
4. Verifies the key (file exists, correct format, correct permissions)
5. **If verification passes:** writes drop-in config, disables password auth, root login, empty passwords, X11 forwarding. Sets max auth tries to 3 and login grace time to 60 seconds. Only the specified user can log in.
6. **If verification fails:** leaves password auth enabled and prints instructions to fix manually.

Backups of both `sshd_config` and the `sshd_config.d/` directory are created before changes. If validation fails, everything is restored automatically.

### Section 12 — Disable Unused Services

Stops and removes services that shouldn't run on a production server:

| Service | Why Remove |
|---------|-----------|
| `snapd` | Snap package manager — apt is sufficient |
| `avahi-daemon` | Broadcasts hostname on local network |
| `cups` / `cups-browsed` | Print server |

Each service is checked before removal. Missing services are silently skipped.

### Section 13 — Restrict su Access

Configures PAM so only users in the sudo group can use `su`. Service accounts cannot attempt to switch to root even if compromised.

### Section 14 — Core Dump Restrictions

Disables core dumps at three levels (user limits, kernel, systemd). Prevents sensitive data from being written to disk when a process crashes.

### Section 15 — File Permissions Audit

Scans and fixes world-writable files and overly permissive home directories.

## After Running the Script

1. **Test login** from a new terminal before closing the root session:
   ```bash
   ssh -i ~/.ssh/<your-key> <username>@<server-ip>
   ```

2. **Open any additional ports** your services need:
   ```bash
   sudo ufw allow <port>/<tcp|udp> comment "Description"
   ```

3. **Reboot** to apply shared memory and kernel changes:
   ```bash
   sudo reboot
   ```

4. **Verify hardening** (optional):
   ```bash
   sudo bash /root/verify.sh
   ```

## Understanding Root Access After Hardening

After the script runs, your admin user is **not** root — it's a regular user with `sudo` privileges. The root user still exists (removing it would break the system), but all external paths to it are blocked:

- **SSH as root** — blocked (`PermitRootLogin no`)
- **Password login** — blocked (`PasswordAuthentication no`)
- **Direct access to `/root/`** — denied (`700` permissions, owned by root)
- **su to root** — blocked for non-sudo users (`pam_wheel.so`)

Your admin user can do anything root can, but only explicitly through `sudo`:

```bash
sudo bash /root/verify.sh          # Run a script as root
sudo ls /root/                      # List files in /root/
sudo cat /etc/ssh/sshd_config      # Read protected config files
sudo -i                             # Drop into a full root shell (type 'exit' to return)
```

Without `sudo`, commands like `cd /root` or `cat /root/verify.sh` will be denied. This is by design — every privileged action is intentional and auditable.

Note: `cd` is a shell built-in and cannot be used with `sudo` directly. Use `sudo -i` to get a root shell if you need to browse protected directories.

## Verification Script

`verify.sh` is a separate read-only script that checks all 15 hardening measures and reports pass/fail. It makes no changes to the system. Run it any time to audit a server's hardening status.

```bash
sudo bash /root/verify.sh
```

## Troubleshooting

### Locked out of SSH

Access the server via your provider's console (DigitalOcean, AWS, etc.), then:

```bash
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config.d/01-hardening.conf
systemctl restart ssh
```

Fix the key, then disable password auth again.

### UFW blocking a needed service

```bash
sudo ufw status verbose                    # Check what's blocked
sudo ufw allow <port>/<tcp|udp>           # Open a port
sudo ufw disable                           # Emergency: disable firewall
```

### fail2ban banned your IP

```bash
sudo fail2ban-client status sshd                    # Check bans
sudo fail2ban-client set sshd unbanip <your-ip>     # Unban
```

### Check which ports are open

```bash
sudo ss -tulnp                  # Using ss (preinstalled)
sudo lsof -i -P -n | grep LISTEN   # Using lsof
```

### Can't cd into /root/

This is expected. Your admin user can't browse `/root/` directly. Use `sudo -i` to get a root shell, or prefix commands with `sudo`:

```bash
sudo ls /root/
sudo -i              # Full root shell — type 'exit' to return
```

## File Locations

| File | Purpose |
|------|---------|
| `/etc/fail2ban/jail.local` | fail2ban configuration |
| `/etc/sysctl.d/60-disable-ipv6.conf` | IPv6 disable |
| `/etc/sysctl.d/70-hardening.conf` | Kernel/network hardening |
| `/etc/sysctl.d/80-no-core-dumps.conf` | Core dump disable (kernel) |
| `/etc/security/limits.d/99-no-core-dumps.conf` | Core dump disable (user limits) |
| `/etc/apt/apt.conf.d/20auto-upgrades` | Auto-update schedule |
| `/etc/apt/apt.conf.d/50unattended-upgrades` | Auto-update sources |
| `/etc/issue.net` | Login warning banner |
| `/etc/ssh/sshd_config` | SSH server configuration |
| `/etc/ssh/sshd_config.d/01-hardening.conf` | SSH hardening drop-in |
| `/etc/ssh/sshd_config.bak.*` | SSH config backup |
| `/etc/ssh/sshd_config.d.bak.*` | SSH drop-in directory backup |
| `/etc/sudoers.d/<username>` | Passwordless sudo for admin user |
| `/etc/pam.d/su` | su access restriction |
| `/etc/fstab` | Shared memory hardening |

## Compatibility

| Ubuntu Version | Status |
|---------------|--------|
| 24.04 LTS | Tested and supported |
| 22.04 LTS | Not supported |
| Non-LTS releases | Not supported |

## License

MIT
