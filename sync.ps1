# success_list.txt -> list.json（合言葉で暗号化）に変換し、変更があれば GitHub へ push する
# 合言葉は同じフォルダの passphrase.txt（git 管理外）に1行で書いておく
param(
  [string]$Source = "H:\AI\cromead\success_list.txt",
  [string]$PassFile = (Join-Path $PSScriptRoot "passphrase.txt"),
  [switch]$NoPush
)
$ErrorActionPreference = "Stop"
$dir = $PSScriptRoot
if (-not (Test-Path $Source)) { Write-Output "not found: $Source"; exit 1 }
if (-not (Test-Path $PassFile)) { Write-Output "passphrase not found: $PassFile"; exit 1 }
$pass = (Get-Content -Path $PassFile -Raw -Encoding UTF8).Trim([char]0xFEFF).Trim()
if (-not $pass) { Write-Output "passphrase is empty"; exit 1 }

$items = @(Get-Content -Path $Source -Encoding UTF8 |
  ForEach-Object { $_.Trim([char]0xFEFF).Trim() } |
  Where-Object { $_ -ne "" })

# 暗号文は毎回変わるので、平文のハッシュで変更を判定する
$utf8 = New-Object System.Text.UTF8Encoding($false)
$sha = [System.Security.Cryptography.SHA256]::Create()
$hash = [Convert]::ToBase64String($sha.ComputeHash($utf8.GetBytes(($items -join "`n") + "`n" + $pass)))
$statePath = Join-Path $dir ".sync_state"
if ((Test-Path $statePath) -and ((Get-Content -Path $statePath -Raw).Trim() -ceq $hash)) { Write-Output "no change in list"; exit 0 }

$obj = [ordered]@{ updated = (Get-Date -Format "yyyy-MM-dd HH:mm"); items = $items }
$plain = $utf8.GetBytes(($obj | ConvertTo-Json -Depth 3 -Compress))

# PBKDF2-SHA256 で 64 バイト（前半: AES-256 鍵 / 後半: HMAC 鍵）
$iter = 310000
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$salt = New-Object byte[] 16; $rng.GetBytes($salt)
$iv = New-Object byte[] 16; $rng.GetBytes($iv)
$kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($pass, $salt, $iter, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
$keys = $kdf.GetBytes(64)
$aes = [System.Security.Cryptography.Aes]::Create()
$aes.Mode = "CBC"; $aes.Padding = "PKCS7"; $aes.Key = $keys[0..31]; $aes.IV = $iv
$ct = $aes.CreateEncryptor().TransformFinalBlock($plain, 0, $plain.Length)
$hmac = New-Object System.Security.Cryptography.HMACSHA256(, [byte[]]$keys[32..63])
$mac = $hmac.ComputeHash([byte[]]($iv + $ct))

$b64 = { param($b) [Convert]::ToBase64String([byte[]]$b) }
$out = [ordered]@{ v = 1; iter = $iter; salt = (& $b64 $salt); iv = (& $b64 $iv); ct = (& $b64 $ct); mac = (& $b64 $mac) }
[System.IO.File]::WriteAllText((Join-Path $dir "list.json"), ($out | ConvertTo-Json), $utf8)
[System.IO.File]::WriteAllText($statePath, $hash, $utf8)
Write-Output ("list.json updated (encrypted): {0} items" -f $items.Count)

if ($NoPush) { exit 0 }
Set-Location $dir
if (-not (Test-Path ".git")) { Write-Output "git repo not set up; skip push"; exit 0 }
git add list.json
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) { Write-Output "no change"; exit 0 }
git commit -m ("update list " + (Get-Date -Format "yyyy-MM-dd"))
git push
