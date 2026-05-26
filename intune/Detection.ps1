<#
.SYNOPSIS
    Intune Remediation - Detection script for VS Code AllowedExtensions policy.

.DESCRIPTION
    Verifies that HKLM\SOFTWARE\Policies\Microsoft\VSCode\AllowedExtensions matches
    the approved allowlist byte-for-byte. Returns exit 0 if compliant, exit 1 if
    the value is missing, drifted, or malformed.

.NOTES
    The $expected value below MUST match the $value in Remediation.ps1 exactly.
    When updating the allowlist, change both scripts together.

    Run as SYSTEM. PowerShell 64-bit either works.
#>

$ErrorActionPreference = 'Stop'

$regPath = 'HKLM:\SOFTWARE\Policies\Microsoft\VSCode'
$regName = 'AllowedExtensions'

# --- KEEP IN SYNC WITH Remediation.ps1 ---
$expected = '{"ms-vscode":true,"ms-vscode.powershell":true,"ms-python.python":true,"ms-python.vscode-pylance":true,"ms-python.debugpy":true,"ms-python.vscode-python-envs":true,"ms-azuretools":true,"ms-dotnettools":true,"ms-toolsai.jupyter":true,"ms-toolsai.jupyter-keymap":true,"ms-toolsai.jupyter-renderers":true,"ms-toolsai.vscode-jupyter-cell-tags":true,"ms-toolsai.vscode-jupyter-slideshow":true,"ms-vscode-remote":true,"ms-kubernetes-tools":true,"ms-vsliveshare":true,"ms-edgedevtools":true,"MS-CEINTL":true,"vscode":true,"GitHub":true}'
# -----------------------------------------

try {
    $current = (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction Stop).$regName

    if ($current -ceq $expected) {
        Write-Output "Compliant: AllowedExtensions matches expected value ($($current.Length) chars)"
        exit 0
    }

    Write-Output "Drift detected: registry value does not match expected (current=$($current.Length) chars, expected=$($expected.Length) chars)"
    exit 1
}
catch [System.Management.Automation.ItemNotFoundException] {
    Write-Output "Policy missing: registry path $regPath not found"
    exit 1
}
catch [System.Management.Automation.PSArgumentException] {
    Write-Output "Policy missing: registry value $regName not found"
    exit 1
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
