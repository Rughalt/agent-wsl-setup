#!/usr/bin/env bash
set -Eeuo pipefail

trap 'printf "setup-wsl.sh failed at line %s\n" "$LINENO" >&2' ERR

linux_user="imps"
git_name="Ubuntu Imp"
git_email="ubuntu-imps@localhost"
tools_csv=""
post_restart=0

usage() {
  cat <<'EOF'
Usage: setup-wsl.sh [options]

Options:
  --user NAME        Linux user to create (default: imps)
  --git-name NAME    Git author name (default: Ubuntu Imp)
  --git-email EMAIL  Git author email (default: ubuntu-imps@localhost)
  --tools LIST       Optional tools: devin,figcraft,gh,glab,go,gt,lerd,node,shiori,uv,zcode
                     Use "all" for every optional tool (default: none)
  --post-restart     Complete tools that require systemd after a WSL restart
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
    --post-restart)
      post_restart=1
      shift
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
  selected_tools=(devin figcraft gh glab go gt lerd node uv zcode shiori)
fi

for tool in "${selected_tools[@]}"; do
  case "$tool" in
    devin|figcraft|gh|glab|go|gt|lerd|node|shiori|uv|zcode) ;;
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
tool_step_count=0
for tool in "${selected_tools[@]}"; do
  [[ $tool == lerd ]] || tool_step_count=$((tool_step_count + 1))
done
step_total=$((6 + tool_step_count))
step() {
  step_current=$((step_current + 1))
  printf '\n%s[%d/%d] %s%s\n' "$c_cyan" "$step_current" "$step_total" "$1" "$c_reset"
}

as_user() {
  local user_id
  user_id="$(id -u "$linux_user")"
  runuser -u "$linux_user" -- env \
    HOME="$user_home" \
    PATH="$user_home/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    XDG_RUNTIME_DIR="/run/user/$user_id" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$user_id/bus" \
    "$@"
}

as_user_in() {
  local directory="$1"
  shift
  as_user sh -c 'cd "$1" && shift && exec "$@"' sh "$directory" "$@"
}

checkpoint_done() {
  [[ -f "$state_dir/$1" ]]
}

checkpoint_mark() {
  local checkpoint="$1" tmp
  if [[ ! $checkpoint =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf 'Unsafe checkpoint name: %s\n' "$checkpoint" >&2
    return 1
  fi
  tmp="$(mktemp "$state_dir/.checkpoint.XXXXXX")"
  printf 'completed_at=%s\n' "$(date --iso-8601=seconds)" > "$tmp"
  chmod 0600 "$tmp"
  mv -f -- "$tmp" "$state_dir/$checkpoint"
}

shiori_is_installed() {
  local checkout state_file skill_name target source found
  checkout="$user_home/.local/share/shiori/shiori-brain"
  state_file="$user_home/.local/state/shiori/managed-skills"
  [[ -d "$checkout/.git" && -s $state_file ]] || return 1
  found=0
  while IFS= read -r skill_name; do
    [[ -n $skill_name ]] || continue
    found=1
    target="$user_home/.agents/skills/$skill_name"
    source="$checkout/skills/$skill_name"
    [[ -L $target && $(readlink "$target") == "$source" ]] || return 1
  done < "$state_file"
  [[ $found -eq 1 ]]
}

tool_is_installed() {
  local tool="$1"
  case "$tool" in
    devin) [[ -x "$user_home/.local/bin/devin" ]] ;;
    figcraft)
      [[ -x "$user_home/.local/bin/figcraft-cli" ]] &&
        as_user "$user_home/.local/bin/figcraft-cli" --version >/dev/null 2>&1
      ;;
    gh|glab) command -v "$tool" >/dev/null 2>&1 ;;
    go) command -v go >/dev/null 2>&1 ;;
    gt) [[ -x "$user_home/.local/bin/gt" ]] ;;
    lerd) [[ -x "$user_home/.local/bin/lerd" ]] ;;
    node) as_user bash -c '. "$HOME/.nvm/nvm.sh" 2>/dev/null && command -v node >/dev/null' ;;
    shiori) shiori_is_installed ;;
    uv) [[ -x "$user_home/.local/bin/uv" && -f "$user_home/.config/uv/uv-receipt.json" ]] ;;
    zcode) [[ -x "$user_home/.local/bin/zcode" ]] ;;
    *) return 1 ;;
  esac
}

