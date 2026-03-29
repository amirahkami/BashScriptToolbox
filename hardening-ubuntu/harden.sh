#!/usr/bin/env bash
# =============================================================================
#  Ubuntu Server 24.04 LTS — Hardening Script
#  Version: 1.0.0
# =============================================================================
#
#  Automated security hardening for fresh Ubuntu Server 24.04 LTS installations.
#
#  Usage:
#    Interactive:
#      sudo bash harden.sh
#
#    Unattended (prompts for username and key only):
#      sudo bash harden.sh --auto
#
#    Fully unattended (CI/CD, cloud-init, Terraform):
#      sudo bash harden.sh --auto --user <username> --key "ssh-ed25519 AAAA..."
#      sudo bash harden.sh --auto --user <username> --key-file /path/to/pubkey
#
# =============================================================================

set -euo pipefail

VERSION="1.0.0"

# ---------------------------------------------------------------------------
#  Argument parsing
# ---------------------------------------------------------------------------
MODE="interactive"
ARG_USER=""
ARG_KEY=""
ARG_KEY_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)      MODE="auto"; shift ;;
        --user)      ARG_USER="$2"; shift 2 ;;
        --key)       ARG_KEY="$2"; shift 2 ;;
        --key-file)  ARG_KEY_FILE="$2"; shift 2 ;;
        *)           echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
#  Colors and output helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[FAIL]${NC}  $1"; }

separator() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Prompt for confirmation in interactive mode. Auto mode always proceeds.
confirm_step() {
    local description="$1"
    if [[ "$MODE" == "auto" ]]; then
        return 0
    fi
    echo ""
    read -rp "$(echo -e "${YELLOW}▶ ${description} [Y/n]: ${NC}")" answer
    case "${answer,,}" in
        n|no) return 1 ;;
        *)    return 0 ;;
    esac
}

# ---------------------------------------------------------------------------
#  Pre-flight checks
# ---------------------------------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
    error "This script must be run as root. Use: sudo bash harden.sh"
    exit 1
fi

# Check Ubuntu version. Only 24.04 LTS is supported.
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" || ! "$VERSION_ID" =~ ^24\.04 ]]; then
        error "This script requires Ubuntu 24.04 LTS."
        error "Detected: $PRETTY_NAME"
        exit 1
    fi
else
    error "Cannot detect OS version. This script requires Ubuntu 24.04 LTS."
    exit 1
fi

separator
echo -e "${GREEN}  Ubuntu Server Hardening Script v${VERSION}${NC}"
echo -e "  Mode: ${YELLOW}${MODE}${NC}"
echo -e "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "  Host: $(hostname)"
separator

# Track what was applied for the summary at the end.
declare -a APPLIED=()
declare -a SKIPPED=()
declare -a WARNINGS=()

track() {
    local label="$1"
    local status="$2"
    if [[ "$status" == "applied" ]]; then
        APPLIED+=("$label")
    else
        SKIPPED+=("$label")
    fi
}

# =============================================================================
#  1. SYSTEM UPDATE & UPGRADE
# =============================================================================
if confirm_step "Update & upgrade system packages"; then
    info "Updating package lists..."
    apt-get update -y
    info "Upgrading installed packages..."
    # DEBIAN_FRONTEND prevents interactive prompts (e.g. openssh config).
    # force-confnew accepts the maintainer's version of changed config files.
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
        -o Dpkg::Options::="--force-confnew"
    info "Removing unused packages..."
    apt-get autoremove -y
    apt-get autoclean -y
    success "System updated and upgraded."
    track "System update & upgrade" "applied"
else
    warn "Skipped system update."
    track "System update & upgrade" "skipped"
fi

# =============================================================================
#  2. INSTALL ESSENTIAL TOOLS
#
#  htop       — interactive process viewer
#  ncdu       — disk usage analyzer
#  curl/wget  — HTTP clients
#  dnsutils   — dig and nslookup for DNS troubleshooting
#  tmux       — terminal multiplexer, sessions survive SSH drops
#  lsof       — shows which process holds a file or port
#  jq         — JSON processor for APIs and logs
#  rsync      — efficient file sync between servers
#  zip/unzip  — archive support
#  nano       — simple text editor
#  micro      — modern terminal editor (syntax highlighting, mouse support)
#  tree       — directory viewer
#  git        — version control
#  ufw        — firewall (installed here, configured in section 10)
# =============================================================================
separator
if confirm_step "Install essential tools"; then
    info "Installing essential tools..."
    apt-get install -y \
        htop        \
        ncdu        \
        curl        \
        wget        \
        dnsutils    \
        tmux        \
        lsof        \
        jq          \
        rsync       \
        zip         \
        unzip       \
        nano        \
        micro       \
        tree        \
        git         \
        ufw
    success "Essential tools installed."
    track "Install essential tools" "applied"
