#!/usr/bin/env bash
# =============================================================================
#  Ubuntu Server Hardening — Verification Script
#  Version: 1.0.0
# =============================================================================
#
#  Read-only checks for all 15 hardening measures.
#  Makes no changes to the system.
#
#  Usage:
#    sudo bash verify.sh
#
# =============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
#  Colors and counters
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

pass() { echo -e "  ${GREEN}✔ PASS${NC}  $1"; ((PASS_COUNT++)); }
fail() { echo -e "  ${RED}✘ FAIL${NC}  $1"; ((FAIL_COUNT++)); }
warn() { echo -e "  ${YELLOW}⚠ WARN${NC}  $1"; ((WARN_COUNT++)); }
header() { echo ""; echo -e "${CYAN}[$1]${NC} $2"; }

# ---------------------------------------------------------------------------
#  Pre-flight
# ---------------------------------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}This script must be run as root. Use: sudo bash verify.sh${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Hardening Verification Report${NC}"
echo -e "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "  Host: $(hostname)"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# =============================================================================
#  1. System packages
# =============================================================================
header "1" "System packages"

UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -c 'upgradable' || true)
if [[ "$UPGRADABLE" -le 1 ]]; then
    pass "System is up to date"
else
    warn "$(( UPGRADABLE - 1 )) package(s) can be upgraded"
fi

# =============================================================================
#  2. Essential tools
# =============================================================================
header "2" "Essential tools"

for TOOL in htop ncdu curl wget dig tmux lsof jq rsync zip unzip nano micro tree git ufw; do
    if command -v "$TOOL" &>/dev/null; then
        pass "$TOOL installed"
    else
        fail "$TOOL not found"
    fi
done

# =============================================================================
#  3. fail2ban
# =============================================================================
header "3" "fail2ban"

if systemctl is-active --quiet fail2ban 2>/dev/null; then
    pass "fail2ban is running"
else
    fail "fail2ban is not running"
fi

if [[ -f /etc/fail2ban/jail.local ]]; then
    pass "jail.local exists"
    if grep -q 'maxretry = 3' /etc/fail2ban/jail.local; then
        pass "SSH jail set to 3 retries"
    else
        warn "SSH jail maxretry is not 3"
    fi
else
    fail "jail.local not found"
fi

# =============================================================================
#  4. IPv6
# =============================================================================
header "4" "IPv6"

IPV6_ALL=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
if [[ "$IPV6_ALL" == "1" ]]; then
    pass "IPv6 disabled"
else
    fail "IPv6 is still enabled"
fi

# =============================================================================
#  5. Automatic security updates
# =============================================================================
header "5" "Automatic security updates"

if dpkg -l unattended-upgrades &>/dev/null; then
    pass "unattended-upgrades installed"
else
    fail "unattended-upgrades not installed"
fi

if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
    if grep -q 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades; then
        pass "Auto-upgrades enabled"
    else
        fail "Auto-upgrades not enabled in config"
    fi
else
    fail "20auto-upgrades config not found"
fi

# =============================================================================
#  6. Kernel/network hardening
# =============================================================================
header "6" "Kernel/network hardening"

declare -A SYSCTL_CHECKS=(
    ["net.ipv4.conf.all.rp_filter"]="1"
    ["net.ipv4.conf.all.accept_source_route"]="0"
    ["net.ipv4.icmp_echo_ignore_broadcasts"]="1"
    ["net.ipv4.conf.all.accept_redirects"]="0"
    ["net.ipv4.conf.all.send_redirects"]="0"
    ["net.ipv4.tcp_syncookies"]="1"
    ["net.ipv4.conf.all.log_martians"]="1"
    ["net.ipv4.ip_forward"]="0"
    ["kernel.randomize_va_space"]="2"
)

for KEY in "${!SYSCTL_CHECKS[@]}"; do
    EXPECTED="${SYSCTL_CHECKS[$KEY]}"
    ACTUAL=$(sysctl -n "$KEY" 2>/dev/null)
    if [[ "$ACTUAL" == "$EXPECTED" ]]; then
        pass "$KEY = $EXPECTED"
    else
        fail "$KEY = $ACTUAL (expected $EXPECTED)"
    fi
done

# =============================================================================
#  7. Shared memory
# =============================================================================
header "7" "Shared memory"

if grep -q '/run/shm.*noexec' /etc/fstab 2>/dev/null; then
    pass "/run/shm hardened in fstab"
else
    fail "/run/shm not hardened in fstab"
fi

# =============================================================================
#  8. Login banner
# =============================================================================
header "8" "Login banner"

if [[ -f /etc/issue.net ]] && grep -q 'Unauthorized' /etc/issue.net; then
    pass "Warning banner configured"
else
    fail "Warning banner not found"
fi

if grep -q '^Banner /etc/issue.net' /etc/ssh/sshd_config 2>/dev/null; then
    pass "Banner wired into sshd_config"
else
    fail "Banner not set in sshd_config"
fi

# =============================================================================
#  9. Timezone & locale
# =============================================================================
header "9" "Timezone & locale"

TZ=$(timedatectl show --property=Timezone --value 2>/dev/null)
if [[ "$TZ" == "UTC" ]]; then
    pass "Timezone is UTC"
else
    fail "Timezone is $TZ (expected UTC)"
fi

if timedatectl show | grep -q 'NTP=yes' 2>/dev/null; then
    pass "NTP is active"
else
    fail "NTP is not active"
fi