install_node() {
  touch "$user_home/.bashrc"
  chown "$linux_user:$linux_user" "$user_home/.bashrc"
  chmod 0644 "$user_home/.bashrc"
  as_user bash -c '
    export NVM_DIR="$HOME/.nvm"
    export PROFILE="$HOME/.bashrc"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.41.0/install.sh | bash
    . "$NVM_DIR/nvm.sh"
    nvm install --lts
    nvm alias default "lts/*"
  '
}

install_go() {
  local release_json version machine go_arch filename checksum tmpdir target
  machine="$(uname -m)"
  case "$machine" in
    x86_64) go_arch=amd64 ;;
    aarch64|arm64) go_arch=arm64 ;;
    *) printf 'Go is not supported by this script on architecture %s\n' "$machine" >&2; return 1 ;;
  esac

  tmpdir="$(mktemp -d)"
  release_json="$tmpdir/releases.json"
  curl -fsSL 'https://go.dev/dl/?mode=json' -o "$release_json"
  version="$(jq -r '.[0].version' "$release_json")"
  filename="${version}.linux-${go_arch}.tar.gz"
  checksum="$(jq -r --arg n "$filename" '.[0].files[] | select(.filename == $n) | .sha256' "$release_json")"
  [[ -n $version && $version != null && -n $checksum && $checksum != null ]]
  curl -fsSL "https://go.dev/dl/$filename" -o "$tmpdir/$filename"
  echo "$checksum  $tmpdir/$filename" | sha256sum --check --status
  target="/opt/go/$version"
  if [[ ! -d $target ]]; then
    install -d -m 0755 /opt/go
    tar -xzf "$tmpdir/$filename" -C "$tmpdir"
    mv "$tmpdir/go" "$target"
  fi
  ln -sfn "$target/bin/go" /usr/local/bin/go
  ln -sfn "$target/bin/gofmt" /usr/local/bin/gofmt
  rm -rf -- "$tmpdir"
}

install_uv() {
  as_user sh -c 'curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 sh'
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
  local machine target tmpdir manifest version url checksum archive extract_dir
  local data_dir versions_dir version_dir current_link target_bin

  machine="$(uname -m)"
  case "$machine" in
    x86_64) target=x86_64-unknown-linux ;;
    aarch64|arm64) target=aarch64-unknown-linux ;;
    *) printf 'Devin is not supported by this script on architecture %s\n' "$machine" >&2; return 1 ;;
  esac

  tmpdir="$(mktemp -d)"
  manifest="$tmpdir/manifest.json"
  archive="$tmpdir/devin.tar.gz"
  extract_dir="$tmpdir/extracted"
  curl -fsSL https://static.devin.ai/cli/current/manifest.json -o "$manifest"
  version="$(jq -r '.version' "$manifest")"
  url="$(jq -r --arg target "$target" '.platforms[$target].url' "$manifest")"
  checksum="$(jq -r --arg target "$target" '.platforms[$target].sha256' "$manifest")"

  if [[ ! $version =~ ^[A-Za-z0-9._-]+$ ||
        ! $url =~ ^https://static\.devin\.ai/cli/ ||
        ! $checksum =~ ^[a-fA-F0-9]{64}$ ]]; then
    printf 'The Devin release manifest contains invalid data; refusing installation.\n' >&2
    rm -rf -- "$tmpdir"
    return 1
  fi

  curl -fsSL "$url" -o "$archive"
  printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check --status
  mkdir -p "$extract_dir"
  tar -xzf "$archive" -C "$extract_dir"
  if [[ ! -x "$extract_dir/bin/devin" ]]; then
    printf 'The verified Devin archive does not contain bin/devin.\n' >&2
    rm -rf -- "$tmpdir"
    return 1
  fi

  data_dir="$user_home/.local/share/devin/cli"
  versions_dir="$data_dir/_versions"
  version_dir="$versions_dir/$version"
  current_link="$versions_dir/current"
  target_bin="$user_home/.local/bin/devin"
  install -d -o "$linux_user" -g "$linux_user" -m 0700 "$versions_dir" "$user_home/.local/bin"
  if [[ -e $target_bin && ! -L $target_bin ]]; then
    printf '%s exists and is not a symlink; refusing to overwrite it.\n' "$target_bin" >&2
    rm -rf -- "$tmpdir"
    return 1
  fi

  rm -rf -- "$version_dir"
  mv "$extract_dir" "$version_dir"
  printf 'curl-bash\n' > "$version_dir/distribution"
  ln -sfn "$version" "$current_link"
  ln -sfn "$current_link/bin/devin" "$target_bin"
  chown -R "$linux_user:$linux_user" "$user_home/.local/share/devin" "$user_home/.local/bin"
  rm -rf -- "$tmpdir"
}