else
    warn "Skipped tool installation."
    track "Install essential tools" "skipped"
fi

# =============================================================================
#  3. INSTALL & CONFIGURE FAIL2BAN
#
#  Protects SSH against brute-force attacks.
#  Config goes in jail.local so it survives package updates.
#  SSH jail: 3 retries within 10 minutes = 1-hour ban.
# =============================================================================
separator
if confirm_step "Install and configure fail2ban"; then
    info "Installing fail2ban..."
    apt-get install -y fail2ban

    info "Writing /etc/fail2ban/jail.local..."
    cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
# Ban for 1 hour after 5 failures within a 10-minute window.
bantime  = 3600
findtime = 600
maxretry = 5
banaction = iptables-multiport

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
EOF

    systemctl enable fail2ban
    systemctl restart fail2ban
    success "fail2ban installed and configured."
    track "fail2ban" "applied"
else
    warn "Skipped fail2ban."
    track "fail2ban" "skipped"
fi

# =============================================================================
#  4. DISABLE IPv6
#
#  Reduces attack surface. Applied via a dedicated sysctl drop-in file
#  so it persists across reboots and doesn't conflict with other configs.
# =============================================================================
separator
if confirm_step "Disable IPv6 system-wide"; then
    info "Disabling IPv6 via sysctl..."
    cat > /etc/sysctl.d/60-disable-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
    sysctl --system > /dev/null 2>&1
    success "IPv6 disabled."
    track "Disable IPv6" "applied"
else
    warn "Skipped IPv6 disable."
    track "Disable IPv6" "skipped"
fi

# =============================================================================
#  5. AUTOMATIC SECURITY UPDATES
#
#  Installs unattended-upgrades for security patches only.
#  Auto-reboot is disabled — you control when servers restart.
# =============================================================================
separator
if confirm_step "Enable automatic security updates"; then
    info "Installing unattended-upgrades..."
    apt-get install -y unattended-upgrades apt-listchanges

    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

    systemctl enable unattended-upgrades
    systemctl restart unattended-upgrades
    success "Automatic security updates enabled."
    track "Automatic security updates" "applied"
else
    warn "Skipped unattended-upgrades."
    track "Automatic security updates" "skipped"
fi

# =============================================================================
#  6. KERNEL & NETWORK HARDENING (sysctl)
#
#  Applies low-level protections:
#    - Reverse path filtering (anti-spoofing)
#    - Source route rejection
#    - ICMP broadcast/redirect blocking
#    - SYN flood protection via syncookies
#    - Martian packet logging
#    - ASLR (address space layout randomization)
#    - IP forwarding disabled (re-enable if server becomes a gateway)
# =============================================================================
separator
if confirm_step "Apply kernel/network hardening"; then
    info "Writing sysctl hardening rules..."
    cat > /etc/sysctl.d/70-hardening.conf <<'EOF'
# --- IP Spoofing / Source Routing ---
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# --- ICMP Hardening ---
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# --- SYN Flood Protection ---
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# --- Martian Packet Logging ---
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# --- Disable IP Forwarding ---
# Re-enable if this server becomes a router or VPN gateway.
net.ipv4.ip_forward = 0

# --- Kernel ASLR ---
kernel.randomize_va_space = 2
EOF

    sysctl --system > /dev/null 2>&1
    success "Kernel/network hardening applied."
    track "Kernel/network sysctl hardening" "applied"
else
    warn "Skipped sysctl hardening."
    track "Kernel/network sysctl hardening" "skipped"
fi

