param(
    [string]$Flutter = "flutter",
    [string]$TargetPlatforms = "android-arm,android-arm64,android-x64",
    [string]$OutputDirectory = "build/releases",
    [string]$BuildName = "",
    [string]$BuildNumber = "",
    [switch]$Force
)
$ErrorActionPreference = "Stop"
$workspaceRoot = Split-Path -Parent $PSScriptRoot

function Copy-EditionApk {
    param(
        [Parameter(Mandatory)][string]$SourceApk,
        [Parameter(Mandatory)][ValidateSet("production", "developer")][string]$Edition,
        [Parameter(Mandatory)][string]$DestinationDirectory,
        [switch]$Force
    )
    $apkName = if ($Edition -eq "production") { "CheckMate.apk" } else { "CheckMate-Dev.apk" }
    $destinationApk = Join-Path $DestinationDirectory $apkName
    Copy-Item -LiteralPath $SourceApk -Destination $destinationApk -Force:$Force -ErrorAction Stop
    return $destinationApk
}

Push-Location $workspaceRoot
try {
    & $Flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "Dependency setup failed" }
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $copiedApks = @()
    foreach ($edition in @("production", "developer")) {
        $buildArgs = @("build", "apk", "--release", "--flavor", $edition, "--target-platform", $TargetPlatforms, "--no-pub")
        if ($BuildName) { $buildArgs += @("--build-name", $BuildName) }
        if ($BuildNumber) { $buildArgs += @("--build-number", $BuildNumber) }
        & $Flutter @buildArgs
        if ($LASTEXITCODE -ne 0) { throw "The $edition build failed" }
        $sourceApk = Join-Path $workspaceRoot "build/app/outputs/flutter-apk/app-$edition-release.apk"
        $copiedApks += Copy-EditionApk -SourceApk $sourceApk -Edition $edition -DestinationDirectory $OutputDirectory -Force:$Force
    }
    $hashLines = foreach ($apkPath in $copiedApks) {
        $apkName = Split-Path -Leaf $apkPath
        $hash = Get-FileHash -LiteralPath $apkPath -Algorithm SHA256
        "$($hash.Hash.ToLowerInvariant())  $apkName"
    }
    $hashLines | Set-Content -LiteralPath (Join-Path $OutputDirectory "SHA256SUMS.txt") -Encoding ascii
    Write-Output "Both editions are ready in $OutputDirectory. Upload both APKs to the same GitHub release."
}
finally { Pop-Location }