install_figcraft() {
  local machine arch tmpdir version asset base_url checksums archive checksum checksum_count
  local extract_dir relative_binary install_root target_bin

  machine="$(uname -m)"
  case "$machine" in
    x86_64) arch=x86_64 ;;
    aarch64|arm64) arch=aarch64 ;;
    *) printf 'FigCraft CLI is not available for architecture %s.\n' "$machine" >&2; return 1 ;;
  esac

  tmpdir="$(mktemp -d)"
  checksums="$tmpdir/SHA256SUMS.txt"
  base_url='https://github.com/storytold/figcraft/releases/latest/download'
  curl -fsSL --retry 4 --retry-delay 2 --retry-all-errors \
    -A 'agent-wsl-setup/1.0' "$base_url/SHA256SUMS.txt" -o "$checksums"
  asset="$(awk -v arch="$arch" '
    {
      name=$2
      sub(/^\*/, "", name)
      if (name ~ /^figcraft-[0-9]/ && name ~ ("-linux-" arch "\\.tar\\.gz$")) print name
    }
  ' "$checksums")"
  if [[ -z $asset || $(printf '%s\n' "$asset" | wc -l) -ne 1 ]]; then
    printf 'Could not identify exactly one FigCraft CLI archive for %s.\n' "$arch" >&2
    rm -rf -- "$tmpdir"
    return 1
  fi

  version="${asset#figcraft-}"
  version="${version%-linux-${arch}.tar.gz}"
  if [[ ! $version =~ ^[0-9][A-Za-z0-9._-]*$ ]]; then
    printf 'The latest FigCraft archive has an invalid version: %s\n' "$version" >&2
    rm -rf -- "$tmpdir"
    return 1
  fi

  archive="$tmpdir/$asset"
  extract_dir="$tmpdir/extracted"
  curl -fsSL --retry 4 --retry-delay 2 --retry-all-errors \
    -A 'agent-wsl-setup/1.0' "$base_url/$asset" -o "$archive"
  checksum="$(awk -v asset="$asset" '{ name=$2; sub(/^\*/, "", name); if (name == asset) print $1 }' "$checksums")"
  checksum_count="$(printf '%s\n' "$checksum" | wc -l)"
  if [[ ! $checksum =~ ^[a-fA-F0-9]{64}$ || $checksum_count -ne 1 ]]; then
    printf 'Could not find one trusted checksum for %s.\n' "$asset" >&2
    rm -rf -- "$tmpdir"
    return 1
  fi
  (cd "$tmpdir" && printf '%s  %s\n' "$checksum" "$asset" | sha256sum --check --status)

  mkdir -p "$extract_dir"
  tar -xzf "$archive" -C "$extract_dir"
  relative_binary="$(find "$extract_dir" -type f -name figcraft-cli -perm /111 -printf '%P\n' | head -n 1)"
  if [[ -z $relative_binary ]]; then
    printf 'The verified FigCraft archive does not contain figcraft-cli.\n' >&2
    rm -rf -- "$tmpdir"
    return 1
  fi

  install_root="$user_home/.local/share/figcraft-cli/$version"
  target_bin="$user_home/.local/bin/figcraft-cli"
  install -d -o "$linux_user" -g "$linux_user" -m 0700 "$(dirname "$install_root")" "$user_home/.local/bin"
  rm -rf -- "$install_root"
  mv "$extract_dir" "$install_root"
  ln -sfn "$install_root/$relative_binary" "$target_bin"
  chown -R "$linux_user:$linux_user" "$user_home/.local/share/figcraft-cli" "$target_bin"
  rm -rf -- "$tmpdir"
}