# =============================================================================
#  7. SECURE SHARED MEMORY
#
#  Restricts /run/shm with noexec, nosuid, nodev to prevent
#  certain privilege escalation techniques.
# =============================================================================
separator
if confirm_step "Harden shared memory (/run/shm)"; then
    info "Adding shared memory restriction to /etc/fstab..."
    if ! grep -q '/run/shm' /etc/fstab; then
        echo "tmpfs  /run/shm  tmpfs  defaults,noexec,nosuid,nodev  0  0" >> /etc/fstab
        success "Shared memory hardened (takes effect on next mount/reboot)."
    else
        warn "/run/shm entry already exists in /etc/fstab — skipping."
    fi
    track "Secure shared memory" "applied"
else
    warn "Skipped shared memory hardening."
    track "Secure shared memory" "skipped"
fi

# =============================================================================
#  8. LOGIN WARNING BANNER
#
#  Sets a legal warning banner displayed before SSH login.
#  Wired into sshd_config via the Banner directive.
# =============================================================================
separator
if confirm_step "Set login warning banner"; then
    info "Writing /etc/issue.net..."
    cat > /etc/issue.net <<'EOF'
************************************************************
*  WARNING: Unauthorized access to this system is prohibited.
*  All connections are monitored and recorded. Disconnect
*  immediately if you are not an authorized user.
************************************************************
EOF

    SSHD_CONFIG="/etc/ssh/sshd_config"
    if [[ -f "$SSHD_CONFIG" ]]; then
        sed -i '/^#\?Banner/d' "$SSHD_CONFIG"
        echo "Banner /etc/issue.net" >> "$SSHD_CONFIG"
        info "SSH Banner directive added to sshd_config."
    fi

    success "Login banner configured."
    track "Login warning banner" "applied"
else
    warn "Skipped login banner."
    track "Login warning banner" "skipped"
fi

# =============================================================================
#  9. TIMEZONE & LOCALE
#
#  Sets UTC for consistent timestamps across servers.
#  Locale set to en_US.UTF-8 for English system messages and proper
#  character encoding. Verifies NTP sync.
# =============================================================================
separator
if confirm_step "Set timezone to UTC and locale to en_US.UTF-8"; then
    info "Setting timezone to UTC..."
    timedatectl set-timezone UTC

    info "Setting locale to en_US.UTF-8..."
    locale-gen en_US.UTF-8 > /dev/null 2>&1
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

    info "Verifying NTP sync..."
    if timedatectl show | grep -q 'NTP=yes'; then
        success "NTP is active and syncing."
    else
        warn "NTP not active — enabling timesyncd..."
        systemctl enable systemd-timesyncd
        systemctl start systemd-timesyncd
        timedatectl set-ntp true
        success "NTP enabled."
    fi

    success "Timezone set to UTC, locale set to en_US.UTF-8."
    track "Timezone & locale" "applied"
else
    warn "Skipped timezone/locale setup."
    track "Timezone & locale" "skipped"
fi

# =============================================================================
#  10. DEFAULT-DENY FIREWALL (UFW)
#
#  Enables UFW with default-deny incoming, allows only SSH (port 22).
#  Open additional ports as needed after running this script:
#    sudo ufw allow <port>/<tcp|udp> comment "Description"
# =============================================================================
separator
if confirm_step "Enable default-deny firewall (UFW), allow SSH only"; then
    info "Configuring UFW..."

    # Reset to clean state in case UFW was previously configured.
    ufw --force reset > /dev/null 2>&1

    # Default policies: deny incoming, allow outgoing.
    ufw default deny incoming
    ufw default allow outgoing

    # Allow SSH so we don't lock ourselves out.
    ufw allow 22/tcp comment "SSH"

    # Enable UFW (--force skips the confirmation prompt).
    ufw --force enable
    success "UFW enabled — default deny incoming, SSH (22/tcp) allowed."
    track "Default-deny firewall (UFW)" "applied"
else
    warn "Skipped UFW setup."
    track "Default-deny firewall (UFW)" "skipped"
fi

