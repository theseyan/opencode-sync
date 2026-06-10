#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$VERSION = "1.0.0"

function Write-Info($msg) { Write-Host "==> $msg" }
function Write-Warn($msg) { Write-Host "warning: $msg" -ForegroundColor Yellow }
function Die($msg) { Write-Error $msg; exit 1 }

function Get-ConfigDir {
    $base = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $env:USERPROFILE ".config" }
    Join-Path $base "opencode"
}

function Get-StateDir {
    $base = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $env:USERPROFILE ".config" }
    Join-Path $base "opencode-sync"
}

function Get-StateFile {
    Join-Path (Get-StateDir) "state"
}

function Get-AbsPath([string]$Path) {
    if (-not (Test-Path $Path)) { Die "path not found: $Path" }
    return (Resolve-Path $Path).Path
}

function Test-GitRepo([string]$Path) {
    git -C $Path rev-parse --is-inside-work-tree 2>$null
    return $LASTEXITCODE -eq 0
}

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    & git @GitArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Read-StateVar([string]$Key) {
    $file = Get-StateFile
    if (-not (Test-Path $file)) { return $null }
    foreach ($line in Get-Content $file) {
        if ($line -match '^\s*#') { continue }
        if ($line -notmatch '^([^=]+)=(.*)$') { continue }
        if ($Matches[1] -ne $Key) { continue }
        $value = $Matches[2]
        if ($value -match "^'(.*)'$") {
            $value = $Matches[1] -replace "\\'", "'"
        }
        return $value
    }
    return $null
}

function Resolve-LinkTarget([string]$LinkPath) {
    $item = Get-Item $LinkPath -Force
    $target = $item.Target
    if ($target -is [array]) { $target = $target[0] }
    if (-not $target) { return $null }
    if (-not [System.IO.Path]::IsPathRooted($target)) {
        $target = Join-Path (Split-Path $LinkPath -Parent) $target
    }
    if (Test-Path $target) {
        return (Get-AbsPath $target)
    }
    return $target
}

function Clear-State {
    $file = Get-StateFile
    if (Test-Path $file) { Remove-Item $file -Force }
}

function Try-ResolveRepo {
    $config = Get-ConfigDir
    if (Test-IsLink $config) {
        $target = Resolve-LinkTarget $config
        if ($target -and (Test-Path $target)) {
            return (Get-AbsPath $target)
        }
    }
    $repo = Read-StateVar "REPO_PATH"
    if ($repo -and (Test-Path $repo)) {
        return (Get-AbsPath $repo)
    }
    return $null
}

function Resolve-Repo {
    $repo = Try-ResolveRepo
    if ($repo) { return $repo }
    Die "no linked repo found; run: opencode-sync init"
}

function Write-State([string]$Repo) {
    $dir = Get-StateDir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $escaped = $Repo -replace "'", "\'"
    $content = @(
        "REPO_PATH='$escaped'"
        "LINKED_AT=$((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
    )
    Set-Content -Path (Get-StateFile) -Value $content -Encoding UTF8
}

function Get-DefaultGitignore {
    @"
# Dependencies
node_modules/

# Logs
*.log

# OS
.DS_Store
Thumbs.db

# Secrets / local overrides
.env
.env.*
*.local.json
*.local.jsonc

# Plugin build artifacts
plugins/node_modules/
"@
}

function Write-DefaultGitignore([string]$Repo) {
    $file = Join-Path $Repo ".gitignore"
    if (Test-Path $file) { return }
    Get-DefaultGitignore | Set-Content -Path $file -Encoding UTF8
}

function Confirm-Gitignore([string]$Repo) {
    $file = Join-Path $Repo ".gitignore"
    while ($true) {
        Write-Host ""
        Write-Host "--- .gitignore ---"
        Get-Content $file | Write-Host
        Write-Host "--- end ---"
        Write-Host ""
        $ans = Read-Host "Does this look correct? [Y/n/e]"
        if ([string]::IsNullOrWhiteSpace($ans)) { $ans = "Y" }
        switch ($ans.ToLower()) {
            { $_ -in "y", "yes" } { return }
            { $_ -in "n", "no" }  { Die "aborted" }
            { $_ -in "e", "edit" } {
                if ($env:EDITOR) {
                    $editorArgs = $env:EDITOR -split '\s+'
                    & $editorArgs[0] ($editorArgs[1..($editorArgs.Length - 1)] + $file)
                } else {
                    notepad $file
                }
            }
            default { Write-Warn "enter Y, n, or e" }
        }
    }
}