install_shiori() {
  as_user sh -c 'curl -fsSL https://raw.githubusercontent.com/Dragonshorn-Studios/shiori-brain/main/scripts/shiori-doctor.sh | sh -s -- --install opencode'
}

configure_lerd_podman_backend() {
  local backend config_dir config_file custom_networks

  backend="$(as_user_in "$user_home" podman info --format '{{.Host.NetworkBackend}}')"
  if [[ $backend == netavark ]]; then
    return 0
  fi
  if [[ $backend != cni ]]; then
    printf 'Unsupported Podman network backend: %s\n' "$backend" >&2
    return 1
  fi

  # Switching backends hides CNI network definitions from Netavark. Do it
  # automatically only while the dedicated agent distro still has no
  # containers and no user-created networks; never destroy Podman state.
  if [[ -n $(as_user_in "$user_home" podman ps -aq) ]]; then
    cat >&2 <<'EOF'
Lerd requires Podman's Netavark backend, but this user already has containers.
No Podman state was changed. Remove or migrate those containers, then re-run setup.
EOF
    return 1
  fi
  custom_networks="$(
    as_user_in "$user_home" podman network ls --format '{{.Name}}' |
      sed '/^podman$/d; /^[[:space:]]*$/d'
  )"
  if [[ -n $custom_networks ]]; then
    printf 'Lerd requires Netavark, but these CNI networks already exist:\n%s\n' \
      "$custom_networks" >&2
    echo 'No Podman state was changed. Remove or migrate them, then re-run setup.' >&2
    return 1
  fi

  config_dir='/etc/containers/containers.conf.d'
  config_file="$config_dir/90-agent-wsl-netavark.conf"
  install -d -o root -g root -m 0755 "$config_dir"
  cat > "$config_file" <<'EOF'
[network]
network_backend = "netavark"
EOF
  chmod 0644 "$config_file"

  backend="$(as_user_in "$user_home" podman info --format '{{.Host.NetworkBackend}}')"
  if [[ $backend != netavark ]]; then
    printf 'Unable to switch Podman from CNI to Netavark (still reports %s).\n' \
      "$backend" >&2
    return 1
  fi
  echo 'Podman network backend migrated safely: CNI -> Netavark.'
}

install_lerd_postrestart() {
  local user_id sudoers_file sudoers_tmp status
  user_id="$(id -u "$linux_user")"

  apt-get update
  apt-get install -y --no-install-recommends \
    dbus-user-session \
    dnsmasq-base \
    fuse-overlayfs \
    libnss3-tools \
    aardvark-dns \
    netavark \
    podman \
    slirp4netns \
    systemd-resolved \
    uidmap

  configure_lerd_podman_backend

  loginctl enable-linger "$linux_user"
  systemctl start "user@${user_id}.service"

  sudoers_file="/etc/sudoers.d/90-ubuntu-imps-lerd-bootstrap"
  sudoers_tmp="$(mktemp)"
  printf '%s ALL=(root) NOPASSWD: %s/.local/bin/lerd bootstrap --system\n' \
    "$linux_user" "$user_home" > "$sudoers_tmp"
  chmod 0440 "$sudoers_tmp"
  visudo -cf "$sudoers_tmp" >/dev/null
  install -o root -g root -m 0440 "$sudoers_tmp" "$sudoers_file"
  rm -f -- "$sudoers_tmp"

  status=0
  # Detach the vendor installer from the controlling terminal so its initial
  # install cannot open an interactive UI. Then explicitly apply the supported
  # unattended setup mode while the narrowly scoped bootstrap sudo rule exists.
  as_user_in "$user_home" setsid -f -w bash -c 'curl -fsSL https://lerd.sh/install.sh | bash' </dev/null || status=$?
  if [[ $status -eq 0 ]]; then
    as_user_in "$user_home" "$user_home/.local/bin/lerd" install --unattended || status=$?
  fi
  rm -f -- "$sudoers_file"
  [[ $status -eq 0 ]] || return "$status"
  as_user_in "$user_home" "$user_home/.local/bin/lerd" doctor
}