# =============================================================================
#  11. SSH HARDENING
#
#  Creates a dedicated admin user with sudo privileges (passwordless),
#  sets up SSH key auth, then verifies the key before locking down.
#
#  Ubuntu 24.04 uses drop-in config files in /etc/ssh/sshd_config.d/.
#  The main sshd_config includes them via "Include" at the top, so
#  drop-ins are processed first (first match wins in OpenSSH).
#  We write our hardening as 01-hardening.conf and remove conflicting
#  cloud-init drop-ins.
#
#  Accepts --user, --key, and --key-file flags for unattended use.
# =============================================================================
separator
if confirm_step "SSH hardening (create admin user, configure key auth)"; then

    # --- Determine username ---
    if [[ -n "$ARG_USER" ]]; then
        USERNAME="$ARG_USER"
    else
        echo ""
        read -rp "$(echo -e "${CYAN}Enter the admin username to create: ${NC}")" USERNAME
        if [[ -z "$USERNAME" ]]; then
            error "No username provided. Skipping SSH hardening."
            WARNINGS+=("SSH hardening incomplete — no username provided.")
            track "SSH hardening" "skipped"
            USERNAME=""
        fi
    fi

    if [[ -n "$USERNAME" ]]; then

        # --- Create user with sudo privileges (passwordless) ---
        if id "$USERNAME" &>/dev/null; then
            info "User '$USERNAME' already exists — skipping creation."
        else
            info "Creating user '$USERNAME' with sudo privileges..."
            adduser --gecos "" --disabled-password "$USERNAME"
            usermod -aG sudo "$USERNAME"
            success "User '$USERNAME' created and added to sudo group."
        fi

        # Grant passwordless sudo. SSH key is the authentication layer.
        echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}"
        chmod 440 "/etc/sudoers.d/${USERNAME}"
        info "Passwordless sudo configured for '$USERNAME'."

        # --- Determine SSH public key ---
        SSH_PUB_KEY=""
        if [[ -n "$ARG_KEY" ]]; then
            SSH_PUB_KEY="$ARG_KEY"
        elif [[ -n "$ARG_KEY_FILE" ]]; then
            if [[ -f "$ARG_KEY_FILE" ]]; then
                SSH_PUB_KEY=$(cat "$ARG_KEY_FILE")
            else
                error "Key file not found: $ARG_KEY_FILE"
            fi
        else
            echo ""
            echo -e "${CYAN}Paste your SSH public key for '$USERNAME' (one line, then press Enter):${NC}"
            echo -e "${YELLOW}Example: ssh-ed25519 AAAAC3NzaC1lZDI1... user@host${NC}"
            echo ""
            read -rp "> " SSH_PUB_KEY
        fi

        if [[ -z "$SSH_PUB_KEY" ]]; then
            error "No key provided. Skipping SSH hardening."
            WARNINGS+=("SSH hardening incomplete — no public key provided.")
            track "SSH hardening" "skipped"
        else
            # --- Set up authorized_keys ---
            SSH_DIR="/home/${USERNAME}/.ssh"
            AUTH_KEYS="${SSH_DIR}/authorized_keys"

            mkdir -p "$SSH_DIR"
            echo "$SSH_PUB_KEY" > "$AUTH_KEYS"
            chmod 700 "$SSH_DIR"
            chmod 600 "$AUTH_KEYS"
            chown -R "${USERNAME}:${USERNAME}" "$SSH_DIR"

            # --- Verify key setup ---
            KEY_VALID=true

            if [[ ! -s "$AUTH_KEYS" ]]; then
                error "authorized_keys is empty."
                KEY_VALID=false
            fi

            if ! grep -qE '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp|sk-ssh-ed25519|sk-ecdsa-sha2) ' "$AUTH_KEYS"; then
                error "Key does not match a recognized SSH key format."
                KEY_VALID=false
            fi

            SSH_DIR_PERMS=$(stat -c '%a' "$SSH_DIR")
            AUTH_KEY_PERMS=$(stat -c '%a' "$AUTH_KEYS")
            if [[ "$SSH_DIR_PERMS" != "700" || "$AUTH_KEY_PERMS" != "600" ]]; then
                error "Incorrect permissions on .ssh directory or authorized_keys."
                KEY_VALID=false
            fi

            # --- Apply hardening or warn ---
            SSHD_CONFIG="/etc/ssh/sshd_config"
            SSHD_DROP_IN="/etc/ssh/sshd_config.d/01-hardening.conf"

            if [[ "$KEY_VALID" == true ]]; then
                info "Key verification passed. Applying full SSH lockdown..."

                # Back up original configs.
                cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
                cp -r /etc/ssh/sshd_config.d /etc/ssh/sshd_config.d.bak.$(date +%Y%m%d%H%M%S)

                # Remove conflicting cloud-init drop-ins.
                rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf
                rm -f /etc/ssh/sshd_config.d/60-cloudimg-settings.conf

                # Write hardening as a drop-in (01 = loads first).
                cat > "$SSHD_DROP_IN" <<EOF
