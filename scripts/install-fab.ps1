# The Fab step of the AgentSkills install, for Windows (PowerShell 5.1 or later).
#
#   powershell -ExecutionPolicy ByPass -c "irm https://raw.githubusercontent.com/NecturaLabs/AgentSkills/main/scripts/install-fab.ps1 | iex"
#   powershell -ExecutionPolicy ByPass -c "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/NecturaLabs/AgentSkills/main/scripts/install-fab.ps1))) -Uninstall"
#
# Mirrors scripts/install-fab.sh: installs FabCLI (pinned, checksum-verified, from its upstream
# releases) and necturalabs-fab (from AgentSkills releases) into one bin directory on the user PATH,
# and offers to sign in. The fab skill ships in the necturalabs plugin. Everything this script
# creates is recorded in a manifest; -Uninstall removes exactly that and nothing else, including
# the necturalabs-fab plugin and marketplace an installer from before 5.0.0 added.
# Under `irm | iex` parameters cannot be passed; every switch has a NECTURALABS_FAB_* equivalent.

[CmdletBinding()]
param(
  [string]$BinDir = $(if ($env:NECTURALABS_FAB_BIN_DIR) { $env:NECTURALABS_FAB_BIN_DIR } else { Join-Path $HOME '.local\bin' }),
  [string]$Version = $env:NECTURALABS_FAB_VERSION,
  [string]$Source = '',
  [switch]$NoLogin = ($env:NECTURALABS_FAB_NO_LOGIN -eq '1'),
  [switch]$NoModifyPath = ($env:NECTURALABS_FAB_NO_MODIFY_PATH -eq '1'),
  [switch]$Yes,
  [switch]$Uninstall,
  [switch]$KeepConfig
)

