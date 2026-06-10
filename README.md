# opencode-sync

Keep your [OpenCode](https://opencode.ai) config in sync across machines with git.

OpenCode reads global config from `~/.config/opencode` (or `%USERPROFILE%\.config\opencode` on Windows). This tool points that directory at a git repo you own. Edit config as usual; run `sync` when you want changes committed and pushed.

## Requirements

- git
- bash on macOS/Linux, PowerShell 5.1+ on Windows

## Install

macOS/Linux (installs to `~/.local/bin`):

```bash
curl -fsSL https://raw.githubusercontent.com/theseyan/opencode-sync/main/install.sh | bash
```

Windows (installs to `%LOCALAPPDATA%\bin`):

```powershell
irm https://raw.githubusercontent.com/theseyan/opencode-sync/main/install.ps1 | iex
```

Custom install path:

```bash
INSTALL_DIR=/usr/local/bin curl -fsSL https://raw.githubusercontent.com/theseyan/opencode-sync/main/install.sh | bash
```

```powershell
$env:INSTALL_DIR = "C:\Tools\bin"; irm https://raw.githubusercontent.com/theseyan/opencode-sync/main/install.ps1 | iex
```

Or clone the repo and run `./install.sh` / `.\install.ps1` if you'd rather read the scripts first.

## Usage

First machine:

```bash
opencode-sync init   # pick option 1
```

Another machine:

```bash
opencode-sync init   # pick option 2, paste your remote URL
```

Daily:

```bash
opencode-sync sync
```

| Command | What it does |
|---------|----------------|
| `init` | Set up a new repo from local config, or clone an existing one |
| `link <repo>` | Point `~/.config/opencode` at a git repo |
| `sync` | Commit, pull, push |
| `status` | Show where you're linked and git status |
| `unlink` | Remove the link (repo stays put) |

`sync` runs `git add -A`, commits if needed, then `git pull` and `git push`. You'll see all git output. Fix merge conflicts in the repo yourself, then run `sync` again.

## Your config repo

The repo root should look like `~/.config/opencode`, not a nested `opencode/` folder:

```
opencode-config/
├── opencode.json
├── agents/
├── commands/
└── ...
```

`init` creates a `.gitignore` with sensible defaults (`node_modules/`, `.env`, `*.local.json`, etc.). You'll get a chance to review it before the first commit.

## Windows

Uses directory junctions (`mklink /J`), so no admin rights needed. If `XDG_CONFIG_HOME` is set, that's used instead of `%USERPROFILE%\.config`.

## Notes

Don't commit API keys. Use `{file:path}` in OpenCode config or gitignored `*.local.json` files for secrets.

This only syncs `~/.config/opencode`. Sessions, cache, and prompt history under `~/.local/share/opencode` and `~/.local/state/opencode` stay on each machine.
