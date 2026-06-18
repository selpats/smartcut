# build_windows.ps1
# Build script for smartcut using MSYS2 MinGW Python
# Prioritizes running via modern pwsh (PowerShell 7+) or falls back to Windows PowerShell.

param(
    [switch]$Full
)

$ErrorActionPreference = "Stop"

$RootDir = (Get-Item "$PSScriptRoot/../..").FullName
Set-Location $RootDir

# --- 1. Set Default MSYS2 Directory ---
$MsysDir = "C:\msys64"

if (-not (Test-Path $MsysDir)) {
    Write-Error "[ERROR] MSYS2 installation not found at $MsysDir"
    Write-Host "Please install MSYS2 to C:\msys64 to use this build script."
    Read-Host "Press Enter to exit..."
    exit 1
}

Write-Host "[INFO] Using MSYS2 installation at: $MsysDir"

# Derive tool paths
$PythonPath = "$MsysDir\ucrt64\bin\python.exe"
$BashPath = "$MsysDir\usr\bin\bash.exe"
$UnixPath = $PWD.Path -replace '\\', '/'

# Verify MSYS2 Bash first
if (-not (Test-Path $BashPath)) {
    Write-Error "[ERROR] MSYS2 Bash shell not found at $BashPath"
    Write-Host "Please install MSYS2 to $MsysDir first."
    Read-Host "Press Enter to exit..."
    exit 1
}

# Auto-install UCRT64 Python if missing
if (-not (Test-Path $PythonPath)) {
    Write-Host "[INFO] UCRT64 Python not found. Installing Python and basic tools via pacman..."
    & $BashPath -lc "pacman -S --noconfirm --needed mingw-w64-ucrt-x86_64-python mingw-w64-ucrt-x86_64-python-pip"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[ERROR] Failed to install UCRT64 Python via pacman!"
        Read-Host "Press Enter to exit..."
        exit 1
    }
}

# Double check derived tools
if (-not (Test-Path $PythonPath)) {
    Write-Error "[ERROR] UCRT64 Python not found at $PythonPath even after installation attempt."
    Read-Host "Press Enter to exit..."
    exit 1
}

# --- 2. Build and Install Custom x265 and FFmpeg ---
$BuildX265 = $false
$BuildFfmpeg = $false

if ($Full) {
    Write-Host "[INFO] -Full flag passed. Forcing rebuild of x265 and FFmpeg..."
    $BuildX265 = $true
    $BuildFfmpeg = $true
} else {
    # Check if custom x265 is installed. It must be installed and must contain "jpsdr".
    Write-Host "[INFO] Checking if custom x265 (jpsdr build) is installed..."
    $x265Query = & $BashPath -lc "pacman -Qi mingw-w64-ucrt-x86_64-x265 2>/dev/null"
    if ($LASTEXITCODE -ne 0 -or ([string]$x265Query) -notmatch 'jpsdr') {
        Write-Host "[INFO] Custom x265 (jpsdr) is missing or standard version is installed. Will rebuild..."
        $BuildX265 = $true
    } else {
        Write-Host "[INFO] Custom x265 (jpsdr) is already installed."
    }

    # Check if custom FFmpeg is installed. It must be installed and must not contain "libplacebo" or "opus" dependencies.
    Write-Host "[INFO] Checking if custom FFmpeg is installed..."
    $ffmpegQuery = & $BashPath -lc "pacman -Qi mingw-w64-ucrt-x86_64-ffmpeg 2>/dev/null"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[INFO] FFmpeg is missing. Will rebuild..."
        $BuildFfmpeg = $true
    } else {
        if (([string]$ffmpegQuery) -match 'mingw-w64-ucrt-x86_64-opus' -or (([string]$ffmpegQuery) -match 'mingw-w64-ucrt-x86_64-libplacebo')) {
            Write-Host "[INFO] Standard (heavy) FFmpeg detected. Rebuilding custom minimal version..."
            $BuildFfmpeg = $true
        } else {
            Write-Host "[INFO] Custom minimal FFmpeg is already installed."
        }
    }
}

# If x265 is being rebuilt, we must rebuild FFmpeg as well to prevent ABI mismatch
if ($BuildX265) {
    $BuildFfmpeg = $true
}

if ($BuildX265 -or $BuildFfmpeg) {
    Write-Host "[INFO] Running full MSYS2 system upgrade (pacman -Syu) to ensure up-to-date toolchain..."
    & $BashPath -lc "pacman -Syu --noconfirm"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[ERROR] Failed to run system upgrade!"
        Read-Host "Press Enter to exit..."
        exit 1
    }

    Write-Host "[INFO] Ensuring MSYS2 UCRT64 compiler toolchain and patch utilities are installed..."
    & $BashPath -lc "pacman -S --noconfirm --needed mingw-w64-ucrt-x86_64-cc mingw-w64-ucrt-x86_64-binutils mingw-w64-ucrt-x86_64-nasm mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja patch git"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[ERROR] Failed to install compilation toolchain via pacman!"
        Read-Host "Press Enter to exit..."
        exit 1
    }
}