install_shell_experience() {
  local theme_dir theme_file bashrc motd
  theme_dir="$user_home/.config/ohmyposh"
  theme_file="$theme_dir/imp.omp.json"
  bashrc="$user_home/.bashrc"
  motd='/usr/local/bin/ubuntu-imps-motd'

  install -d -o "$linux_user" -g "$linux_user" -m 0700 \
    "$theme_dir" "$user_home/.local/bin"
  as_user sh -c 'curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"'

  cat > "$theme_file" <<'EOF'
{
  "$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json",
  "version": 4,
  "final_space": true,
  "blocks": [
    {
      "type": "prompt",
      "alignment": "left",
      "segments": [
        {
          "type": "text",
          "style": "plain",
          "foreground": "#CBA6F7",
          "template": "╭─ 😈 imp "
        },
        {
          "type": "session",
          "style": "plain",
          "foreground": "#F5C2E7",
          "template": "{{ .UserName }}@{{ .HostName }} "
        },
        {
          "type": "path",
          "style": "plain",
          "foreground": "#89B4FA",
          "options": { "style": "folder" },
          "template": "{{ .Path }} "
        },
        {
          "type": "git",
          "style": "plain",
          "foreground": "#A6E3A1",
          "template": "{{ .HEAD }}{{ if .Working.Changed }}*{{ end }} "
        }
      ]
    },
    {
      "type": "prompt",
      "alignment": "left",
      "newline": true,
      "segments": [
        {
          "type": "text",
          "style": "plain",
          "foreground": "#CBA6F7",
          "template": "╰─❯ "
        }
      ]
    }
  ]
}
EOF
  chown "$linux_user:$linux_user" "$theme_file"
  chmod 0600 "$theme_file"

  cat > "$motd" <<'EOF'
#!/bin/sh
purple='\033[38;2;203;166;247m'
pink='\033[38;2;245;194;231m'
blue='\033[38;2;137;180;250m'
dim='\033[2m'
reset='\033[0m'
printf '%b\n' "${purple}╭──────────────────────────────────────────╮${reset}"
printf '%b\n' "${purple}│${reset} ${pink}😈  Ubuntu-Imps agent workshop${reset}             ${purple}│${reset}"
printf '%b\n' "${purple}│${reset} ${blue}private by default · tools ready · be nice${reset} ${purple}│${reset}"
printf '%b\n' "${purple}╰──────────────────────────────────────────╯${reset}"
printf '%b\n' "${dim}$(id -un)@$(hostname) · $(uname -r)${reset}"
EOF
  chmod 0755 "$motd"

  touch "$bashrc"
  if ! grep -qF '# >>> Ubuntu-Imps shell >>>' "$bashrc"; then
    cat >> "$bashrc" <<'EOF'

# >>> Ubuntu-Imps shell >>>
if [[ $- == *i* ]]; then
  if [[ -z ${UBUNTU_IMPS_MOTD_SHOWN:-} ]]; then
    export UBUNTU_IMPS_MOTD_SHOWN=1
    /usr/local/bin/ubuntu-imps-motd
  fi
  if [[ -x $HOME/.local/bin/oh-my-posh ]]; then
    eval "$("$HOME/.local/bin/oh-my-posh" init bash --config "$HOME/.config/ohmyposh/imp.omp.json")"
  fi
fi
# <<< Ubuntu-Imps shell <<<
EOF
  fi
  chown "$linux_user:$linux_user" "$bashrc"
  chmod 0644 "$bashrc"

  as_user "$user_home/.local/bin/oh-my-posh" print primary --config "$theme_file" >/dev/null
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

  # A failed build has no checkpoint; discard only its managed build tree so
  # the next attempt starts from a known state.
  rm -rf -- "$source_dir" "$toolchain"
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

  as_user_in "$source_dir" env PATH="$toolchain/bin:/usr/local/bin:/usr/bin:/bin" \
    "$toolchain/bin/corepack" enable --install-directory "$toolchain/bin"
  as_user_in "$source_dir" env PATH="$toolchain/bin:/usr/local/bin:/usr/bin:/bin" \
    "$toolchain/bin/corepack" prepare "pnpm@$pnpm_version" --activate
  as_user_in "$source_dir" env PATH="$toolchain/bin:/usr/local/bin:/usr/bin:/bin" \
    "$toolchain/bin/pnpm" install --frozen-lockfile
  as_user_in "$source_dir" env PATH="$toolchain/bin:/usr/local/bin:/usr/bin:/bin" \
    "$toolchain/bin/pnpm" --filter '@zcode/cli...' build

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

state_dir='/var/lib/agent-wsl-setup/completed'
install -d -o root -g root -m 0700 "$state_dir"

if [[ $post_restart -eq 1 ]]; then
  if ! id "$linux_user" >/dev/null 2>&1; then
    echo "The user $linux_user does not exist; run the baseline phase first." >&2
    exit 1
  fi
  user_home="$(getent passwd "$linux_user" | cut -d: -f6)"
  if has_tool lerd; then
    if checkpoint_done 'tool-lerd-v1' && tool_is_installed lerd; then
      printf '\nSkipping completed Lerd installation.\n'
    else
      printf '\nCompleting Lerd installation after the systemd restart...\n'
      install_lerd_postrestart
      tool_is_installed lerd
      checkpoint_mark 'tool-lerd-v1'
    fi
  fi
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
if checkpoint_done 'base-packages-v1'; then
  step 'Skipping completed base developer toolchain installation'
else
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
    sudo \
    tar \
    unzip \
    wget \
    xz-utils \
    zip
  checkpoint_mark 'base-packages-v1'
fi

user_checkpoint="user-v1-$linux_user"
if checkpoint_done "$user_checkpoint" && id "$linux_user" >/dev/null 2>&1; then
  step "Skipping completed Linux user setup: $linux_user"
else
  if ! id "$linux_user" >/dev/null 2>&1; then
    step "Creating the locked-down Linux user: $linux_user"
    adduser --disabled-password --gecos '' --shell /bin/bash "$linux_user"
    passwd --lock "$linux_user" >/dev/null
  else
    step "Finishing setup for the existing Linux user: $linux_user"
  fi

  # The account may use sudo after the owner sets a password explicitly.
  usermod --append --groups sudo "$linux_user"
fi

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
# A previously interrupted run may have left parent directories owned by root.
# Repair the dedicated account's home before any installer runs as that user.
chown -R "$linux_user:$linux_user" "$user_home"
if ! checkpoint_done "$user_checkpoint"; then
  checkpoint_mark "$user_checkpoint"
fi

hardening_checkpoint="wsl-hardening-v1-$linux_user"
if checkpoint_done "$hardening_checkpoint" && [[ -f /etc/wsl.conf && -f "$user_home/.ssh/config" ]]; then
  step 'Skipping completed WSL and SSH hardening'
else
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

[boot]
systemd=true
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
  checkpoint_mark "$hardening_checkpoint"
fi

git_config_hash="$(printf '%s\0%s\0%s' "$linux_user" "$git_name" "$git_email" | sha256sum | cut -d' ' -f1)"
git_checkpoint="git-config-v1-$git_config_hash"
if checkpoint_done "$git_checkpoint" && [[ -x "$user_home/.config/git/hooks/pre-push" ]]; then
  step 'Skipping completed Git identity and guardrail configuration'
else
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
  checkpoint_mark "$git_checkpoint"
fi

shell_checkpoint="shell-experience-v1-$linux_user"
if checkpoint_done "$shell_checkpoint" &&
   [[ -x "$user_home/.local/bin/oh-my-posh" &&
      -f "$user_home/.config/ohmyposh/imp.omp.json" &&
      -x /usr/local/bin/ubuntu-imps-motd ]]; then
  step 'Skipping completed Ubuntu-Imps shell experience'
else
  step 'Installing the Ubuntu-Imps MOTD and Oh My Posh theme'
  install_shell_experience
  checkpoint_mark "$shell_checkpoint"
fi

for tool in "${selected_tools[@]}"; do
  [[ $tool == lerd || $tool == shiori ]] && continue
  tool_checkpoint="tool-$tool-v1"
  if checkpoint_done "$tool_checkpoint" && tool_is_installed "$tool"; then
    step "Skipping completed optional tool: $tool"
    continue
  fi
  if tool_is_installed "$tool"; then
    step "Recording already installed optional tool: $tool"
    checkpoint_mark "$tool_checkpoint"
    continue
  fi

  step "Installing optional tool: $tool"
  case "$tool" in
    devin) install_devin ;;
    figcraft) install_figcraft ;;
    gh) install_gh ;;
    glab) install_glab ;;
    go) install_go ;;
    gt) install_gt ;;
    node) install_node ;;
    uv) install_uv ;;
    zcode) install_zcode ;;
  esac
  if ! tool_is_installed "$tool"; then
    printf 'Expected command was not installed: %s\n' "$tool" >&2
    exit 1
  fi
  checkpoint_mark "$tool_checkpoint"
