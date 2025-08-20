# poorvc.ps1
# ─────────────────────────────────────────────────────────────
# Local-only mini VCS for Windows PowerShell
# - git-like UX: init / add / status / commit -m / log / diff / restore
# - file/folder unit commits & selective restore
# - .pignore (gitignore-like) for exclusions
# - No external installs required (uses built-in PowerShell)
# ─────────────────────────────────────────────────────────────

Set-StrictMode -Version Latest

$global:PVC = @{
  MetaDir     = ".pvcs"
  CommitsDir  = ".pvcs\commits"
  TmpDir      = ".pvcs\_tmp"
  LogFile     = ".pvcs\log.csv"    # time,commit,author,message,count
  IndexFile   = ".pvcs\index.txt"  # staged relative paths (LF)
  IgnoreFile  = ".pignore"         # gitignore-like patterns (glob)
}

function Test-PVCRepo {
  return (Test-Path $PVC.MetaDir) -and (Test-Path $PVC.LogFile)
}
function Ensure-PVCRepo {
  if (!(Test-PVCRepo)) { throw "Not a PoorVC repo. Run pvc-init first." }
}

function New-PVCRepo {
  if (Test-PVCRepo) { Write-Host "Already initialized."; return }
  New-Item -ItemType Directory -Path $PVC.MetaDir   | Out-Null
  New-Item -ItemType Directory -Path $PVC.CommitsDir| Out-Null
  if (!(Test-Path $PVC.TmpDir)) { New-Item -ItemType Directory -Path $PVC.TmpDir | Out-Null }
  if (!(Test-Path $PVC.LogFile)) {
    Set-Content -Path $PVC.LogFile -Value "time,commit,author,message,count"
  }
  if (!(Test-Path $PVC.IndexFile)) {
    New-Item -ItemType File -Path $PVC.IndexFile | Out-Null
  }
  if (!(Test-Path $PVC.IgnoreFile)) {
    Set-Content -Path $PVC.IgnoreFile -Value @(
      "# PoorVC ignore file (.pignore)"
      "# Use glob patterns like *.tmp, build/, node_modules/, **/bin/"
      ""
    )
  }
  Write-Host "Initialized PoorVC repository."
}

