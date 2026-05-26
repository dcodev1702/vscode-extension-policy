# 🔐 VSCode Extension Policy

Group Policy templates and reference allowlist for centrally managing Visual Studio Code extensions across managed Windows endpoints.

## Why this exists

The May 2026 [Nx Console supply-chain compromise (CVE-2026-48027)](https://github.com/nrwl/nx-console/security/advisories/GHSA-c9j4-9m59-847w) demonstrated that a single poisoned VS Code extension — pushed through auto-update during an 18-minute window — is enough to harvest GitHub PATs, AWS keys, npm tokens, 1Password vaults, and Anthropic / Claude Code configs from a developer machine. The malicious version reached ~6,000 installs before takedown. GitHub itself disclosed that ~3,800 internal repos were exfiltrated from a single employee device running the compromised extension.

This repo enforces a **deny-by-default extension allowlist** so unapproved publishers (including future compromised ones) cannot be installed or activated on managed endpoints.

## Repository structure

```
.
├── README.md
├── vscode_extension_allowlist.json
│                               # Source of truth for the approved extensions
├── admx/
│   ├── vscode.admx             # Minimal ADMX template (AllowedExtensions + UpdateMode)
│   └── vscode.adml             # English strings + pre-filled default value
├── intune/
│   ├── Detection.ps1           # Intune Remediation detection script
│   ├── Remediation.ps1         # Intune Remediation remediation script
│   └── instructions.md         # Intune deployment steps
└── images/                     # Screenshots referenced in this README
```

## How it works

VS Code 1.96+ honors the `AllowedExtensions` policy at `HKLM\SOFTWARE\Policies\Microsoft\VSCode\AllowedExtensions`. When set, only extensions on the list can be installed; anything else is blocked from the marketplace UI, and any already-installed non-allowed extension is disabled with an org-managed banner.

The policy value is a single-line JSON object mapping extension or publisher IDs to `true` / `false` / a version array.

## ⚠️ Critical gotcha: publisher-level entries are unreliable

The VS Code docs suggest publisher-level entries like `"ms-python": true` will allow every extension from that publisher. **In practice, this is broken for any extension that depends on other extensions for activation.** This is tracked upstream in [microsoft/vscode#243536](https://github.com/microsoft/vscode/issues/243536) and [#238751](https://github.com/microsoft/vscode/issues/238751).

Confirmed broken with publisher-level allow:
- `ms-python` — Python extension installs but Pylance and Debugpy fail to activate
- `ms-vscode.powershell` — fails to load when only `ms-vscode` is allowed (the PowerShell language host has dependency activation)
- `ms-toolsai` — Jupyter notebook rendering breaks

**The fix:** use the full `publisher.extensionId` form for any extension with dependencies. See `vscode_extension_allowlist.json` in this repo for the working set.

Wildcards (`"ms-python.*"`) are **not supported**. Only the literal `"*"` for all-extensions allow/deny is valid.

## Deployment — on-prem Active Directory GPO

### 1. Copy templates to the Central Store

On a Domain Controller (PowerShell, elevated):

```powershell
$cs = "\\$env:USERDNSDOMAIN\SYSVOL\$env:USERDNSDOMAIN\Policies\PolicyDefinitions"
New-Item -Path $cs -ItemType Directory -Force | Out-Null
New-Item -Path "$cs\en-US" -ItemType Directory -Force | Out-Null

Copy-Item -Path ".\admx\vscode.admx"       -Destination $cs -Force
Copy-Item -Path ".\admx\vscode.adml" -Destination "$cs\en-US" -Force
```

### 2. Create and link the GPO

1. Open **Group Policy Management Console** (`gpmc.msc`)
2. Right-click the OU containing your VS Code endpoints → **Create a GPO in this domain, and Link it here**
3. Name: `VSCode - Allowed Extensions`
4. Right-click the new GPO → **Edit**

### 3. Configure the policy

Navigate to:

**Computer Configuration → Policies → Administrative Templates → Visual Studio Code → Extensions → Allow installation of specific extensions**

Set to **Enabled**. The textbox is pre-populated with the working allowlist from `vscode_extension_allowlist.json`. Edit only if adding/removing approved extensions.

![GPO editor configuring the AllowedExtensions policy](images/gpo-editor.png)

### 4. Apply and verify on a client

```powershell
gpupdate /target:computer /force

# Confirm the policy reached the registry
$v = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\VSCode' AllowedExtensions).AllowedExtensions
$v.Length
$v | ConvertFrom-Json   # Must parse cleanly; if this errors, GPO truncated the value
```

## Verification

### Approved extensions activate normally

After applying the policy and restarting VS Code, all extensions on the allowlist load and function as expected. Below: ten Microsoft-published extensions (Jupyter suite, PowerShell, Pylance, Python) all installed and active.

![VS Code Extensions panel showing all approved extensions installed and enabled](images/extensions-installed.png)

### Non-allowed extensions are blocked at the marketplace

Searching for a non-allowlisted extension (e.g., `nx`) shows the marketplace results with `Install` greyed out and a warning indicator. The Nx Console extension — the same one compromised in CVE-2026-48027 — cannot be installed under this policy regardless of version.

![Marketplace search for "nx" showing Nx Console with Install button blocked](images/nx-console-blocked.png)

## Maintenance

### Adding a new approved extension

1. Identify the full extension ID: `publisher.extensionId` (visible in the Marketplace URL: `marketplace.visualstudio.com/items?itemName=publisher.extensionId`)
2. Add it to `vscode_extension_allowlist.json` in this repo, commit
3. Open the GPO in GPME → edit the policy → paste the updated single-line JSON into the textbox
4. `gpupdate /force` on a pilot endpoint, restart VS Code, confirm the extension loads
5. Let GPO propagate to the rest of the fleet (default refresh: 90–120 min, or push immediately with a scheduled task)

### Updating the ADML default

If you want new GPOs created in the future to pre-populate with the latest allowlist, also update the `<defaultValue>` inside `admx/vscode.adml` to match, and re-copy to the Central Store. This does **not** retroactively change already-deployed GPOs (their value lives in `registry.pol`, not in the ADML).

### Common extension IDs

| Need | Extension ID |
|---|---|
| Bicep | `ms-azuretools.vscode-bicep` |
| C# Dev Kit | `ms-dotnettools.csharp`, `ms-dotnettools.csdevkit`, `ms-dotnettools.vscode-dotnet-runtime` |
| Remote-SSH | `ms-vscode-remote.remote-ssh`, `ms-vscode-remote.remote-ssh-edit` |
| C/C++ | `ms-vscode.cpptools`, `ms-vscode.cpptools-extension-pack` |
| Kubernetes | `ms-kubernetes-tools.vscode-kubernetes-tools` |
| KQL | `RoryPreddy.vscode-kusto-formatter` (third-party, evaluate before adding) |

## Alternative deployment — Intune

Use the included PowerShell Remediation package for cloud-managed endpoints: [intune/instructions.md](intune/instructions.md).

## Hunt query — detecting compromise from CVE-2026-48027

If a host had Nx Console v18.95.0 installed before this policy was deployed, the policy will block future loads but will **not** remove the persistence artifacts (cat.py Python backdoor, kitty LaunchAgent, /var/tmp/.gh_update_state). Use the MDE Advanced Hunting KQL maintained separately to identify already-compromised endpoints for credential rotation and cleanup.

Key indicators:
- File: `~/.local/share/kitty/cat.py`, `~/Library/LaunchAgents/com.user.kitty-monitor.plist`, `/var/tmp/.gh_update_state`
- Process: any command line containing `558b09d7ad0d1660e2a0fb8a06da81a6f42e06d2` or `github:nrwl/nx#558`
- Network: HTTPS to `api.github.com/search/commits?q=firedalazer`

## References

- [VS Code: Manage extensions in enterprise environments](https://code.visualstudio.com/docs/enterprise/extensions)
- [VS Code: Centrally manage settings with policies](https://code.visualstudio.com/docs/enterprise/policies)
- [Nx Console GHSA-c9j4-9m59-847w](https://github.com/nrwl/nx-console/security/advisories/GHSA-c9j4-9m59-847w) — original advisory
- [Nx postmortem](https://nx.dev/blog/nx-console-v18-95-0-postmortem)
- [StepSecurity threat intel writeup](https://www.stepsecurity.io/blog/nx-console-vs-code-extension-compromised)

## License

Internal use. Not for external distribution without review.
