#!/usr/bin/env bash
set -Eeuo pipefail

trap 'printf "setup-wsl.sh failed at line %s\n" "$LINENO" >&2' ERR

linux_user="imps"
git_name="Ubuntu Imp"
git_email="ubuntu-imps@localhost"
tools_csv=""

usage() {
  cat <<'EOF'
Usage: setup-wsl.sh [options]

Options:
  --user NAME        Linux user to create (default: imps)
  --git-name NAME    Git author name (default: Ubuntu Imp)
  --git-email EMAIL  Git author email (default: ubuntu-imps@localhost)
  --tools LIST       Comma-separated optional tools: devin,gh,glab,gt,zcode
                     Use "all" for every optional tool (default: none)
  -h, --help         Show this help

Run as root inside the dedicated WSL distribution. The script does not create,
read, or transmit GitHub tokens, SSH private keys, or other credentials.
EOF
}

while (($#)); do
  case "$1" in
    --user)
      linux_user="${2:?missing value for --user}"
      shift 2
      ;;
    --git-name)
      git_name="${2:?missing value for --git-name}"
      shift 2
      ;;
    --git-email)
      git_email="${2:?missing value for --git-email}"
      shift 2
      ;;
    --tools)
      tools_csv="${2-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo 'Run this script as root.' >&2
  exit 1
fi

declare -a selected_tools=()
if [[ -n $tools_csv ]]; then
  IFS=',' read -r -a selected_tools <<< "$tools_csv"
fi
if [[ " ${selected_tools[*]} " == *" all "* ]]; then
  selected_tools=(devin gh glab gt zcode)
fi

for tool in "${selected_tools[@]}"; do
  case "$tool" in
    devin|gh|glab|gt|zcode) ;;
    '') ;;
    *)
      printf 'Unknown optional tool: %s\n' "$tool" >&2
      exit 2
      ;;
  esac
done

has_tool() {
  local wanted="$1" item
  for item in "${selected_tools[@]}"; do
    [[ $item == "$wanted" ]] && return 0
  done
  return 1
}

if [[ -t 1 ]]; then
  c_cyan=$'\033[36m'
  c_green=$'\033[32m'
  c_reset=$'\033[0m'
else
  c_cyan=''
  c_green=''
  c_reset=''
fi

step_current=0
step_total=$((5 + ${#selected_tools[@]}))
step() {
  step_current=$((step_current + 1))
  printf '\n%s[%d/%d] %s%s\n' "$c_cyan" "$step_current" "$step_total" "$1" "$c_reset"
}

as_user() {
  runuser -u "$linux_user" -- env \
    HOME="$user_home" \
    PATH="$user_home/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    "$@"
}

install_gh() {
  local key=/etc/apt/keyrings/githubcli-archive-keyring.gpg
  install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o "$key"
  echo '6084d5d7bd8e288441e0e94fc6275570895da18e6751f70f057485dc2d1a811b  /etc/apt/keyrings/githubcli-archive-keyring.gpg' | sha256sum --check --status
  chmod 0644 "$key"
  printf 'deb [arch=%s signed-by=%s] https://cli.github.com/packages stable main\n' \
    "$(dpkg --print-architecture)" "$key" > /etc/apt/sources.list.d/github-cli.list
  apt-get update
  apt-get install -y --no-install-recommends gh
}

install_glab() {
  local machine glab_arch release_json version asset_name asset_url sums_url tmpdir
  machine="$(dpkg --print-architecture)"
  case "$machine" in
    amd64) glab_arch=amd64 ;;
    arm64) glab_arch=arm64 ;;
    *) printf 'glab is not supported by this script on architecture %s\n' "$machine" >&2; return 1 ;;
  esac

  tmpdir="$(mktemp -d)"
  release_json="$tmpdir/release.json"
  curl -fsSL 'https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases/permalink/latest' -o "$release_json"
  version="$(jq -r '.tag_name | sub("^v"; "")' "$release_json")"
  asset_name="glab_${version}_linux_${glab_arch}.deb"
  asset_url="$(jq -r --arg n "$asset_name" '.assets.links[] | select(.name == $n) | .direct_asset_url' "$release_json")"
  sums_url="$(jq -r '.assets.links[] | select(.name == "checksums.txt") | .direct_asset_url' "$release_json")"
  [[ -n $asset_url && $asset_url != null && -n $sums_url && $sums_url != null ]]
  curl -fsSL "$asset_url" -o "$tmpdir/$asset_name"
  curl -fsSL "$sums_url" -o "$tmpdir/checksums.txt"
  (cd "$tmpdir" && grep "  $asset_name\$" checksums.txt | sha256sum --check --status)
  apt-get install -y "$tmpdir/$asset_name"
  rm -rf -- "$tmpdir"
}

