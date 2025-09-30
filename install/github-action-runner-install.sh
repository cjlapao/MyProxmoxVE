#!/usr/bin/env bash

# Copyright (c) 2021-2025 carlos lapao
# Author: carlos lapao
# Co-Author: carlos lapao
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/cockpit-project/cockpit

set -euo pipefail

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Empty"
msg_ok "Installed Empty"

motd_ssh
customize

USER_NAME="${USER_NAME:-ghactions}"
FULL_NAME="${FULL_NAME:-GitHub Actions Runner}"
MAKE_ADMIN="${MAKE_ADMIN:-false}"          # "true" to give sudo/admin
RUNNER_DIR="${RUNNER_DIR:-actions-runner}" # under the user's HOME
PINNED_FALLBACK_VER="${PINNED_FALLBACK_VER:-2.321.0}"

require_root() { [[ $EUID -eq 0 ]] || { echo "Run with sudo/root."; exit 1; }; }
prompt() {
  local label="$1" var="$2" secret="${3:-false}" def="${4:-}"
  local p="$label"; [[ -n "$def" ]] && p="$p [$def]"; p="$p: "
  local val; if [[ "$secret" == "true" ]]; then read -r -s -p "$p" val; echo; else read -r -p "$p" val; fi
  [[ -z "$val" && -n "$def" ]] && val="$def"
  [[ -n "$val" ]] || { echo "Value required." >&2; exit 1; }
  printf -v "$var" "%s" "$val"
}
detect_os_arch() {
  local k="$(uname -s)" m="$(uname -m)" os arch
  case "$k" in Darwin) os="osx" ;; Linux) os="linux" ;; *) echo "Unsupported OS: $k"; exit 1 ;; esac
  case "$m" in arm64|aarch64) arch="arm64" ;; x86_64) arch="x64" ;; *) echo "Unsupported arch: $m"; exit 1 ;; esac
  echo "$os" "$arch"
}
latest_runner_version() {
  local tag
  tag="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest \
        | grep -m1 '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')" || true
  [[ -z "$tag" ]] && tag="$PINNED_FALLBACK_VER"
  echo "$tag"
}
user_exists() { id "$1" &>/dev/null; }
ensure_user_macos() {
  local u="$1" full="$2" admin="$3"
  if ! user_exists "$u"; then
    local pass; pass="$(/usr/bin/openssl rand -base64 24)"
    /usr/sbin/sysadminctl -addUser "$u" -fullName "$full" -password "$pass" -home "/Users/$u" -shell "/bin/zsh" $( [[ "$admin" == "true" ]] && echo -n "-admin" )
    /usr/sbin/createhomedir -c -u "$u" >/dev/null || true
    echo "Created user $u (macOS). Temp password: $pass"
  else
    echo "User $u already exists (macOS)."
  fi
  chown -R "$u":staff "/Users/$u"; chmod 700 "/Users/$u"
  /usr/sbin/DevToolsSecurity -enable || true
}
ensure_user_linux() {
  local u="$1" admin="$2"
  if ! user_exists "$u"; then
    /usr/sbin/useradd -m -s /bin/bash "$u"
    echo "Created user $u (Linux)."
  else
    echo "User $u already exists (Linux)."
  fi
  if [[ "$admin" == "true" ]]; then
    if getent group sudo >/dev/null; then /usr/sbin/usermod -aG sudo "$u"
    elif getent group wheel >/dev/null; then /usr/sbin/usermod -aG wheel "$u"; fi
  fi
  if command -v apt-get >/dev/null 2>&1; then apt-get update -y && apt-get install -y curl tar ca-certificates; fi
}
install_runner_line_by_line() {
  local os="$1" arch="$2" u="$3" url="$4" token="$5" labels="$6"
  local ver; ver="$(latest_runner_version)"
  local file="actions-runner-${os}-${arch}-${ver}.tar.gz"
  local dl="https://github.com/actions/runner/releases/download/v${ver}/${file}"
  local home; [[ "$os" == "osx" ]] && home="/Users/$u" || home="/home/$u"
  local user_script="$home/${RUNNER_DIR}/_install_runner_user.sh"

  echo "Preparing per-user installer at $user_script"
  # Create directory first (as root, then chown)
  mkdir -p "$home/${RUNNER_DIR}"
  chown -R "$u":"$( [[ "$os" == "osx" ]] && echo staff || echo "$u" )" "$home/${RUNNER_DIR}"

  # Write a SMALL script that runs line-by-line as the user
  cat > "$user_script" <<EOF
#!/usr/bin/env bash
set -euxo pipefail
cd "\$HOME"
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

echo "Downloading: $dl"
curl -fL --retry 3 --retry-delay 2 -o runner.tgz "$dl"

echo "Extracting…"
tar -xzf runner.tgz

echo "Runner files:"
ls -la

NAME="\$(hostname)-$u-\$(date +%s)"
echo "Configuring runner: \$NAME"
./config.sh --unattended \
  --url "$url" \
  --token "$token" \
  --name "\$NAME" \
  --labels "$labels" \
  --work "_work"

echo "Configured runner \$NAME"
EOF

  chown "$u":"$( [[ "$os" == "osx" ]] && echo staff || echo "$u" )" "$user_script"
  chmod +x "$user_script"

  echo "Executing installer as $u (this is truly line-by-line inside a file)…"
  # Use a login shell so HOME is correct
  sudo -iu "$u" bash "$user_script"

  # Install service
  if [[ "$os" == "osx" ]]; then
    sudo -iu "$u" bash -lc "cd ~/${RUNNER_DIR} && ./svc.sh install && ./svc.sh start"
    echo "LaunchAgent installed. Keep user '$u' logged in."
  else
    ( cd "$home/${RUNNER_DIR}" && ./svc.sh install "$u" && ./svc.sh start )
    systemctl status "actions.runner."*".service" --no-pager || true
    echo "systemd service installed for '$u'."
  fi

  echo "All set. Runner should now appear under Settings → Actions → Runners."
}

main() {
  require_root
  read -r OS ARCH < <(detect_os_arch)
  echo "Detected platform: $OS/$ARCH"

  local gh_url gh_token labels default_labels="self-hosted,$([[ "$OS" == "osx" ]] && echo macos || echo linux)"
  prompt "GitHub URL (repo OR org) e.g. https://github.com/owner/repo OR https://github.com/your-org" gh_url
  prompt "Registration token (from Settings → Actions → Runners → New runner)" gh_token true
  prompt "Runner labels (comma-separated)" labels false "$default_labels"

  if [[ "$OS" == "osx" ]]; then
    ensure_user_macos "$USER_NAME" "$FULL_NAME" "$MAKE_ADMIN"
  else
    ensure_user_linux "$USER_NAME" "$MAKE_ADMIN"
  fi

  install_runner_line_by_line "$OS" "$ARCH" "$USER_NAME" "$gh_url" "$gh_token" "$labels"

  echo "Done ✅"
}

main "$@"


msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