function Copy-ConfigTree([string]$Src, [string]$Dst) {
    if (-not (Test-Path $Dst)) { New-Item -ItemType Directory -Path $Dst -Force | Out-Null }
    Get-ChildItem -Path $Src -Force | Where-Object {
        $_.Name -notin @("node_modules", ".git")
    } | ForEach-Object {
        $dest = Join-Path $Dst $_.Name
        if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            if ($_.LinkType -eq "SymbolicLink") {
                try {
                    New-Item -ItemType SymbolicLink -Path $dest -Target $_.Target -Force | Out-Null
                } catch {
                    Write-Warn "could not copy symlink $($_.Name); copying target contents"
                    if (Test-Path $_.FullName) { Copy-ConfigTree $_.FullName $dest }
                }
            } elseif ($_.PSIsContainer) {
                Copy-ConfigTree $_.FullName $dest
            } else {
                Copy-Item -Path $_.FullName -Destination $dest -Force
            }
        } elseif ($_.PSIsContainer) {
            Copy-ConfigTree $_.FullName $dest
        } else {
            Copy-Item -Path $_.FullName -Destination $dest -Force
        }
    }
}

function Backup-ConfigDir([string]$Config) {
    $bak = "$Config.bak"
    if (Test-Path $bak) { Die "$bak already exists; move or remove it first" }
    Move-Item -Path $Config -Destination $bak
    Write-Info "backed up existing config to $bak"
}

function Test-ConfigDirPopulated([string]$Config) {
    if (-not (Test-Path $Config)) { return $false }
    $item = Get-Item $Config -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    return (Get-ChildItem -Path $Config -Force | Measure-Object).Count -gt 0
}

function Test-IsLink([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    $item = Get-Item $Path -Force
    return ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function New-ConfigLink([string]$Repo, [string]$Config) {
    $parent = Split-Path $Config -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    # Junction: no admin required on Windows
    cmd /c mklink /J "$Config" "$Repo" | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "failed to create junction $Config -> $Repo" }
}

function Invoke-Link([string]$RepoPath) {
    $repo = Get-AbsPath $RepoPath
    if (-not (Test-GitRepo $repo)) { Die "not a git repository: $repo" }

    $config = Get-ConfigDir
    if (Test-IsLink $config) {
        $target = Resolve-LinkTarget $config
        if ($target -and (Test-Path $target) -and (Get-AbsPath $target) -eq $repo) {
            Write-Info "already linked to $repo"
            Write-State $repo
            return
        }
        Die "$config is linked elsewhere ($target); run: opencode-sync unlink"
    }

    if (Test-Path $config) {
        if (Test-ConfigDirPopulated $config) {
            Die "$config exists and is not empty; back it up or remove it before linking"
        }
        Remove-Item $config -Force
    }

    New-ConfigLink $repo $config
    Write-State $repo
    Write-Info "linked $config -> $repo"
}

function Invoke-Unlink {
    $config = Get-ConfigDir
    if (-not (Test-IsLink $config)) { Die "$config is not a junction/symlink" }
    $target = Resolve-LinkTarget $config
    cmd /c rmdir "$config" | Out-Null
    if ($LASTEXITCODE -ne 0) { Remove-Item $config -Force }
    Clear-State
    Write-Info "removed link $config -> $target"
    Write-Info "repo unchanged at $target"
}

function Invoke-GitCommitIfDirty([string]$Repo) {
    Invoke-Git @('-C', $Repo, 'add', '-A')
    git -C $Repo diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
        $msg = "opencode-sync: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
        Invoke-Git @('-C', $Repo, 'commit', '-m', $msg)
    }
}

function Test-RemoteHasBranch([string]$Repo, [string]$Remote, [string]$Branch) {
    git -C $Repo ls-remote --exit-code --heads $Remote $Branch 2>$null
    return $LASTEXITCODE -eq 0
}

