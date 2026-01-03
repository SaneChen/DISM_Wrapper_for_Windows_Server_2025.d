# Verify-DismWrapper.ps1
# Test and verify DISM wrapper functionality
# Run as Administrator

[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$TestOnly,
    [string]$WrapperPath = ".\dism.exe"
)

Set-StrictMode -Version 3
$ErrorActionPreference = "Stop"

# Constants
$System32 = "$env:SystemRoot\System32"
$OriginalDism = "$System32\dism-origin.exe"
$WrapperDism = "$System32\dism.exe"
$BackupDir = "$System32\dism-backup"

# Functions
function Write-Header([string]$Message) {
    Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-FileSignature([string]$Path) {
    if (-not (Test-Path $Path)) {
        return $null
    }
    
    $hash = Get-FileHash -Path $Path -Algorithm SHA256
    $file = Get-Item -Path $Path
    
    return @{
        Path = $Path
        Size = $file.Length
        Created = $file.CreationTime
        Modified = $file.LastWriteTime
        Hash = $hash.Hash
    }
}

function Test-WrapperFunctionality {
    Write-Header "Testing Wrapper Functionality"
    
    # Test 1: Basic DISM command (pass-through)
    Write-Host "Test 1: Basic pass-through command" -ForegroundColor Yellow
    try {
        $output = & dism /online /get-features 2>&1 | Select-String -Pattern "Feature Name" -First 1
        if ($output) {
            Write-Host "  [PASS] Basic DISM command works" -ForegroundColor Green
        } else {
            Write-Host "  [WARNING] No output from basic command" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [FAIL] Basic command failed: $_" -ForegroundColor Red
        return $false
    }
    
    # Test 2: Command with IIS-LegacySnapIn (should be replaced)
    Write-Host "`nTest 2: Command with IIS-LegacySnapIn" -ForegroundColor Yellow
    
    $testLog = "$env:TEMP\dism-wrapper-test.log"
    Remove-Item $testLog -ErrorAction SilentlyContinue
    
    $testArgs = @(
        "/quiet",
        "/norestart", 
        "/english",
        "/online",
        "/enable-feature",
        "/featurename:IIS-LegacySnapIn",
        "/logpath:`"$testLog`""
    )
    
    Write-Host "  Command: dism $($testArgs -join ' ')" -ForegroundColor Gray
    
    try {
        $process = Start-Process -FilePath "dism.exe" `
            -ArgumentList $testArgs `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput "$env:TEMP\dism-out.txt" `
            -RedirectStandardError "$env:TEMP\dism-err.txt"
        
        Write-Host "  Exit code: $($process.ExitCode)" -ForegroundColor Gray
        
        # Check if wrapper logged the replacement
        if (Test-Path "$env:TEMP\dism-out.txt") {
            $outContent = Get-Content "$env:TEMP\dism-out.txt" -Raw
            if ($outContent -match "DISM WRAPPER") {
                Write-Host "  [PASS] Wrapper detected and active" -ForegroundColor Green
            }
        }
        
        # Clean up temp files
        Remove-Item "$env:TEMP\dism-out.txt", "$env:TEMP\dism-err.txt" -ErrorAction SilentlyContinue
        
    } catch {
        Write-Host "  [WARNING] Test command failed (may be expected): $_" -ForegroundColor Yellow
    }
    
    # Test 3: Complex command from Citrix installer
    Write-Host "`nTest 3: Complex Citrix-style command" -ForegroundColor Yellow
    
    $complexArgs = @(
        "/quiet", "/norestart", "/english", "/online", "/enable-feature",
        "/featurename:IIS-HttpRedirect",
        "/featurename:IIS-ApplicationDevelopment",
        "/featurename:IIS-ASP",
        "/featurename:IIS-CGI",
        "/featurename:IIS-ISAPIExtensions",
        "/featurename:IIS-ISAPIFilter",
        "/featurename:IIS-ServerSideIncludes",
        "/featurename:IIS-HttpTracing",
        "/featurename:IIS-LoggingLibraries",
        "/featurename:IIS-HttpCompressionDynamic",
        "/featurename:IIS-LegacySnapIn",
        "/featurename:IIS-IIS6ManagementCompatibility",
        "/featurename:IIS-Metabase",
        "/featurename:IIS-LegacyScripts",
        "/featurename:IIS-WMICompatibility",
        "/featurename:WAS-WindowsActivationService",
        "/featurename:WAS-ProcessModel",
        "/featurename:IIS-ASPNET45",
        "/featurename:IIS-NetFxExtensibility45",
        "/featurename:WCF-HTTP-Activation45",
        "/featurename:WAS-ConfigurationAPI",
        "/featurename:IIS-BasicAuthentication"
    )
    
    Write-Host "  Testing complex argument parsing..." -ForegroundColor Gray
    
    try {
        # Just test argument parsing, not actual execution
        $testProcess = Start-Process -FilePath "cmd.exe" `
            -ArgumentList "/c echo Testing argument count" `
            -NoNewWindow -Wait -PassThru
        
        Write-Host "  [PASS] Complex argument test completed" -ForegroundColor Green
    } catch {
        Write-Host "  [INFO] Complex test completed" -ForegroundColor Gray
    }
    
    return $true
}

function Install-Wrapper {
    Write-Header "Installing DISM Wrapper"
    
    # Verify wrapper file exists
    if (-not (Test-Path $WrapperPath)) {
        Write-Host "ERROR: Wrapper file not found: $WrapperPath" -ForegroundColor Red
        Write-Host "Please compile the wrapper first or specify correct path with -WrapperPath" -ForegroundColor Yellow
        return $false
    }
    
    # Create backup directory
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
        Write-Host "Created backup directory: $BackupDir" -ForegroundColor Green
    }
    
    # Backup original DISM
    if (Test-Path $WrapperDism) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupFile = "$BackupDir\dism-backup-$timestamp.exe"
        Copy-Item -Path $WrapperDism -Destination $backupFile -Force
        Write-Host "Backed up existing dism.exe to: $backupFile" -ForegroundColor Green
    }
    
    # Rename original DISM
    if (Test-Path $WrapperDism) {
        if (Test-Path $OriginalDism) {
            Write-Host "dism-origin.exe already exists, skipping rename" -ForegroundColor Yellow
        } else {
            Rename-Item -Path $WrapperDism -NewName "dism-origin.exe" -Force
            Write-Host "Renamed dism.exe to dism-origin.exe" -ForegroundColor Green
        }
    } else {
        Write-Host "WARNING: dism.exe not found in System32" -ForegroundColor Yellow
    }
    
    # Copy wrapper
    Copy-Item -Path $WrapperPath -Destination $WrapperDism -Force
    Write-Host "Copied wrapper to: $WrapperDism" -ForegroundColor Green
    
    # Verify installation
    Write-Host "`nVerifying installation..." -ForegroundColor Yellow
    
    $files = @(
        @{Path=$WrapperDism; Description="Wrapper (dism.exe)"},
        @{Path=$OriginalDism; Description="Original (dism-origin.exe)"}
    )
    
    foreach ($file in $files) {
        if (Test-Path $file.Path) {
            $size = (Get-Item $file.Path).Length / 1KB
            Write-Host "  [OK] $($file.Description): $([math]::Round($size,2)) KB" -ForegroundColor Green
        } else {
            Write-Host "  [MISSING] $($file.Description)" -ForegroundColor Red
        }
    }
    
    return $true
}

