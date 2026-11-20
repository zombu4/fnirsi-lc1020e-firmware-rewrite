#!/bin/sh
# install_sudo_rule.sh - one-time setup on macOS: a root-owned copy of tools/iap_raw.py (raw read /
# write of the LC1020E update drive only) and a sudoers rule that lets only that copy run as root
# without a password. The install procedure itself lives in non-root scripts (tools/iap_write.py)
# that call it, so this does not need to be run again when they change.
# It also removes a copy of an earlier helper, iap_write_lc1020e.py, if present.
# Usage: sudo sh tools/install_sudo_rule.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
user=${SUDO_USER:?run through sudo}
install -o root -g wheel -m 755 "$here/iap_raw.py" /usr/local/libexec/iap_raw_lc1020e.py
tmp=$(mktemp)
echo "$user ALL=(root) NOPASSWD: /opt/homebrew/bin/python3 -I /usr/local/libexec/iap_raw_lc1020e.py *" > "$tmp"
visudo -cf "$tmp"
install -o root -g wheel -m 440 "$tmp" /etc/sudoers.d/flash_lc1020e
rm -f "$tmp" /usr/local/libexec/iap_write_lc1020e.py
echo "installed /usr/local/libexec/iap_raw_lc1020e.py and /etc/sudoers.d/flash_lc1020e"
