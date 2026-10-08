param(
    [string]$Flutter = "flutter",
    [string]$TargetPlatforms = "android-arm,android-arm64,android-x64",
    [string]$OutputDirectory = "build/releases",
    [string]$BuildName = "",
    [string]$BuildNumber = ""
)
$ErrorActionPreference = "Stop"
$workspaceRoot = Split-Path -Parent $PSScriptRoot
Push-Location $workspaceRoot
try {
    & $Flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "Dependency setup failed" }
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    foreach ($edition in @("production", "developer")) {
        $buildArgs = @("build", "apk", "--release", "--flavor", $edition, "--target-platform", $TargetPlatforms, "--no-pub")
        if ($BuildName) { $buildArgs += @("--build-name", $BuildName) }
        if ($BuildNumber) { $buildArgs += @("--build-number", $BuildNumber) }
        & $Flutter @buildArgs
        if ($LASTEXITCODE -ne 0) { throw "The $edition build failed" }
        $sourceApk = Join-Path $workspaceRoot "build/app/outputs/flutter-apk/app-$edition-release.apk"
        $editionLabel = if ($edition -eq "production") { "Production" } else { "Developer" }
        Copy-Item -LiteralPath $sourceApk -Destination (Join-Path $OutputDirectory "CheckMate-$editionLabel.apk") -Force
    }
    $hashLines = foreach ($apkName in @("CheckMate-Production.apk", "CheckMate-Developer.apk")) {
        $hash = Get-FileHash -LiteralPath (Join-Path $OutputDirectory $apkName) -Algorithm SHA256
        "$($hash.Hash.ToLowerInvariant())  $apkName"
    }
    $hashLines | Set-Content -LiteralPath (Join-Path $OutputDirectory "SHA256SUMS.txt") -Encoding ascii
    Write-Output "Both editions are ready in $OutputDirectory. Upload both APKs to the same GitHub release."
}
finally { Pop-Location }
