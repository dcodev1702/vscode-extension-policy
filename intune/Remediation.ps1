<#
.SYNOPSIS
    Intune Remediation - Remediation script for VS Code AllowedExtensions policy.

.DESCRIPTION
    Writes the approved VS Code extension allowlist to
    HKLM\SOFTWARE\Policies\Microsoft\VSCode\AllowedExtensions. Creates the
    registry path if it does not exist. Returns exit 0 on success.

.NOTES
    The $value below MUST match the $expected value in Detection.ps1 exactly.
    When updating the allowlist, change both scripts together.

    Run as SYSTEM. PowerShell 64-bit either works.
    The Policies\Microsoft\VSCode key is machine-scope; all users on the
    device inherit the policy.
#>

$ErrorActionPreference = 'Stop'

$regPath = 'HKLM:\SOFTWARE\Policies\Microsoft\VSCode'
$regName = 'AllowedExtensions'

# --- KEEP IN SYNC WITH Detection.ps1 ---
$value = '{"ms-vscode":true,"ms-vscode.powershell":true,"ms-python.python":true,"ms-python.vscode-pylance":true,"ms-python.debugpy":true,"ms-python.vscode-python-envs":true,"ms-azuretools":true,"ms-dotnettools":true,"ms-toolsai.jupyter":true,"ms-toolsai.jupyter-keymap":true,"ms-toolsai.jupyter-renderers":true,"ms-toolsai.vscode-jupyter-cell-tags":true,"ms-toolsai.vscode-jupyter-slideshow":true,"ms-vscode-remote":true,"ms-kubernetes-tools":true,"ms-vsliveshare":true,"ms-edgedevtools":true,"MS-CEINTL":true,"vscode":true,"GitHub":true}'
# ---------------------------------------

try {
    # Verify the JSON parses before writing it, so we never deploy a broken value
    $null = $value | ConvertFrom-Json -ErrorAction Stop

    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    New-ItemProperty -Path $regPath -Name $regName -Value $value -PropertyType String -Force | Out-Null

    Write-Output "Remediated: AllowedExtensions set ($($value.Length) chars)"
    exit 0
}
catch {
    Write-Output "Remediation failed: $($_.Exception.Message)"
    exit 1
}