function Invoke-Sync {
    $repo = Resolve-Repo
    Write-Info "syncing $repo"
    Invoke-GitCommitIfDirty $repo
    $remotes = git -C $repo remote
    if (-not $remotes) {
        Write-Warn "no remote configured; committed locally only"
        Write-Info "sync complete"
        return
    }
    $branch = git -C $repo symbolic-ref --short HEAD 2>$null
    if (-not $branch) { $branch = "main" }
    git -C $repo rev-parse --abbrev-ref "@{upstream}" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Invoke-Git @('-C', $repo, 'pull')
        Invoke-Git @('-C', $repo, 'push')
    } else {
        $remote = ($remotes -split "`n")[0]
        if (Test-RemoteHasBranch $repo $remote $branch) {
            Invoke-Git @('-C', $repo, 'pull', $remote, $branch)
        } elseif ($branch -ne "main" -and (Test-RemoteHasBranch $repo $remote "main")) {
            Invoke-Git @('-C', $repo, 'pull', $remote, 'main')
        } else {
            Write-Info "remote has no $branch branch yet; skipping pull"
        }
        Invoke-Git @('-C', $repo, 'push', '-u', $remote, $branch)
    }
    Write-Info "sync complete"
}

function Invoke-Status {
    $config = Get-ConfigDir
    Write-Host "config dir: $config"
    if (Test-IsLink $config) {
        Write-Host "link:       $(Resolve-LinkTarget $config)"
    } elseif (Test-Path $config) {
        Write-Host "link:       (not linked - regular directory)"
    } else {
        Write-Host "link:       (missing)"
    }
    $repo = Try-ResolveRepo
    if ($repo) {
        Write-Host "repo:       $repo"
        Write-Host ""
        git -C $repo status -sb
        Write-Host ""
        git -C $repo remote -v
    } else {
        Write-Host "repo:       (not found)"
    }
}