# SSH hardening applied by harden.sh v${VERSION}
PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
X11Forwarding no
LoginGraceTime 60
AllowUsers ${USERNAME}
EOF

                # Create privilege separation directory (Ubuntu 24.04 issue).
                mkdir -p /run/sshd

                # Validate sshd config before restarting.
                if /usr/sbin/sshd -t 2>/tmp/sshd_test_output; then
                    if ! systemctl restart ssh 2>/dev/null; then
                        systemctl reload ssh 2>/dev/null || true
                    fi
                    success "SSH fully hardened. Only '$USERNAME' can log in via key."
                else
                    error "sshd config validation failed:"
                    error "$(cat /tmp/sshd_test_output 2>/dev/null)"

                    # Restore backups.
                    rm -f "$SSHD_DROP_IN"
                    LATEST_DIR_BACKUP=$(ls -dt /etc/ssh/sshd_config.d.bak.* 2>/dev/null | head -1 || true)
                    if [[ -n "$LATEST_DIR_BACKUP" ]]; then
                        cp "$LATEST_DIR_BACKUP"/*.conf /etc/ssh/sshd_config.d/ 2>/dev/null || true
                    fi
                    LATEST_BACKUP=$(ls -t "${SSHD_CONFIG}.bak."* 2>/dev/null | head -1 || true)
                    if [[ -n "$LATEST_BACKUP" ]]; then
                        cp "$LATEST_BACKUP" "$SSHD_CONFIG"
                    fi
                    systemctl restart ssh 2>/dev/null || true
                    WARNINGS+=("SSH config had errors — restored backup. Review manually.")
                fi
                track "SSH hardening (full lockdown)" "applied"
            else
                warn "Key verification failed. Password auth remains ENABLED."
                warn "Fix the key manually, then disable password auth:"
                warn "  1. Add your public key to /home/${USERNAME}/.ssh/authorized_keys"
                warn "  2. Set PasswordAuthentication no in /etc/ssh/sshd_config.d/01-hardening.conf"
                warn "  3. sudo systemctl restart ssh"
                WARNINGS+=("SSH key verification failed — password auth still enabled.")
                track "SSH hardening (partial — key failed)" "applied"
            fi
        fi
    fi
else
    warn "Skipped SSH hardening."
    track "SSH hardening" "skipped"
fi

# =============================================================================
#  12. DISABLE UNUSED SERVICES
#
#  Removes services that have no business running on a production server:
#    - snapd:  Snap package manager — apt is sufficient
#    - avahi:  mDNS/DNS-SD — broadcasts hostname on local network
#    - cups:   Print server
#
#  Each service is checked before removal so the script doesn't fail
#  if it's already absent.
# =============================================================================
separator
if confirm_step "Disable unused services (snapd, avahi, cups)"; then

    for SERVICE in snapd avahi-daemon cups cups-browsed; do
        if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
            info "Stopping $SERVICE..."
            systemctl stop "$SERVICE" 2>/dev/null || true
            systemctl disable "$SERVICE" 2>/dev/null || true
            success "$SERVICE stopped and disabled."
        else
            info "$SERVICE is not running — skipping."
        fi
    done

    for PKG in snapd avahi-daemon cups cups-browsed; do
        if dpkg -l "$PKG" &>/dev/null; then
            info "Removing $PKG..."
            apt-get purge -y "$PKG" > /dev/null 2>&1 || true
        fi
    done

    apt-get autoremove -y > /dev/null 2>&1 || true
    success "Unused services removed."
    track "Disable unused services" "applied"
else
    warn "Skipped unused service removal."
    track "Disable unused services" "skipped"
fi

# =============================================================================
#  13. RESTRICT SU ACCESS
#
#  Limits 'su' to users in the sudo group only. If an attacker
#  compromises a service account (postgres, www-data), they cannot
#  attempt to su to root. Normal service operation is unaffected.
# =============================================================================
separator
if confirm_step "Restrict su access to sudo group only"; then
    info "Configuring PAM to restrict su..."

    PAM_SU="/etc/pam.d/su"

    if grep -q '^#.*pam_wheel.so' "$PAM_SU"; then
        sed -i 's/^#\s*\(auth\s*required\s*pam_wheel.so\)/\1/' "$PAM_SU"
    elif ! grep -q 'pam_wheel.so' "$PAM_SU"; then
        sed -i '/^auth\s*sufficient\s*pam_rootok.so/a auth       required   pam_wheel.so' "$PAM_SU"
    fi

    success "su restricted to sudo group members only."
    track "Restrict su access" "applied"
else
    warn "Skipped su restriction."
    track "Restrict su access" "skipped"
fi

# =============================================================================
#  14. CORE DUMP RESTRICTIONS
#
#  Disables core dumps system-wide. When a process crashes, its memory
#  (which may contain passwords, keys, tokens) won't be written to disk.
# =============================================================================
separator
if confirm_step "Disable core dumps"; then
    info "Disabling core dumps..."

    cat > /etc/security/limits.d/99-no-core-dumps.conf <<'EOF'
*    hard    core    0
*    soft    core    0
EOF

    cat > /etc/sysctl.d/80-no-core-dumps.conf <<'EOF'
fs.suid_dumpable = 0
kernel.core_pattern = |/bin/false
EOF

    sysctl --system > /dev/null 2>&1

    if [[ -d /etc/systemd/coredump.conf.d ]] || [[ -f /etc/systemd/coredump.conf ]]; then
        mkdir -p /etc/systemd/coredump.conf.d
        cat > /etc/systemd/coredump.conf.d/disable.conf <<'EOF'
[Coredump]
Storage=none
ProcessSizeMax=0
EOF
    fi

    success "Core dumps disabled."
    track "Core dump restrictions" "applied"
else
    warn "Skipped core dump restrictions."
    track "Core dump restrictions" "skipped"
fi

# =============================================================================
#  15. FILE PERMISSIONS AUDIT
#
#  Finds and fixes:
#    - World-writable files (anyone can modify them)
#    - Home directories readable by others
# =============================================================================
separator
if confirm_step "Run file permissions audit"; then
    info "Checking for world-writable files..."

    WW_FILES=$(find / -xdev -type f -perm -0002 \
        -not -path '/proc/*' \
        -not -path '/sys/*' \
        -not -path '/dev/*' \
        -not -path '/run/*' \
        -not -path '/tmp/*' \
        2>/dev/null || true)

    if [[ -n "$WW_FILES" ]]; then
        WW_COUNT=$(echo "$WW_FILES" | wc -l)
        info "Found $WW_COUNT world-writable file(s). Removing world-write bit..."
        echo "$WW_FILES" | while read -r file; do
            chmod o-w "$file"
            info "  Fixed: $file"
        done
        success "World-writable files fixed."
    else
        success "No world-writable files found."
    fi

    info "Checking home directory permissions..."
    for DIR in /home/*/; do
        if [[ -d "$DIR" ]]; then
            PERMS=$(stat -c '%a' "$DIR")
            if [[ "$PERMS" != "700" && "$PERMS" != "750" ]]; then
                chmod 750 "$DIR"
                info "  Fixed: $DIR (was $PERMS, now 750)"
            fi
        fi
    done

    success "File permissions audit complete."
    track "File permissions audit" "applied"
else
    warn "Skipped file permissions audit."
    track "File permissions audit" "skipped"
fi

# =============================================================================
#  SUMMARY
# =============================================================================
separator
echo -e "${GREEN}  HARDENING COMPLETE${NC}"
separator

if [[ ${#APPLIED[@]} -gt 0 ]]; then
    echo -e "  ${GREEN}Applied:${NC}"
    for item in "${APPLIED[@]}"; do
        echo -e "    ✔  $item"
    done
fi

if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${YELLOW}Skipped:${NC}"
    for item in "${SKIPPED[@]}"; do
        echo -e "    ‒  $item"
    done
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${RED}Warnings:${NC}"
    for item in "${WARNINGS[@]}"; do
        echo -e "    ⚠  $item"
    done
fi

separator
echo -e "  ${CYAN}Next steps:${NC}"
echo -e "    1. Open any additional ports you need:  ${YELLOW}sudo ufw allow <port>/<tcp|udp>${NC}"
echo -e "    2. Reboot to apply all changes:  ${YELLOW}sudo reboot${NC}"
echo -e "    3. Verify hardening (optional):  ${YELLOW}sudo bash verify.sh${NC}"
separator