if ($BuildX265) {
    Write-Host "[INFO] Rebuilding custom x265..."
    $BuildDir = "build/mingw-w64-x265"
    if (Test-Path $BuildDir) {
        Remove-Item -Path $BuildDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null

    Write-Host "[INFO] Copying x265 packaging files from distribution directory..."
    Copy-Item -Path "$RootDir/distribution/msys2-packages/mingw-w64-x265/*" -Destination $BuildDir -Recurse -Force

    # Ensure line endings are LF for MSYS2 makepkg compatibility on Windows
    Get-ChildItem -Path $BuildDir -File | ForEach-Object {
        if ($_.Extension -ne ".zip") {
            $content = Get-Content -Raw -Path $_.FullName
            $content = $content -replace "`r`n", "`n"
            [IO.File]::WriteAllText($_.FullName, $content)
        }
    }

    # Download the specific tested version of x265 source
    $tag = "4.2.0.6"
    $zipUrl = "https://github.com/jpsdr/x265/archive/refs/tags/$tag.zip"
    Write-Host "[INFO] Downloading x265 source version $tag..."
    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile "$BuildDir/x265_source.zip"
    } catch {
        Write-Error "[ERROR] Failed to download x265 source: $_"
        Read-Host "Press Enter to exit..."
        exit 1
    }

    Write-Host "[INFO] Running makepkg-mingw to build custom x265..."
    $env:MSYSTEM = "UCRT64"
    $env:CHERE_INVOKING = 1
    $originalLocation = Get-Location
    try {
        Set-Location $BuildDir
        & $BashPath -lc "makepkg-mingw -s --noconfirm -f"
        if ($LASTEXITCODE -ne 0) {
            throw "makepkg-mingw failed with exit code $LASTEXITCODE"
        }
        
        Write-Host "[INFO] Installing the compiled x265 package..."
        & $BashPath -lc "pacman -U --noconfirm --overwrite '*' mingw-w64-ucrt-x86_64-x265-*.pkg.tar.zst"
        if ($LASTEXITCODE -ne 0) {
            throw "pacman failed with exit code $LASTEXITCODE"
        }
    } catch {
        Write-Error "[ERROR] Failed to compile or install custom x265: $_"
        Set-Location $originalLocation
        Read-Host "Press Enter to exit..."
        exit 1
    }
    Set-Location $originalLocation
} else {
    Write-Host "[INFO] Skipping x265 rebuild."
}