function Read-RepoPath([string]$Default) {
    $input = Read-Host "Repo path [$Default]"
    if ([string]::IsNullOrWhiteSpace($input)) { $input = $Default }
    if ($input -match '^~\\?(.*)$') {
        $rest = $Matches[1]
        if ($rest) { $input = Join-Path $env:USERPROFILE $rest.Replace('/', '\') }
        else { $input = $env:USERPROFILE }
    }
    if (Test-Path $input) { return (Get-AbsPath $input) }
    $dir = Split-Path $input -Parent
    $base = Split-Path $input -Leaf
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return (Join-Path (Resolve-Path $dir).Path $base)
}

function Read-RemoteUrl {
    $url = Read-Host "Remote URL"
    if ([string]::IsNullOrWhiteSpace($url)) { Die "remote URL is required" }
    return $url
}

function Invoke-InitNewRepo {
    $config = Get-ConfigDir
    $defaultRepo = Join-Path $env:USERPROFILE "opencode-config"
    $repo = Read-RepoPath $defaultRepo

    if (Test-Path $repo) {
        $items = Get-ChildItem -Path $repo -Force
        if ($items.Count -gt 0) { Die "$repo already exists" }
    } else {
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
    }

    if (Test-IsLink $config) { Die "$config is already linked; unlink first" }

    if ((Test-Path $config) -and -not (Test-IsLink $config)) {
        if (Test-ConfigDirPopulated $config) {
            Write-Info "copying $config -> $repo"
            Copy-ConfigTree $config $repo
            Backup-ConfigDir $config
        }
    }

    if (-not (Test-GitRepo $repo)) {
        git -C $repo init -b main 2>$null
        if ($LASTEXITCODE -ne 0) {
            Invoke-Git @('-C', $repo, 'init')
            git -C $repo checkout -b main 2>$null
        }
    }

    Write-DefaultGitignore $repo
    Confirm-Gitignore $repo

    Invoke-Git @('-C', $repo, 'add', '-A')
    git -C $repo diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Warn "nothing to commit; creating empty initial commit"
        Invoke-Git @('-C', $repo, 'commit', '--allow-empty', '-m', 'Initial opencode config')
    } else {
        Invoke-Git @('-C', $repo, 'commit', '-m', 'Initial opencode config')
    }

    $remote = Read-RemoteUrl
    git -C $repo remote get-url origin 2>$null
    if ($LASTEXITCODE -eq 0) {
        Invoke-Git @('-C', $repo, 'remote', 'set-url', 'origin', $remote)
    } else {
        Invoke-Git @('-C', $repo, 'remote', 'add', 'origin', $remote)
    }

    $branch = git -C $repo symbolic-ref --short HEAD 2>$null
    if (-not $branch) { $branch = "main" }
    Invoke-Git @('-C', $repo, 'push', '-u', 'origin', $branch)

    Invoke-Link $repo
    Write-Info "init complete"
}

function Invoke-InitCloneRepo {
    $config = Get-ConfigDir
    $remote = Read-RemoteUrl
    $defaultRepo = Join-Path $env:USERPROFILE "opencode-config"
    $repo = Read-RepoPath $defaultRepo

    if (Test-Path $repo) { Die "$repo already exists" }
    if (Test-IsLink $config) { Die "$config is already linked; unlink first" }

    if ((Test-Path $config) -and -not (Test-IsLink $config) -and (Test-ConfigDirPopulated $config)) {
        Write-Host "Existing config found at $config"
        $ans = Read-Host "Back up to ${config}.bak and continue? [Y/n]"
        if ([string]::IsNullOrWhiteSpace($ans)) { $ans = "Y" }
        switch ($ans.ToLower()) {
            { $_ -in "y", "yes" } { Backup-ConfigDir $config }
            default { Die "aborted" }
        }
    }

    Invoke-Git @('clone', $remote, $repo)

    if (-not (Test-Path (Join-Path $repo ".gitignore"))) {
        $ans = Read-Host "No .gitignore found. Add defaults? [Y/n]"
        if ([string]::IsNullOrWhiteSpace($ans)) { $ans = "Y" }
        switch ($ans.ToLower()) {
            { $_ -in "y", "yes" } {
                Write-DefaultGitignore $repo
                Confirm-Gitignore $repo
                Invoke-Git @('-C', $repo, 'add', '.gitignore')
                Invoke-Git @('-C', $repo, 'commit', '-m', 'Add default .gitignore')
                $branch = git -C $repo symbolic-ref --short HEAD 2>$null
                if (-not $branch) { $branch = "main" }
                git -C $repo push origin $branch
                if ($LASTEXITCODE -ne 0) { Write-Warn "could not push .gitignore commit" }
            }
            default { Write-Warn "continuing without .gitignore - be careful not to commit secrets" }
        }
    }

    Invoke-Link $repo
    Write-Info "init complete"
}

function Invoke-Init {
    Write-Host "OpenCode config sync - setup"
    Write-Host ""
    Write-Host "  1) Create a new repo from my existing config (first machine)"
    Write-Host "  2) Clone an existing repo (another machine)"
    Write-Host ""
    $choice = Read-Host "Choose [1/2]"
    switch ($choice) {
        "1" { Invoke-InitNewRepo }
        "2" { Invoke-InitCloneRepo }
        default { Die "invalid choice" }
    }
}

function Show-Usage {
    @"
opencode-sync $VERSION - sync OpenCode config via git

Usage:
  opencode-sync init              Interactive setup (new repo or clone)
  opencode-sync link <repo>       Link config dir to a git repo
  opencode-sync sync              Commit, pull, then push
  opencode-sync status            Show link and git status
  opencode-sync unlink            Remove junction (repo is kept)
  opencode-sync version           Show version
"@
}

$cmd = $args[0]
$rest = @()
if ($args.Count -gt 1) { $rest = $args[1..($args.Count - 1)] }

switch ($cmd) {
    "init"    { Invoke-Init }
    "link"    {
        if ($rest.Count -ne 1) { Die "usage: opencode-sync link <repo>" }
        Invoke-Link $rest[0]
    }
    "sync"    { Invoke-Sync }
    "status"  { Invoke-Status }
    "unlink"  { Invoke-Unlink }
    { $_ -in "version", "--version", "-V" } { Write-Host "opencode-sync $VERSION" }
    { $_ -in "help", "--help", "-h", $null, "" } { Show-Usage }
    default   { Die "unknown command: $cmd (try: opencode-sync help)" }
}
