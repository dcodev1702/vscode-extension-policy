# Central Store path (auto-replicates to all DCs via SYSVOL)
$cs = "\\$env:USERDNSDOMAIN\SYSVOL\$env:USERDNSDOMAIN\Policies\PolicyDefinitions"

# Create it if it doesn't exist yet (first-time setup)
New-Item -Path $cs -ItemType Directory -Force | Out-Null
New-Item -Path "$cs\en-US" -ItemType Directory -Force | Out-Null

# Copy the templates (adjust source paths to wherever you saved them)
Copy-Item -Path "C:\Temp\vscode.admx"       -Destination $cs
Copy-Item -Path "C:\Temp\en-US\vscode.adml" -Destination "$cs\en-US"

# Verify
Get-ChildItem $cs\vscode.admx, $cs\en-US\vscode.adml