if ($BuildFfmpeg) {
    # --- 2b. Patch x265.h to include <stdbool.h> for C-compiler configure checks ---
    $x265Header = "$MsysDir\ucrt64\include\x265.h"
    if (Test-Path $x265Header) {
        Write-Host "[INFO] Verifying x265.h stdbool patch..."
        $content = Get-Content -Path $x265Header -Raw
        if ($content -notmatch '#include <stdbool.h>') {
            Write-Host "[INFO] Patching x265.h to include <stdbool.h>..."
            $content = $content -replace '#include <stdint.h>', "#include <stdint.h>`r`n#include <stdbool.h>"
            [IO.File]::WriteAllText($x265Header, $content)
        }
    }

    # --- 2c. Build and Install Custom FFmpeg ---
    Write-Host "[INFO] Setting up build directory for FFmpeg..."
    $FfmpegBuildDir = "build/mingw-w64-ffmpeg"
    if (Test-Path $FfmpegBuildDir) {
        Remove-Item -Path $FfmpegBuildDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $FfmpegBuildDir -Force | Out-Null
    Copy-Item -Path "$RootDir/distribution/msys2-packages/mingw-w64-ffmpeg/*" -Destination $FfmpegBuildDir -Recurse -Force

    # Ensure line endings are LF for MSYS2 makepkg compatibility on Windows
    Get-ChildItem -Path $FfmpegBuildDir -File | ForEach-Object {
        $content = Get-Content -Raw -Path $_.FullName
        $content = $content -replace "`r`n", "`n"
        [IO.File]::WriteAllText($_.FullName, $content)
    }

    $originalLocation = Get-Location
    try {
        Set-Location $FfmpegBuildDir
        Write-Host "[INFO] Running makepkg-mingw to build custom FFmpeg (minimal dependencies)..."
        & $BashPath -lc "export MAKEFLAGS='-j`$(nproc)' && makepkg-mingw -s --noconfirm -f --skippgpcheck"
        if ($LASTEXITCODE -ne 0) {
            throw "makepkg-mingw for ffmpeg failed with exit code $LASTEXITCODE"
        }
        
        Write-Host "[INFO] Installing the compiled FFmpeg package..."
        & $BashPath -lc "pacman -U --noconfirm --overwrite '*' mingw-w64-ucrt-x86_64-ffmpeg-*.pkg.tar.zst"
        if ($LASTEXITCODE -ne 0) {
            throw "pacman for ffmpeg failed with exit code $LASTEXITCODE"
        }
    } catch {
        Write-Error "[ERROR] Failed to compile or install custom FFmpeg: $_"
        Set-Location $originalLocation
        Read-Host "Press Enter to exit..."
        exit 1
    }
    Set-Location $originalLocation
} else {
    Write-Host "[INFO] Skipping FFmpeg rebuild."
}

# --- 3. Manage venv ---
$SetupVenv = $false
if ($Full) {
    if (Test-Path "venv") {
        Write-Host "[INFO] -Full flag passed. Forcing full clean rebuild (re-creating venv)..."
        Remove-Item -Path "venv" -Recurse -Force
    }
    $SetupVenv = $true
}
if (-not (Test-Path "venv/bin/python.exe")) { $SetupVenv = $true }

if ($SetupVenv) {
    Write-Host "[INFO] Ensuring MSYS2 UCRT64 system packages are installed..."
    & $BashPath -lc "pacman -S --noconfirm --needed mingw-w64-ucrt-x86_64-python mingw-w64-ucrt-x86_64-python-av mingw-w64-ucrt-x86_64-python-numpy mingw-w64-ucrt-x86_64-python-tqdm"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[ERROR] Failed to install MSYS2 dependencies via pacman!"
        Read-Host "Press Enter to exit..."
        exit 1
    }

    Write-Host "[INFO] Setting up virtual environment (venv)..."
    if (Test-Path "venv") {
        Write-Host "[INFO] venv already exists. Re-creating it..."
        Remove-Item -Path "venv" -Recurse -Force
    }

    & $PythonPath -m venv venv --system-site-packages
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[ERROR] Failed to create venv!"
        Read-Host "Press Enter to exit..."
        exit 1
    }

    Write-Host "[INFO] Installing PyInstaller and dependencies in venv..."
    $env:MSYSTEM = "UCRT64"
    $env:CHERE_INVOKING = 1
    & $BashPath -lc "cd '$UnixPath' && venv/bin/python.exe -m pip install pyinstaller"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[ERROR] Failed to install PyInstaller in venv!"
        Read-Host "Press Enter to exit..."
        exit 1
    }

    Write-Host "[INFO] Installing project package and dependencies..."
    & $BashPath -lc "cd '$UnixPath' && venv/bin/python.exe -m pip install -e ."
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[ERROR] Failed to install project dependencies in venv!"
        Read-Host "Press Enter to exit..."
        exit 1
    }
} else {
    Write-Host "[INFO] Re-using existing virtual environment venv."
}

# --- 4. Build smartcut ---
Write-Host "[INFO] Generating PyInstaller spec file..."
& $BashPath -lc "cd '$UnixPath' && venv/bin/pyi-makespec --onefile -n smartcut --hidden-import=uuid smartcut/__main__.py"
if ($LASTEXITCODE -ne 0) {
    Write-Error "[ERROR] Failed to generate spec file!"
    exit 1
}

$SpecPath = Join-Path $RootDir "smartcut.spec"
if (Test-Path $SpecPath) {
    Write-Host "[INFO] Modifying spec file to exclude UCRT DLLs..."
    $SpecContent = Get-Content -Path $SpecPath -Raw
    
    $ExclusionCode = "
# Exclude Universal CRT DLLs for Windows 10/11 compatibility (saves size)
a.binaries = [x for x in a.binaries if not (
    x[0].lower().startswith('api-ms-win') or 
    x[0].lower().startswith('ucrtbase')
)]

"
    $SpecContent = $SpecContent.Replace("excludes=[],", "excludes=['PIL'],")
    $SpecContent = $SpecContent.Replace("pyz = PYZ(a.pure)", $ExclusionCode + "pyz = PYZ(a.pure)")
    [IO.File]::WriteAllText($SpecPath, $SpecContent)
} else {
    Write-Error "[ERROR] smartcut.spec not found at $SpecPath after generation!"
    exit 1
}

Write-Host "[INFO] Compiling smartcut using the modified spec file..."
$env:MSYSTEM = "UCRT64"
$env:CHERE_INVOKING = 1
& $BashPath -lc "cd '$UnixPath' && venv/bin/python.exe -m PyInstaller -y smartcut.spec"

if ($LASTEXITCODE -eq 0) {
    Write-Host "[INFO] Build completed successfully!"
    Write-Host "[INFO] Output executable: dist\smartcut.exe"
} else {
    Write-Error "[ERROR] Build failed with exit code $LASTEXITCODE"
}
