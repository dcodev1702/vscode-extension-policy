# Intune Deployment Instructions

This directory contains an Intune Remediations package for enforcing the same VS Code `AllowedExtensions` policy value used by the GPO templates.

## Files

- `Detection.ps1` checks `HKLM\SOFTWARE\Policies\Microsoft\VSCode\AllowedExtensions` and exits `0` only when the deployed value matches the approved JSON byte-for-byte.
- `Remediation.ps1` writes the approved JSON to the same machine policy registry value and validates that the JSON parses before writing.

## Why Remediations

Intune ADMX ingestion cannot deploy this policy directly because the `HKLM\SOFTWARE\Policies\Microsoft\*` registry path is blocked for ADMX ingestion. Remediations avoid that limitation by running PowerShell as SYSTEM and writing the supported VS Code policy registry value directly.

## Deployment Quick Reference

```text
Endpoint Manager > Devices > Scripts and remediations > Create
Detection script:    intune/Detection.ps1
Remediation script:  intune/Remediation.ps1
Run as logged-on:    No
Enforce signature:   No
64-bit PowerShell:   Yes
Assignment:          Target your VS Code devices group, hourly schedule
```

## Create The Remediation

1. Open the Intune admin center.
2. Go to **Devices** > **Scripts and remediations**.
3. Select **Create** > **Remediation script**.
4. Name it `VS Code - Allowed Extensions`.
5. Upload `Detection.ps1` as the detection script.
6. Upload `Remediation.ps1` as the remediation script.
7. Set **Run this script using the logged-on credentials** to **No**.
8. Set **Enforce script signature check** to **No**, unless you sign both scripts before upload.
9. Set **Run script in 64-bit PowerShell** to **Yes**.
10. Assign it to the device group that contains managed VS Code endpoints.
11. Use an hourly schedule for fast drift correction, or choose a less frequent schedule if your change-control process requires it.

## Verify Deployment

On a targeted endpoint, wait for the remediation to run or trigger an Intune device sync, then verify the registry value:

```powershell
$value = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\VSCode' AllowedExtensions).AllowedExtensions
$value.Length
$value | ConvertFrom-Json
```

Restart VS Code after the value is present. Approved extensions should continue to load, and non-allowlisted extensions should be blocked from install or activation.

## Maintenance

The approved JSON is intentionally embedded in both scripts. This keeps endpoint execution independent of network access, GitHub availability, or repository authentication.

When the allowlist changes:

1. Update `vscode_extension_allowlist.json` in the repo.
2. Update the JSON inside both `Detection.ps1` and `Remediation.ps1` between the `KEEP IN SYNC` comment blocks.
3. Confirm the two script JSON values are byte-identical.
4. Commit the changes together.
5. Re-upload both scripts to the Intune remediation.

If only one script is updated, endpoints may alternate between detected drift and successful remediation. That failure mode is noisy by design so mismatched scripts are visible in Intune reporting.