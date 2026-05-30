<#
.SYNOPSIS
    Keeps the VS Code AllowedExtensions allowlist in sync across the repo.

.DESCRIPTION
    vscode_extension_allowlist.json is the single source of truth. Running this
    script stamps that exact value into every place the allowlist is duplicated:

      - intune/Detection.ps1      ($expected)
      - intune/Remediation.ps1    ($value)
      - admx/vscode.adml          (<defaultValue>)

    Workflow: edit the JSON, run this script, commit. No more hand-editing four
    copies and hoping they match.

.PARAMETER Check
    Validate-only mode for CI / pre-commit hooks. Makes no changes; prints which
    targets have drifted and exits 1 if any are out of sync, 0 if all match.

.PARAMETER RepoRoot
    Repository root. Defaults to the folder this script lives in.

.EXAMPLE
    .\sync_allowlist.ps1
    Update Detection.ps1, Remediation.ps1, and vscode.adml from the JSON.

.EXAMPLE
    .\sync_allowlist.ps1 -Check
    CI guard: fail the build (exit 1) if any copy has drifted from the JSON.

.NOTES
    The source JSON must be a single line of compact JSON (it is the byte-for-byte
    value Detection.ps1 compares against with -ceq). Run as any user; no admin needed.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = $PSScriptRoot,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

function Read-Text  ([string]$Path) { [System.IO.File]::ReadAllText($Path) }
function Write-Text ([string]$Path, [string]$Content) {
    # UTF-8 without BOM; preserves the file's existing content and line endings.
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

# --- 1. Load and validate the single source of truth ------------------------
$jsonPath = Join-Path $RepoRoot 'vscode_extension_allowlist.json'
if (-not (Test-Path -LiteralPath $jsonPath)) { throw "Source not found: $jsonPath" }

$allowlist = (Read-Text $jsonPath).Trim()
if ($allowlist -match '[\r\n]') {
    throw "Source allowlist must be a single line of compact JSON. Reformat $jsonPath to one line and re-run."
}
try { $null = $allowlist | ConvertFrom-Json } catch {
    throw "Source allowlist is not valid JSON: $($_.Exception.Message)"
}

# In a PowerShell single-quoted literal, apostrophes must be doubled (none expected here).
$psLiteral = $allowlist -replace "'", "''"

# --- 2. Define every place the value lives ----------------------------------
$targets = @(
    @{ Label = 'Detection.ps1 ($expected)'
       Path  = (Join-Path $RepoRoot 'intune/Detection.ps1')
       Regex = [regex]"(?s)(\`$expected\s*=\s*')(.*?)(')"
       Value = $psLiteral }
    @{ Label = 'Remediation.ps1 ($value)'
       Path  = (Join-Path $RepoRoot 'intune/Remediation.ps1')
       Regex = [regex]"(?s)(\`$value\s*=\s*')(.*?)(')"
       Value = $psLiteral }
    @{ Label = 'vscode.adml (<defaultValue>)'
       Path  = (Join-Path $RepoRoot 'admx/vscode.adml')
       Regex = [regex]"(?s)(<defaultValue>)(.*?)(</defaultValue>)"
       Value = $allowlist }
)

# --- 3. Compare / update each target ----------------------------------------
$drift = $false
$mode  = if ($Check) { 'CHECK' } else { 'SYNC' }
Write-Host "Allowlist $mode  (source = $($allowlist.Length) chars)`n"

foreach ($t in $targets) {
    if (-not (Test-Path -LiteralPath $t.Path)) { throw "Target not found: $($t.Path)" }

    $text = Read-Text $t.Path
    $mc   = $t.Regex.Matches($text)
    if ($mc.Count -ne 1) {
        throw "Expected exactly one match for $($t.Label) in $($t.Path), found $($mc.Count). Has the marker or assignment changed?"
    }

    $g       = $mc[0].Groups[2]
    $current = $g.Value
    $desired = $t.Value

    if ($current -ceq $desired) {
        Write-Host ("  [in sync] {0}" -f $t.Label)
        continue
    }

    $drift = $true
    if ($Check) {
        Write-Host ("  [DRIFT]   {0}  (current {1} chars -> expected {2})" -f $t.Label, $current.Length, $desired.Length)
    }
    else {
        # String surgery on the captured group avoids regex replacement-token pitfalls ($1, $&, etc.)
        $updated = $text.Substring(0, $g.Index) + $desired + $text.Substring($g.Index + $g.Length)
        Write-Text $t.Path $updated
        Write-Host ("  [updated] {0}  -> {1} chars" -f $t.Label, $desired.Length)
    }
}

Write-Host ''
if ($Check) {
    if ($drift) { Write-Host 'Result: OUT OF SYNC - run .\sync_allowlist.ps1 to fix.'; exit 1 }
    Write-Host 'Result: all targets in sync with the source JSON.'; exit 0
}
else {
    if ($drift) { Write-Host 'Result: synced all targets from the source JSON.' }
    else        { Write-Host 'Result: everything was already in sync; no changes made.' }
    exit 0
}
