## Run (Windows 11 25H2 Pro cleanup)

This repo includes a PowerShell cleanup script (`win11-cleanup.ps1`) to remove common preinstalled apps and disable consumer features (Copilot/Widgets/etc.) safely.

### Requirements
- Windows 11
- PowerShell
- Administrator privileges

---

## Option A (Recommended): Run the `.ps1` directly

1) Open **PowerShell as Administrator**
   - Press `Win` → type **PowerShell**
   - Right click → **Run as administrator**

2) Go to the folder where the script is located (example: Desktop)

```powershell
cd $env:USERPROFILE\Desktop
