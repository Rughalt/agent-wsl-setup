# Ubuntu-Imps WSL

Create a separate WSL 2 distribution for coding agents without copying the
credentials, Git configuration, or files from an existing Ubuntu installation.

## What it does

- Installs a fresh Ubuntu distribution named `Ubuntu-Imps`.
- Creates an `imps` user with optional password-based `sudo` access.
- Disables Windows drive automounting and Windows executable interoperability.
- Uses private-by-default file permissions (`umask 077`).
- Keeps Git, SSH, and CLI credentials separate from the Windows user and other
  WSL distributions.
- Adds a local guardrail against direct pushes to `main` and `master`.
- Adds an Ubuntu-Imps login banner and a local purple/pink Oh My Posh theme.
- Adds a matching purple/pink `😈 Ubuntu-Imps` profile to Windows Terminal without modifying its main settings file.
- Optionally installs Node through NVM, Playwright with Chromium, Go, `uv`, Lerd, GitHub CLI (`gh`),
  GitLab CLI (`glab`), Gitea CLI (`gt`), Devin CLI, ZCode CLI, FigCraft CLI,
  and the shared Shiori Brain skills.

WSL is useful environment separation, **not a strong security boundary**. Use a
separate VM for untrusted code. Enforce branch protection and least privilege on
the Git hosting service; local Git hooks can be bypassed.

## Quick start

### One-line installer

Run the current version directly from this repository in PowerShell:

```powershell
$AgentWslTools = 'all'; irm 'https://raw.githubusercontent.com/Rughalt/agent-wsl-setup/main/install.ps1' | iex
```

Install only selected tools:

```powershell
$AgentWslTools = 'node,go,uv,lerd,gh,gt'; irm 'https://raw.githubusercontent.com/Rughalt/agent-wsl-setup/main/install.ps1' | iex
```

The bootstrap downloads `create-wsl.ps1` and `setup-wsl.sh` from this repository
to a unique temporary directory, invokes them with the supplied options, and
removes the downloaded copies afterwards. Review `install.ps1` before running
the one-liner if you do not want to execute the current `main` branch directly.

### Downloaded scripts

Download `create-wsl.ps1` and `setup-wsl.sh` into the same directory, then run
PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\create-wsl.ps1 -Tools node,playwright,go,uv,lerd,gh,gt,devin
```

Install every optional CLI (the ZCode source build can take a while):

```powershell
.\create-wsl.ps1 -Tools all
```

Install no optional CLIs:

```powershell
.\create-wsl.ps1
```

Add or repair tools later without recreating the distribution:

```powershell
.\create-wsl.ps1 -SetupOnly -Tools node,go,uv,gh,glab,gt
```

The same operation through the one-line installer:

```powershell
$AgentWslSetupOnly = $true; $AgentWslTools = 'node,go,uv,gh,glab,gt'; irm 'https://raw.githubusercontent.com/Rughalt/agent-wsl-setup/main/install.ps1' | iex
```

If the distribution already exists and `SetupOnly` was not supplied, the
installer asks whether it should re-run setup and hardening instead of failing.

Useful customization:

```powershell
.\create-wsl.ps1 `
  -DistroName Ubuntu-Imps `
  -LinuxUser imps `
  -GitName 'Imp Kodzislaw' `
  -GitEmail 'cespenar@dragonshorn.info' `
  -Tools node,go,uv,lerd,gh,gt,devin,zcode
```

## Entering the distribution and enabling sudo

`imps` is configured as the default user, so the normal login is:

```powershell
wsl -d Ubuntu-Imps
```

You can also select the user explicitly:

```powershell
wsl -d Ubuntu-Imps -u imps
```

The account belongs to the `sudo` group. After the Linux setup succeeds, the
installer runs the native `passwd` prompt for `imps`; input is hidden and the
password is never passed as an argument, logged, generated, or stored by these
scripts. If that prompt was cancelled, set it later from PowerShell:

```powershell
wsl -d Ubuntu-Imps -u root -- passwd imps
```

After entering the new password twice, open the distribution normally and use
`sudo` when an additional package genuinely needs root access. To open an
emergency root shell without changing the default user:

```powershell
wsl -d Ubuntu-Imps -u root
```

## Authentication

The default Git author is `Imp Kodzislaw <cespenar@dragonshorn.info>`.
Register that address in Gravatar to give the persona an avatar. To attribute
the commits to the authenticated `imp-coders` GitHub account too, add and verify
the same address in that account's email settings. GitHub CLI authentication
and Git commit identity are separate settings.

The scripts deliberately do not create, copy, or embed credentials. Start the
distribution and authenticate each selected service interactively:

```bash
wsl -d Ubuntu-Imps
ssh-keygen -t ed25519 -a 100 -C "cespenar@dragonshorn.info"
gh auth login --git-protocol ssh
gt auth login
glab auth login
devin setup
```

Authentication and onboarding are deliberately never launched by the setup
script. Run them later in an interactive shell so browser or token prompts
cannot block the unattended installation.

## Resuming interrupted setup

Completed steps are recorded only after they succeed in
`/var/lib/agent-wsl-setup/completed`. Re-running setup skips finished base,
user, hardening, Git, shell-profile, Lerd, and per-tool steps. An interrupted
step has no checkpoint and is retried. Existing tool binaries from installations
made before checkpoint support are detected and recorded without reinstalling.

Inspect the saved checkpoints from PowerShell with:

```powershell
wsl -d Ubuntu-Imps -u root -- ls -1 /var/lib/agent-wsl-setup/completed
```

To deliberately repeat one step, remove only its corresponding checkpoint as
root and run setup again. Checkpoint names contain explicit schema versions so
future installer changes can invalidate only the affected step.

Give the machine user only the repositories and permissions it needs. Require
pull requests on protected branches and do not allow that account to bypass the
rules.

## Optional tool installation

| Tool | Installation source |
|---|---|
| `gh` | Official GitHub APT repository; keyring checksum is verified |
| `glab` | Latest official GitLab release; release checksum is verified |
| `gt` | Official Gitea installer, which verifies its downloaded binary |
| `devin` | Binary from the official `static.devin.ai` release manifest, with its SHA-256 verified; interactive setup is never launched |
| `zcode` | Official `zai-org/ZCode` source; Node is downloaded from nodejs.org and checksum-verified, then the CLI is built with the versions pinned by upstream |
| `figcraft` | Latest official `storytold/figcraft` Linux release for the current architecture; `SHA256SUMS.txt` is verified and `figcraft-cli` includes the MCP server |
| `shiori` | Runs the official `Dragonshorn-Studios/shiori-brain` doctor last, creating a managed checkout and linking generated skills into `~/.agents/skills` |
| `node` | NVM from the pinned official installer, followed by the latest Node LTS |
| `playwright` | Latest Playwright CLI, Linux browser dependencies, and its matching Chromium build for screenshots and browser automation |
| `go` | Latest stable archive from go.dev, verified using the official release checksum |
| `uv` | Official Astral standalone installer into the unprivileged user's home |
| `lerd` | Official Lerd installer after a WSL restart with systemd; provides containerized PHP, Composer, services, HTTPS and `.test` domains |

ZCode is built from the official source because upstream does not currently
publish a standalone Linux CLI artifact. The similarly named third-party npm
packages are intentionally not used.

Lerd needs systemd and rootless Podman. The setup enables systemd, restarts the
distribution, installs Lerd in a detached non-interactive session, and then
explicitly runs the official system bootstrap followed by
`lerd install --unattended`. Temporary sudo permissions are limited to that
bootstrap and the exact files/commands Lerd uses to hand WSL DNS to
`systemd-resolved`; they are removed immediately afterward. Day-to-day Lerd
usage runs as `imps` without sudo.

All running WSL distributions share the host's listening ports. If Lerd is
already running in another distribution, its nginx and dashboard normally own
ports 80, 443, and 7073. The installer will still install Lerd in `Ubuntu-Imps`
and record the completed step, but it will not stop the other stack. To switch
manually, stop Lerd in the other distribution and then run:

```powershell
wsl -d Ubuntu-Imps -u imps -- bash -lc 'lerd start'
```

Oh My Posh is installed from its official Linux installer into
`~/.local/bin`. The custom theme is stored locally at
`~/.config/ohmyposh/imp.omp.json`, so starting a shell does not download a
remote theme. For full icon coverage, configure a Nerd Font in Windows Terminal.

Shiori Brain is installed after every selected CLI. It uses the repository's
official doctor in `opencode` compatibility mode, which installs the shared
Agent Skills without requiring OpenCode itself. It does not copy credentials.

## Removal

When the one-line installer finds an existing distribution, choose `R` to reset
it. The installer requires typing the exact distribution name before it calls
`wsl --unregister`, removes its managed install directory, and recreates it:

```powershell
$AgentWslTools = 'all'; irm 'https://raw.githubusercontent.com/Rughalt/agent-wsl-setup/main/install.ps1' | iex
```

The downloaded-script equivalent is:

```powershell
.\create-wsl.ps1 -ResetDistro -Tools all
```

To permanently remove the distribution without recreating it, review the name
carefully and run:

```powershell
wsl --unregister Ubuntu-Imps
```

This permanently deletes the distribution and everything stored inside it.