install_gt() {
  as_user sh -c 'curl -fsSL https://gitea.com/gitea/cli/raw/branch/main/scripts/install.sh | GITEA_CLI_INSTALL_DIR="$HOME/.local/bin" sh'
}

install_devin() {
  as_user sh -c 'curl -fsSL https://cli.devin.ai/install.sh | bash'
}

install_zcode() {
  local share_dir source_dir node_version pnpm_version machine node_arch node_file node_base toolchain tmpdir
  share_dir="$user_home/.local/share/zcode-cli"
  source_dir="$share_dir/source"
  toolchain="$share_dir/toolchain"

  if [[ -x $user_home/.local/bin/zcode ]]; then
    echo 'zcode is already installed; leaving the existing build unchanged.'
    return 0
  fi

  install -d -o "$linux_user" -g "$linux_user" -m 0700 "$share_dir" "$user_home/.local/bin"
  as_user git clone --depth 1 https://github.com/zai-org/ZCode.git "$source_dir"
  node_version="$(awk -F'"' '/^[[:space:]]*node[[:space:]]*=/ {print $2; exit}' "$source_dir/mise.toml")"
  pnpm_version="$(awk -F'"' '/^[[:space:]]*pnpm[[:space:]]*=/ {print $2; exit}' "$source_dir/mise.toml")"
  [[ -n $node_version && -n $pnpm_version ]]

  machine="$(uname -m)"
  case "$machine" in
    x86_64) node_arch=x64 ;;
    aarch64|arm64) node_arch=arm64 ;;
    *) printf 'ZCode source build is not supported on architecture %s\n' "$machine" >&2; return 1 ;;
  esac

  node_file="node-v${node_version}-linux-${node_arch}.tar.xz"
  node_base="https://nodejs.org/dist/v${node_version}"
  tmpdir="$(mktemp -d)"
  curl -fsSL "$node_base/$node_file" -o "$tmpdir/$node_file"
  curl -fsSL "$node_base/SHASUMS256.txt" -o "$tmpdir/SHASUMS256.txt"
  (cd "$tmpdir" && grep "  $node_file\$" SHASUMS256.txt | sha256sum --check --status)
  install -d -o "$linux_user" -g "$linux_user" -m 0700 "$toolchain"
  tar -xJf "$tmpdir/$node_file" --strip-components=1 -C "$toolchain"
  chown -R "$linux_user:$linux_user" "$toolchain" "$source_dir"
  rm -rf -- "$tmpdir"

  as_user env PATH="$toolchain/bin:/usr/local/bin:/usr/bin:/bin" \
    "$toolchain/bin/corepack" prepare "pnpm@$pnpm_version" --activate
  as_user env PATH="$toolchain/bin:/usr/local/bin:/usr/bin:/bin" \
    pnpm --dir "$source_dir" install --frozen-lockfile
  as_user env PATH="$toolchain/bin:/usr/local/bin:/usr/bin:/bin" \
    pnpm --dir "$source_dir" --filter '@zcode/cli...' build

  cat > "$user_home/.local/bin/zcode" <<EOF
#!/bin/sh
exec "$toolchain/bin/node" "$source_dir/apps/zcode-cli/packages/cli/dist/zcode.cjs" "\$@"
EOF
  chown "$linux_user:$linux_user" "$user_home/.local/bin/zcode"
  chmod 0700 "$user_home/.local/bin/zcode"
}