function Get-RelativePath([string]$p) {
  $root = (Resolve-Path ".\").Path
  $full = (Resolve-Path $p -ErrorAction Stop).Path
  if ($full.StartsWith($root)) {
    return $full.Substring($root.Length).TrimStart('\')
  }
  return $p
}

function Read-IgnorePatterns {
  if (!(Test-Path $PVC.IgnoreFile)) { return @() }
  $lines = Get-Content $PVC.IgnoreFile
  # remove comments/empty
  $pat = @()
  foreach ($l in $lines) {
    $t = $l.Trim()
    if ($t -eq "" -or $t.StartsWith("#")) { continue }
    $pat += $t
  }
  return $pat
}

function Test-IgnoreMatch([string]$relPath, [string[]]$patterns) {
  # glob match; support **, *, ?, and folder-style rules
  foreach ($pat in $patterns) {
    $pp = $pat
    # Normalize directory-style rules: "dir/" => "dir/**"
    if ($pp.EndsWith("/")) { $pp = $pp + "**" }
    $pp = $pp -replace "/", "\"
    # Convert to regex
    $rx = [Regex]::Escape($pp)
    $rx = $rx -replace "\\\*\\\*","__DOUBLESTAR__"
    $rx = $rx -replace "\\\*","[^\\]*"
    $rx = $rx -replace "\\\?","[^\\]"
    $rx = $rx -replace "__DOUBLESTAR__",".*"
    $rx = "^$rx$"
    if ($relPath -match $rx) { return $true }
    # also try matching with any leading directories (for patterns like **/bin/**)
    $relNorm = $relPath
    if ($relNorm -match $rx) { return $true }
  }
  return $false
}

function Read-Index {
  if (!(Test-Path $PVC.IndexFile)) { return @() }
  $lines = Get-Content $PVC.IndexFile
  return @($lines | Where-Object { $_ -ne "" })   # ★配列で返す
}

function Write-Index([string[]]$paths) {
  $uniq = $paths | Sort-Object -Unique
  Set-Content -Path $PVC.IndexFile -Value ($uniq -join "`n")
}

function Add-PVC {
  param(
    [Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)]
    [string[]]$Path
  )
  Ensure-PVCRepo
  $patterns = Read-IgnorePatterns
  $staged = Read-Index
  $added  = @()

  foreach ($spec in $Path) {
    if (Test-Path $spec -PathType Container) {
      $files = Get-ChildItem -Recurse -File $spec
      foreach ($f in $files) {
        $rel = Get-RelativePath $f.FullName
        if ($rel.StartsWith("$($PVC.MetaDir)\")) { continue }
        if (Test-IgnoreMatch $rel $patterns) { continue }
        $added += $rel
      }
    } elseif (Test-Path $spec -PathType Leaf) {
      $rel = Get-RelativePath $spec
      if ($rel.StartsWith("$($PVC.MetaDir)\")) { continue }
      if (Test-IgnoreMatch $rel $patterns) { continue }
      $added += $rel
    } else {
      # wildcard pathspec (glob)
      $files = Get-ChildItem -Recurse -File -Filter $spec -ErrorAction SilentlyContinue
      foreach ($f in $files) {
        $rel = Get-RelativePath $f.FullName
        if ($rel.StartsWith("$($PVC.MetaDir)\")) { continue }
        if (Test-IgnoreMatch $rel $patterns) { continue }
        $added += $rel
      }
    }
  }

  $newIndex = $staged + $added
  Write-Index $newIndex
  $stagedCount = @($added | Sort-Object -Unique).Count
  Write-Host ("Staged: {0} file(s)" -f $stagedCount)

}

function Status-PVC {
  Ensure-PVCRepo
  $staged = @(Read-Index)                          # ★配列化
  $count  = $staged.Count
  Write-Host "On branch (single-lineage)"
  Write-Host "Staged files: $count"
  if ($count -gt 0) {
    $preview = $staged | Select-Object -First 20
    $preview | ForEach-Object { "  + $_" }
    if ($count -gt 20) { Write-Host "  ... (+$($count-20) more)" }
  }
  else {
    Write-Host "  (no files staged; use pvc-add <path>)"
  }
}

function Get-NextCommitId {
  $ts = Get-Date -Format "yyyyMMdd-HHmmss"
  $rnd = -join ((48..57 + 97..122) | Get-Random -Count 4 | ForEach-Object {[char]$_})
  return "$ts-$rnd"
}

function Get-HeadCommit {
  Ensure-PVCRepo
  $rows = Import-Csv $PVC.LogFile
  if (-not $rows) { return $null }
  return ($rows | Select-Object -Last 1).commit
}

function Resolve-Ref([string]$ref) {
  Ensure-PVCRepo
  if ([string]::IsNullOrWhiteSpace($ref) -or $ref -eq "HEAD") { return Get-HeadCommit }
  if ($ref -like "HEAD~*") {
    $n = [int]($ref -replace "HEAD~","")
    $rows = Import-Csv $PVC.LogFile
    if ($rows.Count -le $n) { throw "No such revision: $ref" }
    return $rows[$rows.Count - 1 - $n].commit
  }
  return $ref
}

function Commit-PVC {
  param(
    [Alias("m")][Parameter(Mandatory=$true)][string]$Message,
    [string]$Author = $env:UserName
  )
  Ensure-PVCRepo
  $staged = @(Read-Index)                          # ★配列化
  if ($staged.Count -eq 0) {
    throw "Nothing to commit. Stage files first (pvc-add)."
  }

  # build snapshot tree
  if (Test-Path $PVC.TmpDir) { Remove-Item -Recurse -Force $PVC.TmpDir }
  New-Item -ItemType Directory -Path $PVC.TmpDir | Out-Null
  $snapshot = Join-Path $PVC.TmpDir "snapshot"
  New-Item -ItemType Directory -Path $snapshot | Out-Null

  $copied = 0
  foreach ($rel in $staged) {
    $src = Join-Path "." $rel
    if (!(Test-Path $src)) { continue } # skip missing files
    $dst = Join-Path $snapshot $rel
    $dstDir = Split-Path $dst -Parent
    if (!(Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item -Force $src $dst
    $copied++
  }

  $commitId = Get-NextCommitId
  $zip = Join-Path $PVC.CommitsDir "$commitId.zip"
  Compress-Archive -Path (Join-Path $snapshot "*") -DestinationPath $zip -Force

  $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Add-Content $PVC.LogFile "$now,$commitId,$Author,""$Message"",$copied"

  # clear index
  Set-Content -Path $PVC.IndexFile -Value ""

  Write-Host ("Committed {0} file(s) as {1}: {2}" -f $copied, $commitId, $Message)
}

function Log-PVC {
  param([int]$n = 0)
  Ensure-PVCRepo
  $rows = Import-Csv $PVC.LogFile
  if (-not $rows) { Write-Host "No commits yet."; return }
  if ($n -gt 0) { $rows = $rows | Select-Object -Last $n }
  $rows | ForEach-Object {
    "{0}  {1}  {2}  {3}  ({4} file[s])" -f $_.time, $_.commit, $_.author, $_.message, $_.count
  }
}

function Expand-Commit([string]$commitId, [string]$dst) {
  $zip = Join-Path $PVC.CommitsDir "$commitId.zip"
  if (!(Test-Path $zip)) { throw "Unknown commit: $commitId" }
  if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
  New-Item -ItemType Directory -Path $dst | Out-Null
  if ((Get-Item $zip).Length -eq 0) { return }
  Expand-Archive -Path $zip -DestinationPath $dst -Force
}

function Diff-PVC {
  param(
    [Parameter(Mandatory=$true)][string]$From,
    [Parameter(Mandatory=$true)][string]$To,
    [string]$Path
  )
  Ensure-PVCRepo
  $fromId = Resolve-Ref $From
  $toId   = Resolve-Ref $To
  $base   = Join-Path $PVC.TmpDir "diff"
  if (Test-Path $base) { Remove-Item -Recurse -Force $base }
  $A = Join-Path $base "A"
  $B = Join-Path $base "B"
  Expand-Commit $fromId $A
  Expand-Commit $toId   $B

  if ($Path) {
    $rel = (Get-RelativePath $Path)
    $pa = Join-Path $A $rel
    $pb = Join-Path $B $rel
    if (!(Test-Path $pa) -and !(Test-Path $pb)) { throw "Path not present in either commit: $rel" }
    if (!(Test-Path $pa)) { Write-Host "+++ Added: $rel"; return }
    if (!(Test-Path $pb)) { Write-Host "--- Deleted: $rel"; return }
    Write-Host "*** Modified?: $rel"
    fc "$pa" "$pb" | Out-Host
    return
  }

  $filesA = if (Test-Path $A) { Get-ChildItem -Recurse -File $A | ForEach-Object { $_.FullName.Substring($A.Length+1) } } else { @() }
  $filesB = if (Test-Path $B) { Get-ChildItem -Recurse -File $B | ForEach-Object { $_.FullName.Substring($B.Length+1) } } else { @() }
  $all = ($filesA + $filesB) | Sort-Object -Unique

  foreach ($rel in $all) {
    $pa = Join-Path $A $rel
    $pb = Join-Path $B $rel
    if (!(Test-Path $pa))      { Write-Host "+++ Added:   $rel" }
    elseif (!(Test-Path $pb))  { Write-Host "--- Deleted: $rel" }
    else {
      $ha = (Get-FileHash $pa).Hash
      $hb = (Get-FileHash $pb).Hash
      if ($ha -ne $hb) {
        Write-Host "*** Modified: $rel"
        fc "$pa" "$pb" | Out-Host
      }
    }
  }
}

function Restore-PVC {
  param(
    [Parameter(Mandatory=$true)][string]$To,
    [string]$Path,
    [switch]$Force
  )
  Ensure-PVCRepo
  $commitId = Resolve-Ref $To
  $tmp = Join-Path $PVC.TmpDir "restore"
  Expand-Commit $commitId $tmp

  if ($Path) {
    $rel = Get-RelativePath $Path
    $src = Join-Path $tmp $rel
    if (!(Test-Path $src)) { throw "Path not found in commit: $rel" }
    $dstDir = Split-Path $rel -Parent
    if ($dstDir -and !(Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item -Recurse -Force $src ".\$rel"
    Write-Host ("Restored path from {0}: {1}" -f $commitId, $rel)

    return
  }

  if (-not $Force) {
    $ans = Read-Host "Restore ALL files from $commitId and overwrite current files? (y/N)"
    if ($ans -ne 'y') { Write-Host "Canceled."; return }
  }

  # overwrite selected files from commit (no deletion of extra files)
  $files = Get-ChildItem -Recurse -File $tmp
  foreach ($f in $files) {
    $rel = $f.FullName.Substring($tmp.Length+1)
    $dst = ".\$rel"
    $dstDir = Split-Path $dst -Parent
    if ($dstDir -and !(Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item -Force $f.FullName $dst
  }
  Write-Host "Restored all files from $commitId."
}

function Edit-PVCIgnore {
  if (!(Test-Path $PVC.IgnoreFile)) { Set-Content -Path $PVC.IgnoreFile -Value "" }
  Start-Process notepad.exe $PVC.IgnoreFile | Out-Null
}

# public wrappers (git-like)
function Init-PVC      { New-PVCRepo }
function Add-PVCMain   { param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Path) Add-PVC -Path $Path }
function Status-PVCMain{ Status-PVC }
function Commit-PVCMain{ param([Alias("m")][string]$Message,[string]$Author) Commit-PVC -Message $Message -Author $Author }
function Log-PVCMain   { param([int]$n=0) Log-PVC -n $n }
function Diff-PVCMain  { param([string]$From,[string]$To,[string]$Path) Diff-PVC -From $From -To $To -Path $Path }
function Restore-PVCMain { param([string]$To,[string]$Path,[switch]$Force) Restore-PVC -To $To -Path $Path -Force:$Force }
function Ignore-PVCEdit { Edit-PVCIgnore }

# aliases
Set-Alias pvc-init       Init-PVC
Set-Alias pvc-add        Add-PVCMain
Set-Alias pvc-status     Status-PVCMain
Set-Alias pvc-commit     Commit-PVCMain
Set-Alias pvc-log        Log-PVCMain
Set-Alias pvc-diff       Diff-PVCMain
Set-Alias pvc-restore    Restore-PVCMain
Set-Alias pvc-ignore-edit Ignore-PVCEdit
# ─────────────────────────────────────────────────────────────
