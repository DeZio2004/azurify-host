# Run from this folder: uploads AZURIFY Host to https://github.com/DeZio2004/azurify-host
Set-Location $PSScriptRoot
if (-not (Test-Path .git)) { git init -b main }
git config user.name "AZURIFY"; git config user.email "dezihacker2004@gmail.com"
if (-not (git remote)) { git remote add origin https://github.com/DeZio2004/azurify-host.git }
git add -A
git commit -m "AZURIFY Host update" 2>$null
git push -u origin main