done

# Shiori is intentionally last: it inspects the finished agent environment and
# links the generated shared skills only after every selected CLI is ready.
if has_tool shiori; then
  tool_checkpoint='tool-shiori-v1'
  if checkpoint_done "$tool_checkpoint" && tool_is_installed shiori; then
    step 'Skipping completed Shiori Brain skill installation'
  elif tool_is_installed shiori; then
    step 'Recording already installed Shiori Brain skills'
    checkpoint_mark "$tool_checkpoint"
  else
    step 'Installing Shiori Brain shared skills'
    install_shiori
    tool_is_installed shiori
    checkpoint_mark "$tool_checkpoint"
  fi
fi

profile_checkpoint="shell-profile-v1-$linux_user"
if ! checkpoint_done "$profile_checkpoint" || [[ ! -f /etc/profile.d/99-ubuntu-imps.sh ]]; then
  cat > /etc/profile.d/99-ubuntu-imps.sh <<'EOF'
# Private-by-default files for interactive shells.
umask 077
export HISTCONTROL=ignoreboth:erasedups
export PATH="$HOME/.local/bin:$HOME/go/bin:$HOME/.config/composer/vendor/bin:/usr/local/go/bin:$PATH"
EOF
  chmod 0644 /etc/profile.d/99-ubuntu-imps.sh
  checkpoint_mark "$profile_checkpoint"
fi

chmod 0700 "$user_home"
chown -R "$linux_user:$linux_user" "$user_home"
apt-get clean

step 'Final verification'
for tool in "${selected_tools[@]}"; do
  [[ $tool == lerd ]] && continue
  if ! tool_is_installed "$tool"; then
    printf 'Expected command was not installed: %s\n' "$tool" >&2
    exit 1
  fi
done

cat <<EOF

Ubuntu-Imps hardening applied.

After Windows restarts this distribution:
  * Windows drives will not be mounted automatically.
  * Windows executables and Windows PATH injection will be disabled.
  * $linux_user will be the default user and a member of sudo.
  * Direct pushes to main/master will be blocked by a local Git hook.

No GitHub or agent credentials were created or copied.
The Windows wrapper will securely prompt for the sudo password if it is still locked.
Authenticate interactively as $linux_user only after reviewing access scopes.
Enforce pull requests and branch protection on GitHub; local hooks are bypassable.
WSL is not a strong sandbox or a substitute for a separate VM.
EOF

if has_tool devin; then
  printf '\nDevin was installed without starting onboarding. Log in later as %s with:\n  devin setup\n' "$linux_user"
fi
