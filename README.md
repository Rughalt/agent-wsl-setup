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
- Optionally installs Node through NVM, Go, `uv`, Lerd, GitHub CLI (`gh`),
  GitLab CLI (`glab`), Gitea CLI (`gt`), Devin CLI, and ZCode CLI.

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
.\create-wsl.ps1 -Tools node,go,uv,lerd,gh,gt,devin
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

Useful customization:

```powershell
.\create-wsl.ps1 `
  -DistroName Ubuntu-Imps `
  -LinuxUser imps `
  -GitName 'Dragonshorn Imp' `
  -GitEmail 'YOUR-MACHINE-USER@users.noreply.github.com' `
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

The account belongs to the `sudo` group, but its password starts locked so the
setup never generates or stores a credential. Set it once from PowerShell:

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

The scripts deliberately do not create, copy, or embed credentials. Start the
distribution and authenticate each selected service interactively:

```bash
wsl -d Ubuntu-Imps
ssh-keygen -t ed25519 -a 100 -C "YOUR-MACHINE-USER@users.noreply.github.com"
gh auth login --git-protocol ssh
gt auth login
glab auth login
```

Give the machine user only the repositories and permissions it needs. Require
pull requests on protected branches and do not allow that account to bypass the
rules.

## Optional tool installation

| Tool | Installation source |
|---|---|
| `gh` | Official GitHub APT repository; keyring checksum is verified |
| `glab` | Latest official GitLab release; release checksum is verified |
| `gt` | Official Gitea installer, which verifies its downloaded binary |
| `devin` | Official `cli.devin.ai` installer, run as the unprivileged user |
| `zcode` | Official `zai-org/ZCode` source; Node is downloaded from nodejs.org and checksum-verified, then the CLI is built with the versions pinned by upstream |
| `node` | NVM from the pinned official installer, followed by the latest Node LTS |
| `go` | Latest stable archive from go.dev, verified using the official release checksum |
| `uv` | Official Astral standalone installer into the unprivileged user's home |
| `lerd` | Official Lerd installer after a WSL restart with systemd; provides containerized PHP, Composer, services, HTTPS and `.test` domains |

ZCode is built from the official source because upstream does not currently
publish a standalone Linux CLI artifact. The similarly named third-party npm
packages are intentionally not used.

Lerd needs systemd and rootless Podman. The setup enables systemd, restarts the
distribution, installs Lerd in the second phase, and grants only the temporary
bootstrap permission needed by its official installer. Day-to-day Lerd usage
runs as `imps` without sudo.

## Removal

Review the name carefully before running this destructive command:

```powershell
wsl --unregister Ubuntu-Imps
```

This permanently deletes the distribution and everything stored inside it.