# Everything below runs in a child scope, so preferences, strict mode and helper functions never
# leak into a session that ran this through `iex`.
& {
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
# Windows PowerShell 5.1 defaults to TLS 1.0/1.1, which GitHub refuses.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Repo = 'NecturaLabs/AgentSkills'
# The standalone plugin and marketplace installers before 5.0.0 added. Only -Uninstall uses them.
$Marketplace = 'necturalabs-fab'
$Plugin = 'necturalabs-fab@necturalabs-fab'
$FabCliVersion = '0.1.0'
$FabCliAsset = "fabcli-v$FabCliVersion-windows64.zip"
# Pinned rather than read from the release page, so a replaced asset cannot slip through.
$FabCliSha256 = '67e0eb68d62589a3282a4af12085a40246625fa7c57ffdd5189d5814b5c0a383'

$DataDir = Join-Path $env:LOCALAPPDATA 'necturalabs-fab'
$Manifest = Join-Path $DataDir 'install.manifest.json'
$ConfigDir = Join-Path $env:APPDATA 'necturalabs-fab'
# The licence cache lives in the data directory unless an absolute XDG_CACHE_HOME moves it, as it
# does in the binary.
$CacheDir = if ($env:XDG_CACHE_HOME -and [IO.Path]::IsPathRooted($env:XDG_CACHE_HOME)) {
  Join-Path $env:XDG_CACHE_HOME 'necturalabs-fab'
} else { $DataDir }
$FabCliStateDir = Join-Path $env:APPDATA 'fabcli'
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$CodexDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$state = @{ Failed = $false; Source = $Source; Version = $Version }

function Say([string]$Text) { Write-Host $Text }
function Warn([string]$Text) { Write-Warning $Text }
function Have([string]$Name) { [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
# A step that could not be undone. Its manifest entry stays, so a re-run retries it.
function Register-Failure([string]$Text) { Warn $Text; $state.Failed = $true }

# Drive-rooted (C:\...) or UNC (\\server\...) only: a relative or drive-relative path would land
# somewhere that depends on the current directory.
if (-not ($BinDir -match '^[A-Za-z]:\\' -or $BinDir -match '^\\\\[^\\]')) { throw "-BinDir must be an absolute path (got '$BinDir')" }
if ($state.Version -and -not ($state.Version -match '^v[0-9][A-Za-z0-9.+-]*$')) { throw "-Version must be a release tag such as v0.1.0" }

# --- manifest -------------------------------------------------------------------------------

function Read-Manifest {
  if (Test-Path -LiteralPath $Manifest) {
    $data = Get-Content -Raw -LiteralPath $Manifest | ConvertFrom-Json
    $table = @{}
    foreach ($p in $data.PSObject.Properties) { $table[$p.Name] = $p.Value }
    return $table
  }
  return @{}
}

function Write-Manifest([hashtable]$Table) {
  New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
  $Table | ConvertTo-Json | Set-Content -LiteralPath $Manifest -Encoding UTF8
}

function Record([string]$Key, [string]$Value) {
  $table = Read-Manifest
  $table[$Key] = $Value
  Write-Manifest $table
}

function Recorded([string]$Key) {
  $table = Read-Manifest
  if ($table.ContainsKey($Key)) { return [string]$table[$Key] }
  return ''
}

function Forget([string]$Key) {
  if (-not (Test-Path -LiteralPath $Manifest)) { return }
  $table = Read-Manifest
  if ($table.ContainsKey($Key)) { $table.Remove($Key); Write-Manifest $table }
}

# --- helpers --------------------------------------------------------------------------------

function Get-File([string]$Url, [string]$OutFile) {
  $ProgressPreference = 'SilentlyContinue'
  Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
}

# Download one asset of the pinned release: anonymously, or through a signed-in gh when that
# fails. Throws if neither works.
function Get-ReleaseAsset([string]$Name, [string]$OutFile) {
  try { Get-File "https://github.com/$Repo/releases/download/$($state.Version)/$Name" $OutFile; return } catch { }
  if (-not (Have 'gh')) { throw "could not download $Name" }
  if (-not (Invoke-Quiet { gh release download $state.Version -R $Repo -p $Name -O $OutFile --clobber })) { throw "could not download $Name" }
}

# The release every remote artifact comes from, so the binary and the skill always match.
function Resolve-Tag {
  if ($state.Source -or $state.Version) { return }
  $ProgressPreference = 'SilentlyContinue'
  $tag = ''
  try {
    $response = Invoke-WebRequest -Uri "https://github.com/$Repo/releases/latest" -Method Head -UseBasicParsing
    # Windows PowerShell 5.1 and PowerShell 7 expose the final URL differently.
    $final = if ($response.BaseResponse.PSObject.Properties['ResponseUri']) { $response.BaseResponse.ResponseUri.AbsoluteUri } else { $response.BaseResponse.RequestMessage.RequestUri.AbsoluteUri }
    $tag = ($final -split '/')[-1]
  } catch { $tag = '' }
  # When an anonymous request fails, a signed-in gh may still reach the release.
  if (-not ($tag -match '^v[0-9]') -and (Have 'gh')) {
    $tag = (Get-NativeOutput { gh release view -R $Repo --json tagName -q .tagName }).Trim()
  }
  if (-not ($tag -match '^v[0-9][A-Za-z0-9.+-]*$')) { throw "no release of $Repo found (got '$tag'); pass -Version" }
  $state.Version = $tag
}

function Confirm-Step([string]$Question) {
  if ($Yes) { return $true }
  if (-not [Environment]::UserInteractive) { return $false }
  $answer = Read-Host "$Question [Y/n]"
  return -not ($answer -match '^(n|no)$')
}

# Output of a native command, '' if it fails. Stderr is discarded.
function Get-NativeOutput([scriptblock]$Block) {
  $ErrorActionPreference = 'Continue'
  try { return (& $Block 2>$null | Out-String) } catch { return '' }
}

function Invoke-Quiet([scriptblock]$Block) {
  # Native tools write to stderr; under 'Stop', PowerShell 5.1 turns redirected stderr into
  # terminating errors. Exit codes are checked explicitly instead.
  $ErrorActionPreference = 'Continue'
  try { & $Block *> $null; return ($LASTEXITCODE -eq 0) } catch { return $false }
}

# Runs a native command; on failure throws with its combined output.
function Invoke-Checked([string]$What, [scriptblock]$Block) {
  $ErrorActionPreference = 'Continue'
  $out = & $Block 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { throw "$What failed: $($out.Trim())" }
}

# Adds $Dir to the user PATH stored in the registry, keeping the value unexpanded (REG_EXPAND_SZ)
# and notifying Explorer, the approach cargo-dist's installers use. Returns $true if it changed.
function Add-UserPath([string]$Dir) {
  $key = 'registry::HKEY_CURRENT_USER\Environment'
  $current = (Get-Item -LiteralPath $key).GetValue('Path', '', 'DoNotExpandEnvironmentNames') -split ';' -ne ''
  if ($current -contains $Dir) { return $false }
  Set-ItemProperty -Type ExpandString -LiteralPath $key -Name Path -Value ((, $Dir + $current) -join ';')
  Send-EnvironmentChange
  return $true
}

function Remove-UserPath([string]$Dir) {
  $key = 'registry::HKEY_CURRENT_USER\Environment'
  $current = (Get-Item -LiteralPath $key).GetValue('Path', '', 'DoNotExpandEnvironmentNames') -split ';' -ne ''
  if (-not ($current -contains $Dir)) { return }
  Set-ItemProperty -Type ExpandString -LiteralPath $key -Name Path -Value (($current | Where-Object { $_ -ne $Dir }) -join ';')
  Send-EnvironmentChange
}

# A throwaway user variable set and cleared makes Windows broadcast WM_SETTINGCHANGE.
function Send-EnvironmentChange {
  $name = 'necturalabs-fab-' + [guid]::NewGuid().ToString()
  [Environment]::SetEnvironmentVariable($name, '1', 'User')
  [Environment]::SetEnvironmentVariable($name, [NullString]::Value, 'User')
}

function Test-Checkout {
  if ($state.Source) { return }
  if (-not $PSCommandPath) { return }
  $root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
  $cargo = Join-Path $root 'cli\fab\Cargo.toml'
  if ((Test-Path -LiteralPath $cargo) -and (Select-String -LiteralPath $cargo -Pattern '^name = "necturalabs-fab"' -Quiet)) {
    $state.Source = $root
  }
}

function Initialize-BinDir {
  if (-not (Test-Path -LiteralPath $BinDir)) {
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    if (-not (Recorded 'bin_dir')) { Record 'bin_dir' "created:$BinDir" }
  }
}

function Test-ClaudePlugin {
  $ErrorActionPreference = 'Continue'
  if (-not (Have 'claude')) { return $false }
  $list = claude plugin list --json 2>$null | Out-String | ConvertFrom-Json
  return [bool]($list | Where-Object { $_.id -eq $Plugin })
}

function Test-ClaudeMarketplace {
  $ErrorActionPreference = 'Continue'
  $list = claude plugin marketplace list --json 2>$null | Out-String | ConvertFrom-Json
  return [bool]($list | Where-Object { $_.name -eq $Marketplace })
}

function Test-CodexPlugin {
  $config = Join-Path $CodexDir 'config.toml'
  return (Test-Path -LiteralPath $config) -and (Select-String -LiteralPath $config -SimpleMatch "[plugins.`"$Plugin`"]" -Quiet)
}

function Test-CodexMarketplace {
  $ErrorActionPreference = 'Continue'
  $lines = codex plugin marketplace list 2>$null
  return [bool]($lines | Where-Object { ($_ -split '\s+')[0] -eq $Marketplace })
}

# --- install --------------------------------------------------------------------------------

function Install-FabCli([string]$Work) {
  $existing = Get-Command fabcli -ErrorAction SilentlyContinue
  $ours = Recorded 'fabcli'
  if ($existing -and ("installed:" + $existing.Source) -ne $ours) {
    $path = $existing.Source
    $version = Get-NativeOutput { & $path --version }
    if ($version -match '^fabcli 0\.1\.') {
      Say "FabCLI: using the one already at $($existing.Source)"
      if (-not $ours) { Record 'fabcli' ("preexisting:" + $existing.Source) }
      return $existing.Source
    }
    Warn "$($existing.Source) is not FabCLI 0.1.x; installing $FabCliVersion into $BinDir"
  }
  if ([Environment]::Is64BitOperatingSystem -eq $false) {
    Warn 'FabCLI publishes 64-bit Windows builds only; install it manually.'
    return ''
  }
  $target = Join-Path $BinDir 'fabcli.exe'
  if ((Test-Path -LiteralPath $target) -and $ours -ne "installed:$target") {
    throw "$target exists and was not installed by necturalabs-fab; remove it or choose -BinDir"
  }
  Say "FabCLI: downloading $FabCliVersion"
  $zip = Join-Path $Work $FabCliAsset
  Get-File "https://github.com/zirklerite/FabCLI/releases/download/v$FabCliVersion/$FabCliAsset" $zip
  $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLowerInvariant()
  if ($actual -ne $FabCliSha256) { throw "FabCLI checksum mismatch (got $actual); refusing to install" }
  Expand-Archive -LiteralPath $zip -DestinationPath $Work -Force
  Initialize-BinDir
  # FabCLI's sign-in state that predates us belongs to the user: uninstall must then neither sign it
  # out nor delete it.
  if (-not (Recorded 'fabcli_state')) {
    Record 'fabcli_state' $(if (Test-Path -LiteralPath $FabCliStateDir) { 'preexisting' } else { 'ours' })
  }
  Copy-Item -LiteralPath (Join-Path $Work "fabcli-v$FabCliVersion-windows64\fabcli.exe") -Destination $target -Force
  Record 'fabcli' "installed:$target"
  Say "FabCLI: installed $target (checksum verified)"
  return $target
}

function Install-NecturaLabsFab([string]$Work) {
  Initialize-BinDir
  $target = Join-Path $BinDir 'necturalabs-fab.exe'
  if ($state.Source) {
    if (-not (Have 'cargo')) { throw 'building from a checkout needs Rust: https://rustup.rs' }
    Say "necturalabs-fab: building from $($state.Source)"
    Push-Location (Join-Path $state.Source 'cli\fab')
    try { cargo build --release --locked --bin necturalabs-fab --quiet; if ($LASTEXITCODE -ne 0) { throw 'cargo build failed' } }
    finally { Pop-Location }
    Copy-Item -LiteralPath (Join-Path $state.Source 'cli\fab\target\release\necturalabs-fab.exe') -Destination $target -Force
  } else {
    $asset = 'necturalabs-fab-x86_64-pc-windows-msvc.zip'
    $zip = Join-Path $Work $asset
    $sums = Join-Path $Work 'SHA256SUMS'
    $released = $true
    try { Get-ReleaseAsset $asset $zip; Get-ReleaseAsset 'SHA256SUMS' $sums } catch { $released = $false }
    if ($released) {
      $expected = (Get-Content -LiteralPath $sums | Where-Object { ($_ -split '\s+')[1] -in @($asset, "*$asset") } | ForEach-Object { ($_ -split '\s+')[0] }) | Select-Object -First 1
      if (-not $expected) { throw "release SHA256SUMS has no entry for $asset" }
      $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLowerInvariant()
      if ($actual -ne $expected) { throw 'necturalabs-fab checksum mismatch; refusing to install' }
      Expand-Archive -LiteralPath $zip -DestinationPath $Work -Force
      Copy-Item -LiteralPath (Join-Path $Work 'necturalabs-fab.exe') -Destination $target -Force
      Say "necturalabs-fab: installed $($state.Version) (checksum verified)"
    } elseif (Have 'cargo') {
      Say "necturalabs-fab: no release build found for $($state.Version); compiling with cargo"
      cargo install --quiet --locked --git "https://github.com/$Repo" --tag $state.Version --root (Join-Path $Work 'cargo') necturalabs-fab --bin necturalabs-fab
      if ($LASTEXITCODE -ne 0) { throw 'cargo install failed' }
      Copy-Item -LiteralPath (Join-Path $Work 'cargo\bin\necturalabs-fab.exe') -Destination $target -Force
    } else {
      throw 'no release build and no Rust toolchain; install Rust from https://rustup.rs and re-run'
    }
  }
  Record 'necturalabs_fab' "installed:$target"
  if (-not $NoModifyPath -and (Add-UserPath $BinDir)) { Record 'user_path' $BinDir }
  Say "necturalabs-fab: installed $target"
  return $target
}

function Invoke-Install {
  Test-Checkout
  Resolve-Tag
  $work = Join-Path ([IO.Path]::GetTempPath()) ('necturalabs-fab-' + [guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Force -Path $work | Out-Null
  try {
    Say "Installing necturalabs-fab $(if ($state.Version) { "$($state.Version) " })into $BinDir"
    $fabcli = Install-FabCli $work
    $nf = Install-NecturaLabsFab $work
    $fabcliArgs = if ($fabcli) { @('--fabcli-path', $fabcli) } else { @() }

    $status = Get-NativeOutput { & $nf @fabcliArgs --json auth status }
    if ($status -match '"authenticated":true') {
      Say 'Fab: already signed in'
    } elseif ($fabcli -and -not $NoLogin -and (Confirm-Step "Sign in to Fab now? Epic's sign-in page opens in your browser; paste the code it shows back here.")) {
      & $nf @fabcliArgs --human auth login --run
      if ($LASTEXITCODE -ne 0) { Warn "sign-in did not complete; run 'necturalabs-fab auth login --run' later" }
    } else {
      Say 'Sign in later with: necturalabs-fab auth login --run'
    }
    Say ''
    & $nf @fabcliArgs --human doctor
    Say ''
    Say 'Done. Open a new terminal so PATH picks up necturalabs-fab.'
  } finally {
    Remove-Item -Recurse -Force -LiteralPath $work -ErrorAction SilentlyContinue
  }
}

# --- uninstall ------------------------------------------------------------------------------

# Removes a file or directory; $false (and a recorded failure) if it could not.
function Remove-Entry([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $true }
  try {
    Remove-Item -Recurse -Force -LiteralPath $Path
    Say "removed $Path"
    return $true
  } catch {
    Register-Failure "could not remove ${Path}: $($_.Exception.Message)"
    return $false
  }
}

function Invoke-Uninstall {
  if (-not (Test-Path -LiteralPath $Manifest)) {
    Say "Nothing to uninstall: no install record at $Manifest"
    return
  }

  if ((Recorded 'claude_plugin') -eq 'installed') {
    if ((Have 'claude') -and (Invoke-Quiet { claude plugin uninstall $Plugin })) { Say 'removed the Claude Code plugin'; Forget 'claude_plugin' }
    else { Register-Failure "could not uninstall; run: claude plugin uninstall $Plugin" }
  } else { Forget 'claude_plugin' }
  if ((Recorded 'claude_marketplace') -eq 'added') {
    if ((Have 'claude') -and (Invoke-Quiet { claude plugin marketplace remove $Marketplace })) {
      Say 'removed the Claude Code marketplace entry'; Forget 'claude_marketplace'; Forget 'claude_marketplace_source'
    } else { Register-Failure "could not remove; run: claude plugin marketplace remove $Marketplace" }
  } else { Forget 'claude_marketplace'; Forget 'claude_marketplace_source' }
  # Claude marks an uninstalled plugin's cache as orphaned and deletes it later; delete it now,
  # but only once the plugin is really gone.
  if ((Have 'claude') -and -not (Test-ClaudePlugin)) { Remove-Entry (Join-Path $ClaudeDir "plugins\cache\$Marketplace") | Out-Null }

  if ((Recorded 'codex_plugin') -eq 'installed') {
    if ((Have 'codex') -and (Invoke-Quiet { codex plugin remove $Plugin })) { Say 'removed the Codex plugin'; Forget 'codex_plugin' }
    else { Register-Failure "could not uninstall; run: codex plugin remove $Plugin" }
  } else { Forget 'codex_plugin' }
  if ((Recorded 'codex_marketplace') -eq 'added') {
    if ((Have 'codex') -and (Invoke-Quiet { codex plugin marketplace remove $Marketplace })) {
      Say 'removed the Codex marketplace entry'; Forget 'codex_marketplace'; Forget 'codex_marketplace_source'
    } else { Register-Failure "could not remove; run: codex plugin marketplace remove $Marketplace" }
  } else { Forget 'codex_marketplace'; Forget 'codex_marketplace_source' }
  # Codex leaves the plugin's (emptied) cache directory behind.
  if ((Have 'codex') -and -not (Test-CodexPlugin)) { Remove-Entry (Join-Path $CodexDir "plugins\cache\$Marketplace") | Out-Null }
  $codexDirRecord = Recorded 'codex_dir'
  if ($codexDirRecord -like 'created:*') {
    $dir = $codexDirRecord.Substring('created:'.Length)
    if ((Test-Path -LiteralPath $dir) -and -not (Get-ChildItem -Force -LiteralPath $dir)) { Remove-Entry $dir | Out-Null }
    Forget 'codex_dir'
  }

  $fabcli = Recorded 'fabcli'
  if ($fabcli -like 'installed:*') {
    $path = $fabcli.Substring('installed:'.Length)
    if ((Recorded 'fabcli_state') -eq 'ours') {
      if (Test-Path -LiteralPath $path) {
        # FabCLI's own logout deletes the token, its credential-manager entry, the sign-in
        # browser data and the library cache, and stops its background daemon.
        Invoke-Quiet { & $path auth logout } | Out-Null
        Say 'signed FabCLI out (token, credential entry and browser data removed)'
      }
      Remove-Entry $FabCliStateDir | Out-Null
    } else {
      Say "kept FabCLI's sign-in state in $FabCliStateDir (it predates necturalabs-fab)"
    }
    if (Remove-Entry $path) { Forget 'fabcli'; Forget 'fabcli_state' }
  } elseif ($fabcli -like 'preexisting:*') {
    Say "kept FabCLI at $($fabcli.Substring('preexisting:'.Length)) (it was installed before necturalabs-fab)"
    Forget 'fabcli'; Forget 'fabcli_state'
  } else { Forget 'fabcli_state' }

  $nf = Recorded 'necturalabs_fab'
  if ($nf -like 'installed:*') { if (Remove-Entry $nf.Substring('installed:'.Length)) { Forget 'necturalabs_fab' } }
  $userPath = Recorded 'user_path'
  if ($userPath) {
    Remove-UserPath $userPath
    Say "removed $userPath from your PATH"
    Forget 'user_path'
  }
  $binDirRecord = Recorded 'bin_dir'
  if ($binDirRecord -like 'created:*') {
    $dir = $binDirRecord.Substring('created:'.Length)
    if ((Test-Path -LiteralPath $dir) -and -not (Get-ChildItem -Force -LiteralPath $dir)) { Remove-Entry $dir | Out-Null }
    Forget 'bin_dir'
  }
  if (-not $KeepConfig) { Remove-Entry $ConfigDir | Out-Null }
  if ($CacheDir -ne $DataDir) { Remove-Entry $CacheDir | Out-Null }

  if ($state.Failed) {
    throw "some steps failed; their record is kept in $Manifest, so running -Uninstall again retries them"
  }
  Remove-Entry $DataDir | Out-Null

  Say ''
  Say 'necturalabs-fab is uninstalled. Not touched: project .necturalabs-fab.toml files and assets you downloaded.'
}

if ($Uninstall) { Invoke-Uninstall } else { Invoke-Install }
}
