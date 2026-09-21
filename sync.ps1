# success_list.txt -> list.json に変換し、変更があれば GitHub へ push する
param(
  [string]$Source = "H:\AI\cromead\success_list.txt",
  [switch]$NoPush
)
$ErrorActionPreference = "Stop"
$dir = $PSScriptRoot
if (-not (Test-Path $Source)) { Write-Output "not found: $Source"; exit 1 }

$items = @(Get-Content -Path $Source -Encoding UTF8 |
  ForEach-Object { $_.Trim([char]0xFEFF).Trim() } |
  Where-Object { $_ -ne "" })

$jsonPath = Join-Path $dir "list.json"
if (Test-Path $jsonPath) {
  $old = @((Get-Content -Path $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json).items)
  if ((($old -join "`n")) -ceq (($items -join "`n"))) { Write-Output "no change in list"; exit 0 }
}

$obj = [ordered]@{ updated = (Get-Date -Format "yyyy-MM-dd HH:mm"); items = $items }
$json = $obj | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText((Join-Path $dir "list.json"), $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("list.json updated: {0} items" -f $items.Count)

if ($NoPush) { exit 0 }
Set-Location $dir
if (-not (Test-Path ".git")) { Write-Output "git repo not set up; skip push"; exit 0 }
git add list.json
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) { Write-Output "no change"; exit 0 }
git commit -m ("update list " + (Get-Date -Format "yyyy-MM-dd"))
git push