LANG_SET=$(locale 2>/dev/null | grep '^LANG=' | cut -d= -f2)
if [[ "$LANG_SET" == "en_US.UTF-8" ]]; then
    pass "Locale is en_US.UTF-8"
else
    warn "Locale is $LANG_SET (expected en_US.UTF-8)"
fi

# =============================================================================
#  10. Firewall
# =============================================================================
header "10" "Firewall (UFW)"

if ufw status | grep -q 'Status: active' 2>/dev/null; then
    pass "UFW is active"
else
    fail "UFW is not active"
fi

if ufw status | grep -q '22/tcp.*ALLOW' 2>/dev/null; then
    pass "SSH (22/tcp) allowed"
else
    fail "SSH not allowed in UFW"
fi

UFW_DEFAULT=$(ufw status verbose 2>/dev/null | grep 'Default:' || true)
if echo "$UFW_DEFAULT" | grep -q 'deny (incoming)'; then
    pass "Default incoming: deny"
else
    fail "Default incoming is not deny"
fi

# =============================================================================
#  11. SSH hardening
# =============================================================================
header "11" "SSH hardening"

SSHD_DROP_IN="/etc/ssh/sshd_config.d/01-hardening.conf"

if [[ -f "$SSHD_DROP_IN" ]]; then
    pass "SSH hardening drop-in exists"

    declare -A SSH_CHECKS=(
        ["PermitRootLogin"]="no"
        ["PasswordAuthentication"]="no"
        ["PermitEmptyPasswords"]="no"
        ["MaxAuthTries"]="3"
        ["X11Forwarding"]="no"
    )

    for KEY in "${!SSH_CHECKS[@]}"; do
        EXPECTED="${SSH_CHECKS[$KEY]}"
        ACTUAL=$(grep "^${KEY}" "$SSHD_DROP_IN" 2>/dev/null | awk '{print $2}')
        if [[ "$ACTUAL" == "$EXPECTED" ]]; then
            pass "$KEY = $EXPECTED"
        else
            fail "$KEY = $ACTUAL (expected $EXPECTED)"
        fi
    done

    if grep -q '^AllowUsers' "$SSHD_DROP_IN"; then
        ALLOWED=$(grep '^AllowUsers' "$SSHD_DROP_IN" | cut -d' ' -f2-)
        pass "AllowUsers set to: $ALLOWED"
    else
        fail "AllowUsers not set"
    fi
else
    fail "SSH hardening drop-in not found"
fi

# Check for conflicting cloud-init drop-ins.
if [[ -f /etc/ssh/sshd_config.d/50-cloud-init.conf ]]; then
    warn "50-cloud-init.conf still present (may conflict)"
else
    pass "No conflicting cloud-init SSH config"
fi

# =============================================================================
#  12. Unused services
# =============================================================================
header "12" "Unused services"

for SERVICE in snapd avahi-daemon cups; do
    if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
        fail "$SERVICE is still running"
    elif dpkg -l "$SERVICE" &>/dev/null 2>&1; then
        warn "$SERVICE is installed but not running"
    else
        pass "$SERVICE removed"
    fi
done

# =============================================================================
#  13. su restriction
# =============================================================================
header "13" "su restriction"

if grep -qE '^auth\s+required\s+pam_wheel.so' /etc/pam.d/su 2>/dev/null; then
    pass "su restricted to sudo group"
else
    fail "su is not restricted"
fi

# =============================================================================
#  14. Core dumps
# =============================================================================
header "14" "Core dumps"

SUID_DUMPABLE=$(sysctl -n fs.suid_dumpable 2>/dev/null)
if [[ "$SUID_DUMPABLE" == "0" ]]; then
    pass "suid_dumpable = 0"
else
    fail "suid_dumpable = $SUID_DUMPABLE (expected 0)"
fi

if [[ -f /etc/security/limits.d/99-no-core-dumps.conf ]]; then
    pass "Core dump limits configured"
else
    fail "Core dump limits not found"
fi

# =============================================================================
#  15. File permissions
# =============================================================================
header "15" "File permissions"

WW_COUNT=$(find / -xdev -type f -perm -0002 \
    -not -path '/proc/*' \
    -not -path '/sys/*' \
    -not -path '/dev/*' \
    -not -path '/run/*' \
    -not -path '/tmp/*' \
    2>/dev/null | wc -l || true)

if [[ "$WW_COUNT" -eq 0 ]]; then
    pass "No world-writable files found"
else
    fail "$WW_COUNT world-writable file(s) found"
fi

HOME_ISSUES=0
for DIR in /home/*/; do
    if [[ -d "$DIR" ]]; then
        PERMS=$(stat -c '%a' "$DIR")
        if [[ "$PERMS" != "700" && "$PERMS" != "750" ]]; then
            fail "$DIR has permissions $PERMS (expected 700 or 750)"
            ((HOME_ISSUES++))
        fi
    fi
done
if [[ "$HOME_ISSUES" -eq 0 ]]; then
    pass "Home directory permissions are correct"
fi

# =============================================================================
#  SUMMARY
# =============================================================================
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${GREEN}Passed: $PASS_COUNT${NC}    ${RED}Failed: $FAIL_COUNT${NC}    ${YELLOW}Warnings: $WARN_COUNT${NC}"

if [[ "$FAIL_COUNT" -eq 0 ]]; then
    echo ""
    echo -e "  ${GREEN}Server is fully hardened.${NC}"
else
    echo ""
    echo -e "  ${RED}Server has $FAIL_COUNT issue(s) to address.${NC}"
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

exit "$FAIL_COUNT"