if [[ ! $linux_user =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  echo 'Invalid Linux user name.' >&2
  exit 2
fi

if [[ $git_name == *$'\n'* || $git_name == *$'\r'* ||
      $git_email == *$'\n'* || $git_email == *$'\r'* ]]; then
  echo 'Git identity values must not contain newlines.' >&2
  exit 2
fi

if ! grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease /proc/version 2>/dev/null; then
  echo 'This script is intended for a dedicated WSL distribution.' >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
step 'Updating Ubuntu and installing the base developer toolchain'
apt-get update
apt-get upgrade -y
apt-get install -y --no-install-recommends \
  bash-completion \
  build-essential \
  ca-certificates \
  curl \
  git \
  gnupg \
  jq \
  openssh-client \
  ripgrep \
  tar \
  unzip \
  wget \
  xz-utils \
  zip

if ! id "$linux_user" >/dev/null 2>&1; then
  step "Creating the locked-down Linux user: $linux_user"
  adduser --disabled-password --gecos '' --shell /bin/bash "$linux_user"
else
  step "Reusing the existing Linux user: $linux_user"
fi

# The agent account deliberately has no sudo access and no usable password.
if getent group sudo >/dev/null 2>&1; then
  gpasswd --delete "$linux_user" sudo >/dev/null 2>&1 || true
fi
passwd --lock "$linux_user" >/dev/null

user_home="$(getent passwd "$linux_user" | cut -d: -f6)"
if [[ -z $user_home || $user_home == / ]]; then
  echo 'Could not determine a safe user home directory.' >&2
  exit 1
fi

install -d -o "$linux_user" -g "$linux_user" -m 0700 \
  "$user_home" \
  "$user_home/.ssh" \
  "$user_home/work" \
  "$user_home/.config/git/hooks"

step 'Disabling Windows drive mounts and Windows executable interoperability'
cat > /etc/wsl.conf <<EOF
[automount]
enabled=false
mountFsTab=false

[interop]
enabled=false
appendWindowsPath=false

[user]
default=$linux_user
EOF
chmod 0644 /etc/wsl.conf

cat > "$user_home/.ssh/config" <<'EOF'
Host *
    AddKeysToAgent no
    ForwardAgent no
    ForwardX11 no
    HashKnownHosts yes
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
EOF
chown "$linux_user:$linux_user" "$user_home/.ssh/config"
chmod 0600 "$user_home/.ssh/config"

step 'Configuring Git identity and protected-branch guardrails'
cat > "$user_home/.config/git/hooks/pre-push" <<'EOF'
#!/bin/sh
# Local guardrail only. GitHub branch protection is the authoritative control.
while read -r _local_ref _local_sha remote_ref _remote_sha; do
  case "$remote_ref" in
    refs/heads/main|refs/heads/master)
      echo 'Direct pushes to main/master are blocked for Ubuntu-Imps.' >&2
      echo 'Push a feature branch and open a pull request instead.' >&2
      exit 1
      ;;
  esac
done
EOF
chown "$linux_user:$linux_user" "$user_home/.config/git/hooks/pre-push"
chmod 0700 "$user_home/.config/git/hooks/pre-push"

runuser -u "$linux_user" -- git config --global user.name "$git_name"
runuser -u "$linux_user" -- git config --global user.email "$git_email"
runuser -u "$linux_user" -- git config --global init.defaultBranch main
runuser -u "$linux_user" -- git config --global push.default current
runuser -u "$linux_user" -- git config --global push.autoSetupRemote true
runuser -u "$linux_user" -- git config --global fetch.prune true
runuser -u "$linux_user" -- git config --global credential.helper ''
runuser -u "$linux_user" -- git config --global core.hooksPath "$user_home/.config/git/hooks"

for tool in "${selected_tools[@]}"; do
  step "Installing optional tool: $tool"
  case "$tool" in
    devin) install_devin ;;
    gh) install_gh ;;
    glab) install_glab ;;
    gt) install_gt ;;
    zcode) install_zcode ;;
  esac
done

cat > /etc/profile.d/99-ubuntu-imps.sh <<'EOF'
# Private-by-default files for interactive shells.
umask 077
export HISTCONTROL=ignoreboth:erasedups
EOF
chmod 0644 /etc/profile.d/99-ubuntu-imps.sh

chmod 0700 "$user_home"
chown -R "$linux_user:$linux_user" "$user_home"
apt-get clean

step 'Final verification'
for tool in "${selected_tools[@]}"; do
  case "$tool" in
    devin) command_path="$user_home/.local/bin/devin" ;;
    zcode) command_path="$user_home/.local/bin/zcode" ;;
    gt) command_path="$user_home/.local/bin/gt" ;;
    gh|glab) command_path="$(command -v "$tool" || true)" ;;
  esac
  if [[ ! -x $command_path ]]; then
    printf 'Expected command was not installed: %s\n' "$tool" >&2
    exit 1
  fi
done

cat <<EOF

Ubuntu-Imps hardening applied.

After Windows restarts this distribution:
  * Windows drives will not be mounted automatically.
  * Windows executables and Windows PATH injection will be disabled.
  * $linux_user will be the default, password-locked, non-sudo user.
  * Direct pushes to main/master will be blocked by a local Git hook.

No GitHub or agent credentials were created or copied.
Authenticate interactively as $linux_user only after reviewing access scopes.
Enforce pull requests and branch protection on GitHub; local hooks are bypassable.
WSL is not a strong sandbox or a substitute for a separate VM.
EOF