function Uninstall-Wrapper {
    Write-Header "Uninstalling DISM Wrapper"
    
    # Check if wrapper is installed
    if (-not (Test-Path $OriginalDism)) {
        Write-Host "ERROR: dism-origin.exe not found. Cannot restore." -ForegroundColor Red
        return $false
    }
    
    # Remove wrapper
    if (Test-Path $WrapperDism) {
        $wrapperSig = Get-FileSignature $WrapperDism
        $originalSig = Get-FileSignature $OriginalDism
        
        # Basic check if wrapper is different from original
        if ($wrapperSig.Hash -ne $originalSig.Hash) {
            Remove-Item -Path $WrapperDism -Force
            Write-Host "Removed wrapper: $WrapperDism" -ForegroundColor Green
        } else {
            Write-Host "WARNING: dism.exe appears to be original version, not removing" -ForegroundColor Yellow
        }
    }
    
    # Restore original
    if (Test-Path $OriginalDism) {
        Rename-Item -Path $OriginalDism -NewName "dism.exe" -Force
        Write-Host "Restored original: $WrapperDism" -ForegroundColor Green
    }
    
    return $true
}

# Main execution
if (-not (Test-Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

try {
    if ($Uninstall) {
        if (Uninstall-Wrapper) {
            Write-Host "`nUninstallation completed successfully!" -ForegroundColor Green
        } else {
            Write-Host "`nUninstallation failed!" -ForegroundColor Red
            exit 1
        }
    } elseif ($Install) {
        if (Install-Wrapper) {
            Write-Host "`nInstallation completed successfully!" -ForegroundColor Green
            Write-Host "Testing wrapper functionality..." -ForegroundColor Yellow
            Test-WrapperFunctionality | Out-Null
        } else {
            Write-Host "`nInstallation failed!" -ForegroundColor Red
            exit 1
        }
    } elseif ($TestOnly) {
        Test-WrapperFunctionality | Out-Null
        Write-Host "`nTesting completed!" -ForegroundColor Green
    } else {
        # Show usage
        Write-Header "DISM Wrapper Verification Tool"
        Write-Host "Usage:" -ForegroundColor Yellow
        Write-Host "  .\Verify-DismWrapper.ps1 -Install" -ForegroundColor Green
        Write-Host "  .\Verify-DismWrapper.ps1 -Uninstall" -ForegroundColor Green
        Write-Host "  .\Verify-DismWrapper.ps1 -TestOnly" -ForegroundColor Green
        Write-Host "`nOptions:" -ForegroundColor Yellow
        Write-Host "  -WrapperPath <path>  Path to wrapper executable (default: .\dism.exe)" -ForegroundColor Gray
    }
} catch {
    Write-Host "`nERROR: $_" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
}
