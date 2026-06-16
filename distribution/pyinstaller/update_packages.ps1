# update_packages.ps1
# Script to check and update PKGBUILD recipes for x265 and FFmpeg

$ErrorActionPreference = "Stop"

$x265PkgbuildPath = "$PSScriptRoot/../msys2-packages/mingw-w64-x265/PKGBUILD"
$ffmpegPkgbuildPath = "$PSScriptRoot/../msys2-packages/mingw-w64-ffmpeg/PKGBUILD"
$buildScriptPath = "$PSScriptRoot/build_windows.ps1"

Write-Host "=== Checking for updates ==="

# --- 1. Check x265 (JPSDR fork) ---
if (Test-Path $x265PkgbuildPath) {
    $currentX265Ver = ""
    $pkgbuildContent = Get-Content -Path $x265PkgbuildPath -Raw
    if ($pkgbuildContent -match 'pkgver=([0-9\.]+)') {
        $currentX265Ver = $Matches[1]
    }
    
    Write-Host "[INFO] Current local x265 version: $currentX265Ver"
    Write-Host "[INFO] Fetching latest x265 release tag from JPSDR repository..."
    try {
        $html = (Invoke-WebRequest -Uri 'https://github.com/jpsdr/x265/tags' -UseBasicParsing).Content
        if ($html -match '/jpsdr/x265/releases/tag/([0-9\.]+)') {
            $latestX265Ver = $Matches[1]
            Write-Host "[INFO] Latest JPSDR release tag: $latestX265Ver"
            
            if ($latestX265Ver -ne $currentX265Ver) {
                Write-Host "[UPDATE] New x265 version available! Updating local files..." -ForegroundColor Green
                
                # Update PKGBUILD
                $pkgbuildContent = $pkgbuildContent -replace 'pkgver=[0-9\.]+', "pkgver=$latestX265Ver"
                [IO.File]::WriteAllText($x265PkgbuildPath, $pkgbuildContent)
                Write-Host "[SUCCESS] Updated x265 PKGBUILD version to $latestX265Ver"
                
                # Update build_windows.ps1
                if (Test-Path $buildScriptPath) {
                    $buildScriptContent = Get-Content -Path $buildScriptPath -Raw
                    $buildScriptContent = $buildScriptContent -replace '\$tag = "[0-9\.]+"', "`$tag = `"$latestX265Ver`""
                    [IO.File]::WriteAllText($buildScriptPath, $buildScriptContent)
                    Write-Host "[SUCCESS] Updated build_windows.ps1 x265 tag to $latestX265Ver"
                }
            } else {
                Write-Host "[INFO] x265 is up to date."
            }
        } else {
            Write-Warning "Could not parse latest release tag from JPSDR HTML."
        }
    } catch {
        Write-Warning "Failed to check latest x265 version: $_"
    }
} else {
    Write-Error "x265 PKGBUILD not found at $x265PkgbuildPath"
}

# --- 2. Check FFmpeg (MSYS2 official package version) ---
if (Test-Path $ffmpegPkgbuildPath) {
    $currentFfmpegVer = ""
    $ffmpegPkgbuildContent = Get-Content -Path $ffmpegPkgbuildPath -Raw
    if ($ffmpegPkgbuildContent -match 'pkgver=([0-9\.]+)') {
        $currentFfmpegVer = $Matches[1]
    }
    
    Write-Host ""
    Write-Host "[INFO] Current local FFmpeg version: $currentFfmpegVer"
    Write-Host "[INFO] Checking latest FFmpeg package version from MSYS2 repository..."
    try {
        $officialPkgbuildUrl = "https://raw.githubusercontent.com/msys2/MINGW-packages/master/mingw-w64-ffmpeg/PKGBUILD"
        $officialPkgbuild = (Invoke-WebRequest -Uri $officialPkgbuildUrl -UseBasicParsing).Content
        if ($officialPkgbuild -match 'pkgver=([0-9\.]+)') {
            $latestFfmpegVer = $Matches[1]
            Write-Host "[INFO] Latest MSYS2 FFmpeg package version: $latestFfmpegVer"
            
            if ($latestFfmpegVer -ne $currentFfmpegVer) {
                Write-Host "[UPDATE] New FFmpeg version available! Updating local files..." -ForegroundColor Green
                
                # Fetch the corresponding sha256sum for the source archive from the official PKGBUILD
                $latestFfmpegHash = ""
                if ($officialPkgbuild -match "sha256sums=\(\s*'([a-f0-9]{64})'") {
                    $latestFfmpegHash = $Matches[1]
                }
                
                if (-not $latestFfmpegHash) {
                    Write-Warning "Could not parse latest FFmpeg source sha256sum. Will default to 'SKIP' for the tarball."
                    $latestFfmpegHash = "SKIP"
                }
                
                # Update PKGBUILD
                $ffmpegPkgbuildContent = $ffmpegPkgbuildContent -replace 'pkgver=[0-9\.]+', "pkgver=$latestFfmpegVer"
                $ffmpegPkgbuildContent = $ffmpegPkgbuildContent -replace 'pkgrel=[0-9]+', "pkgrel=1"
                $ffmpegPkgbuildContent = $ffmpegPkgbuildContent -replace "sha256sums=\(\s*'([a-f0-9]{64}|SKIP)'", "sha256sums=('$latestFfmpegHash'"
                [IO.File]::WriteAllText($ffmpegPkgbuildPath, $ffmpegPkgbuildContent)
                
                Write-Host "[SUCCESS] Updated FFmpeg PKGBUILD version to $latestFfmpegVer and source hash to $latestFfmpegHash"
                Write-Host "[INFO] Note: Custom FFmpeg is minimal for smartcut. If compilation fails, check if patches need updating."
            } else {
                Write-Host "[INFO] FFmpeg package version is up to date with MSYS2."
            }
        } else {
            Write-Warning "Could not parse latest FFmpeg version from MSYS2 PKGBUILD."
        }
    } catch {
        Write-Warning "Failed to check latest FFmpeg version: $_"
    }
} else {
    Write-Error "FFmpeg PKGBUILD not found at $ffmpegPkgbuildPath"
}
