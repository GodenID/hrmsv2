<#
.SYNOPSIS
    Terbitkan APK Android baru agar aplikasi memperbarui diri otomatis.

.DESCRIPTION
    Alur: login superadmin -> minta presigned PUT -> unggah APK ke S3 ->
    catat rilis di server. Setelah ini, setiap karyawan yang membuka aplikasi
    akan ditawari (atau dipaksa memasang, bila minVersionCode dinaikkan)
    pembaruan tanpa perlu dikirimi berkas satu per satu.

    Naikkan `version: x.y.z+N` di pubspec.yaml sebelum build. N harus selalu
    bertambah dan APK harus ditandatangani keystore yang sama.

.EXAMPLE
    .\tool\publish_release.ps1 `
      -BaseUrl https://apihrms.prasastigroup.id `
      -Username admin `
      -Apk .\build\app\outputs\flutter-apk\app-release.apk `
      -VersionCode 2 -VersionName 1.0.1 `
      -Notes "Perbaikan absensi dan notifikasi."

    Tambahkan -MinVersionCode 2 untuk memaksa semua pengguna versi lama
    memperbarui sebelum bisa memakai aplikasi.
#>
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$Username,
    [Parameter(Mandatory = $true)][string]$Password,
    [Parameter(Mandatory = $true)][string]$Apk,
    [Parameter(Mandatory = $true)][int]$VersionCode,
    [Parameter(Mandatory = $true)][string]$VersionName,
    [int]$MinVersionCode = 0,
    [string]$Notes = ""
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$base = $BaseUrl.TrimEnd('/')
$file = Get-Item -LiteralPath $Apk
if ($file.Extension -ne '.apk') {
    throw "Berkas harus .apk: $($file.FullName)"
}
if ($VersionCode -le 0) {
    throw 'VersionCode harus bilangan bulat positif.'
}

Write-Host "1/4 Masuk sebagai $Username..."
$loginBody = @{ username = $Username; password = $Password } | ConvertTo-Json
$login = Invoke-RestMethod -Method Post -Uri "$base/auth/login" `
    -ContentType 'application/json' -Body $loginBody
$token = $login.token
if (-not $token) { throw 'Login gagal: token tidak diterima.' }
$headers = @{ authorization = "Bearer $token" }

Write-Host "2/4 Menghitung SHA-256..."
$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()

Write-Host "3/4 Mengunggah $([math]::Round($file.Length / 1MB, 1)) MB..."
$presignBody = @{
    purpose  = 'apk'
    filename = $file.Name
    size     = [int64]$file.Length
} | ConvertTo-Json
$presign = Invoke-RestMethod -Method Post -Uri "$base/uploads/presign" `
    -Headers $headers -ContentType 'application/json' -Body $presignBody
Invoke-WebRequest -Method Put -Uri $presign.putUrl -InFile $file.FullName `
    -ContentType 'application/vnd.android.package-archive' | Out-Null

Write-Host "4/4 Menerbitkan versi..."
$releaseBody = @{
    versionCode    = $VersionCode
    versionName    = $VersionName
    minVersionCode = $MinVersionCode
    apkKey         = $presign.key
    sha256         = $sha
    notes          = $Notes
} | ConvertTo-Json
$release = Invoke-RestMethod -Method Post -Uri "$base/app/releases" `
    -Headers $headers -ContentType 'application/json' -Body $releaseBody

Write-Host "Selesai: v$($release.versionName) (build $($release.versionCode)), " `
    "$([math]::Round($release.sizeBytes / 1MB, 1)) MB."
