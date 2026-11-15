# Ubuntu-Imps WSL

Create a separate WSL 2 distribution for coding agents without copying the
credentials, Git configuration, or files from an existing Ubuntu installation.

## What it does

- Installs a fresh Ubuntu distribution named `Ubuntu-Imps`.
- Creates a password-locked, non-sudo `imps` user.
- Disables Windows drive automounting and Windows executable interoperability.
- Uses private-by-default file permissions (`umask 077`).
- Keeps Git, SSH, and CLI credentials separate from the Windows user and other
  WSL distributions.
- Adds a local guardrail against direct pushes to `main` and `master`.
- Optionally installs GitHub CLI (`gh`), GitLab CLI (`glab`), Gitea CLI (`gt`),
  Devin CLI, and the official ZCode CLI source tree.

WSL is useful environment separation, **not a strong security boundary**. Use a
separate VM for untrusted code. Enforce branch protection and least privilege on
the Git hosting service; local Git hooks can be bypassed.

## Quick start

Download `create-wsl.ps1` and `setup-wsl.sh` into the same directory, then run
PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\create-wsl.ps1 -Tools gh,gt,devin
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
.\create-wsl.ps1 -SetupOnly -Tools gh,glab,gt
```

Useful customization:

```powershell
.\create-wsl.ps1 `
  -DistroName Ubuntu-Imps `
  -LinuxUser imps `
  -GitName 'Dragonshorn Imp' `
  -GitEmail 'YOUR-MACHINE-USER@users.noreply.github.com' `
  -Tools gh,gt,devin,zcode
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

ZCode is built from the official source because upstream does not currently
publish a standalone Linux CLI artifact. The similarly named third-party npm
packages are intentionally not used.

## Removal

Review the name carefully before running this destructive command:

```powershell
wsl --unregister Ubuntu-Imps
```

This permanently deletes the distribution and everything stored inside it.
