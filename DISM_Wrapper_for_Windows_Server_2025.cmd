@echo off
:: ============================================================================
:: DismWrapperDeploy.cmd - DISM Wrapper Deployment Tool v2.6
:: 
:: Professional deployment tool for DISM wrapper to resolve IIS-LegacySnapIn
:: compatibility issues on Windows Server 2025.
::
:: Fixed issues in v2.6:
::   1. Fixed variable expansion in banner display
::   2. Fixed menu selection handling (proper delayed expansion)
::   3. Improved TrustedInstaller permission handling
::   4. Enhanced error recovery and logging
::   5. Proper exit codes and status reporting
::
:: Key Features:
::   1. Robust auto-elevation with UAC prompt (multiple methods)
::   2. Interactive menu when launched without parameters
::   3. /replace - Deploy wrapper to replace IIS-LegacySnapIn
::   4. /restore - Restore original DISM configuration
::   5. Proper handling of TrustedInstaller file permissions (takeown + icacls)
::   6. Case-sensitive handling (Dism.exe vs dism.exe)
::   7. Comprehensive error handling and logging
::   8. Backup and restore functionality
::   9. System requirements verification
::
:: Usage:
::   DismWrapperDeploy.cmd                  (interactive menu)
::   DismWrapperDeploy.cmd /replace         (deploy wrapper)
::   DismWrapperDeploy.cmd /restore         (restore original)
::   DismWrapperDeploy.cmd /verify          (verify configuration)
::   DismWrapperDeploy.cmd /check           (check requirements)
::   DismWrapperDeploy.cmd /help            (show help)
::   DismWrapperDeploy.cmd /version         (show version)
::
:: Note: Script will auto-elevate if not running as Administrator
:: ============================================================================

setlocal enabledelayedexpansion

:: ============================================================================
:: Configuration
:: ============================================================================
set "SCRIPT_NAME=%~nx0"
set "SCRIPT_VERSION=2.6"
set "SCRIPT_DATE=2024-01-03"
set "SCRIPT_AUTHOR=System Administrator"

:: Store version in a standard environment variable for reliable access
set VERSION_DISPLAY=v%SCRIPT_VERSION%

:: Paths - assuming script is in same directory as build folder
set "SYSTEM32=%SystemRoot%\System32"
set "DISM_ORIGINAL=%SYSTEM32%\Dism.exe"
set "DISM_ORIGIN=%SYSTEM32%\dism-origin.exe"
set "DISM_BACKUP_DIR=%SYSTEM32%\DismBackup"
set "BUILD_DIR=%~dp0build"
set "WRAPPER_SOURCE=%BUILD_DIR%\Dism.exe"

:: Log file for debugging (optional)
set "LOG_FILE=%TEMP%\DismWrapperDeploy_%USERNAME%_%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%.log"

:: ============================================================================
:: Initialize and check admin privileges
:: ============================================================================
cls

:: Clear any existing choice variable
set "MENU_CHOICE="

:: First, check if we need to elevate
call :check_elevation

if !IS_ELEVATED! equ 0 (
    :: Not running as admin, need to elevate
    echo.
    echo ============================================================================
    echo   ADMINISTRATOR PRIVILEGES REQUIRED
    echo ============================================================================
    echo.
    echo This script requires Administrator privileges to modify system files.
    echo.
    echo Press any key to request elevation via UAC...
    pause > nul
    echo.
    echo Requesting elevation...
    
    :: If no arguments, we're in interactive mode
    if "%~1"=="" (
        call :elevate_script /menu
    ) else (
        call :elevate_script %*
    )
    
    :: Exit the non-elevated instance
    exit /b !ERRORLEVEL!
)

:: Now running with admin privileges
echo [SUCCESS] Running with Administrator privileges.
echo.

:: ============================================================================
:: Main logic - parse command line arguments
:: ============================================================================
if "%~1"=="" (
    call :interactive_menu
    goto :end_script
) else if "%~1"=="/replace" (
    call :deploy_wrapper
    goto :end_script
) else if "%~1"=="/restore" (
    call :restore_original
    goto :end_script
) else if "%~1"=="/menu" (
    call :interactive_menu
    goto :end_script
) else if "%~1"=="/verify" (
    call :verify_configuration
    goto :end_script
) else if "%~1"=="/check" (
    call :check_requirements
    goto :end_script
) else if "%~1"=="/help" (
    call :show_help
    goto :end_script
) else if "%~1"=="/version" (
    call :show_version
    goto :end_script
) else if "%~1"=="/?" (
    call :show_help
    goto :end_script
) else (
    echo [ERROR] Invalid argument: %~1
    echo.
    call :show_help
    goto :end_script
)

:: ============================================================================
:: Function: Print banner
:: ============================================================================
:print_banner
    echo ============================================================================
    echo   DISM WRAPPER DEPLOYMENT TOOL v%SCRIPT_VERSION%
    echo ============================================================================
    echo   For Windows Server 2025 IIS-LegacySnapIn Compatibility
    echo ============================================================================
    echo.
goto :eof

:: ============================================================================
:: Function: Print header
:: ============================================================================
:print_header
    echo ============================================================================
    echo   %~1
    echo ============================================================================
    echo.
goto :eof

:: ============================================================================
:: Function: Check if running with admin privileges
:: ============================================================================
:check_elevation
    set "IS_ELEVATED=0"
    
    :: Method 1: Check for Admin group membership
    net session >nul 2>&1
    if %ERRORLEVEL% equ 0 set "IS_ELEVATED=1"
    
    :: Method 2: Check using fltmc (filter manager control)
    if !IS_ELEVATED! equ 0 (
        fltmc >nul 2>&1
        if %ERRORLEVEL% equ 0 set "IS_ELEVATED=1"
    )
    
    :: Method 3: Try to create a file in System32
    if !IS_ELEVATED! equ 0 (
        echo > "%SystemRoot%\System32\test_elevation_%RANDOM%.tmp" 2>nul
        if exist "%SystemRoot%\System32\test_elevation_%RANDOM%.tmp" (
            del "%SystemRoot%\System32\test_elevation_%RANDOM%.tmp" >nul 2>&1
            set "IS_ELEVATED=1"
        )
    )
    
    echo [DEBUG] Elevation check: !IS_ELEVATED! (0=user, 1=admin) >nul
goto :eof

:: ============================================================================
:: Function: Elevate script with UAC prompt
:: ============================================================================
:elevate_script
    set "ELEVATE_ARGS=%*"
    
    :: Method 1: PowerShell (most reliable on Windows 8+)
    set "PS_SCRIPT=%TEMP%\elevate_%RANDOM%.ps1"
    
    echo ^$args = '!ELEVATE_ARGS!' > "!PS_SCRIPT!"
    echo ^$proc = Start-Process -FilePath '%~f0' -ArgumentList ^$args -Verb RunAs -Wait -PassThru >> "!PS_SCRIPT!"
    echo exit ^$proc.ExitCode >> "!PS_SCRIPT!"
    
    powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "!PS_SCRIPT!"
    set "PS_RESULT=%ERRORLEVEL%"
    
    if exist "!PS_SCRIPT!" del "!PS_SCRIPT!" >nul 2>&1
    
    if !PS_RESULT! equ 0 (
        exit /b 0
    )
    
    :: Method 2: VBScript (compatibility with older Windows)
    set "VBS_SCRIPT=%TEMP%\elevate_%RANDOM%.vbs"
    
    echo Set UAC = CreateObject^("Shell.Application"^) > "!VBS_SCRIPT!"
    echo UAC.ShellExecute "%~f0", "!ELEVATE_ARGS!", "", "runas", 1 >> "!VBS_SCRIPT!"
    
    cscript //nologo "!VBS_SCRIPT!" >nul 2>&1
    set "VBS_RESULT=%ERRORLEVEL%"
    
    if exist "!VBS_SCRIPT!" del "!VBS_SCRIPT!" >nul 2>&1
    
    timeout /t 2 /nobreak >nul
    
    if !VBS_RESULT! equ 0 (
        exit /b 0
    )
    
    :: Method 3: Manual instructions
    echo.
    echo ============================================================================
    echo   MANUAL ELEVATION REQUIRED
    echo ============================================================================
    echo.
    echo Automatic elevation failed. Please run this script manually as Administrator:
    echo.
    echo Method 1: Right-click and "Run as administrator"
    echo   1. Right-click on "!SCRIPT_NAME!"
    echo   2. Select "Run as administrator"
    echo   3. Click "Yes" in the UAC prompt
    echo.
    echo Method 2: Command Prompt
    echo   1. Open Command Prompt as Administrator
    echo   2. Navigate to: %~dp0
    echo   3. Run: "!SCRIPT_NAME!" !ELEVATE_ARGS!
    echo.
    echo Press any key to exit...
    pause > nul
    
    exit /b 1
goto :eof

:: ============================================================================
:: Function: Interactive Menu (FIXED - Proper delayed expansion handling)
:: ============================================================================
:interactive_menu
    :menu_start
    cls
    call :print_banner
    
    echo ============================================================================
    echo   INTERACTIVE MENU
    echo ============================================================================
    echo.
    echo Current user: %USERNAME%
    echo Computer: %COMPUTERNAME%
    echo Windows version:
    ver | findstr /i "Microsoft"
    echo.
    
    echo Please select an option:
    echo.
    echo   1. Deploy DISM Wrapper (replace IIS-LegacySnapIn)
    echo   2. Restore Original DISM
    echo   3. Verify Current Configuration
    echo   4. Check System Requirements
    echo   5. Show Help
    echo   6. Show Version Information
    echo   0. Exit
    echo.
    
    :: Clear previous choice
    set "MENU_CHOICE="
    
    :: Get user input - use plain variable assignment
    set /p "MENU_CHOICE=Enter your choice (0-6): "
    
    :: Clean up the input - remove any surrounding quotes or spaces
    if defined MENU_CHOICE (
        :: Remove quotes if present
        set "MENU_CHOICE=!MENU_CHOICE:"=!"
        :: Remove leading/trailing spaces
        for /f "tokens=* delims= " %%a in ("!MENU_CHOICE!") do set "MENU_CHOICE=%%a"
    )
    
    :: Check the choice - use proper delayed expansion
    if "!MENU_CHOICE!"=="1" (
        call :deploy_wrapper
        call :pause_and_return
        goto :menu_start
    ) else if "!MENU_CHOICE!"=="2" (
        call :restore_original
        call :pause_and_return
        goto :menu_start
    ) else if "!MENU_CHOICE!"=="3" (
        call :verify_configuration
        call :pause_and_return
        goto :menu_start
    ) else if "!MENU_CHOICE!"=="4" (
        call :check_requirements
        call :pause_and_return
        goto :menu_start
    ) else if "!MENU_CHOICE!"=="5" (
        call :show_help
        call :pause_and_return
        goto :menu_start
    ) else if "!MENU_CHOICE!"=="6" (
        call :show_version
        call :pause_and_return
        goto :menu_start
    ) else if "!MENU_CHOICE!"=="0" (
        goto :end_script
    ) else (
        echo.
        echo [ERROR] Invalid choice: "!MENU_CHOICE!". Please enter a number between 0 and 6.
        echo.
        timeout /t 2 /nobreak >nul
        goto :menu_start
    )
goto :eof

:: ============================================================================
:: Function: Deploy DISM wrapper (Complete version with TrustedInstaller handling)
:: ============================================================================
:deploy_wrapper
    cls
    call :print_header "DEPLOY DISM WRAPPER"
    
    :: Step 1: Verify preconditions
    echo [STEP 1/8] Verifying preconditions...
    echo.
    
    :: Check if wrapper file exists
    if not exist "!WRAPPER_SOURCE!" (
        echo [ERROR] Wrapper file not found: !WRAPPER_SOURCE!
        echo.
        echo Please ensure:
        echo   1. The wrapper is compiled and placed in the build directory
        echo   2. The wrapper is named Dism.exe
        echo   3. You have run the build script to generate the wrapper
        echo.
        echo If using the provided build script, the wrapper should be at:
        echo   !BUILD_DIR!\Dism.exe
        echo.
        goto :deploy_fail
    )
    
    :: Check if original Dism.exe exists
    if not exist "!DISM_ORIGINAL!" (
        echo [ERROR] Original Dism.exe not found: !DISM_ORIGINAL!
        echo.
        echo This may indicate:
        echo   1. DISM is not installed on this system
        echo   2. System files are corrupted
        echo   3. Wrong Windows version
        echo.
        goto :deploy_fail
    )
    
    echo [SUCCESS] All preconditions verified.
    echo.
    
    :: Step 2: Display warning and get confirmation
    echo [STEP 2/8] Warning and confirmation...
    echo.
    echo ============================================================================
    echo   WARNING: SYSTEM FILE MODIFICATION
    echo ============================================================================
    echo.
    echo This operation will modify system files in %SYSTEM32%:
    echo   1. Rename !DISM_ORIGINAL! to dism-origin.exe
    echo   2. Deploy wrapper to !DISM_ORIGINAL!
    echo   3. Stop and restart related Windows services
    echo.
    echo The wrapper will automatically intercept and replace:
    echo   /featurename:IIS-LegacySnapIn
    echo   with these 5 modern IIS features:
    echo     - IIS-WebServerManagementTools
    echo     - IIS-ManagementConsole
    echo     - IIS-ManagementScriptingTools
    echo     - IIS-ManagementService
    echo     - IIS-IIS6ManagementCompatibility
    echo.
    echo This is required for Citrix installation on Windows Server 2025.
    echo.
    set /p "CONFIRM=Do you want to continue? (Y/N): "
    if /i not "!CONFIRM!"=="Y" (
        echo.
        echo [INFO] Operation cancelled by user.
        goto :deploy_fail
    )
    
    :: Step 3: Create backup
    echo.
    echo [STEP 3/8] Creating backup...
    echo.
    
    if not exist "!DISM_BACKUP_DIR!" (
        mkdir "!DISM_BACKUP_DIR!" >nul 2>&1
        if !ERRORLEVEL! neq 0 (
            echo [ERROR] Cannot create backup directory: !DISM_BACKUP_DIR!
            goto :deploy_fail
        )
        echo [SUCCESS] Created backup directory: !DISM_BACKUP_DIR!
    )
    
    :: Generate timestamp for backup filename
    for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value 2^>nul') do set "DATETIME=%%I"
    if "!DATETIME!"=="" (
        :: Fallback if wmic is not available
        set "TIMESTAMP=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%-%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
    ) else (
        set "TIMESTAMP=!DATETIME:~0,8!-!DATETIME:~8,6!"
    )
    
    set "BACKUP_FILE=!DISM_BACKUP_DIR!\Dism-backup-!TIMESTAMP!.exe"
    
    copy "!DISM_ORIGINAL!" "!BACKUP_FILE!" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        for %%F in ("!BACKUP_FILE!") do set "BACKUP_SIZE=%%~zF"
        set /a "BACKUP_SIZE_KB=!BACKUP_SIZE! / 1024"
        echo [SUCCESS] Backup created: !BACKUP_FILE! (!BACKUP_SIZE_KB! KB)
    ) else (
        echo [WARNING] Could not create backup (file may be in use)
    )
    
    :: Step 4: Stop related services
    echo.
    echo [STEP 4/8] Stopping related services...
    echo.
    
    call :stop_services
    
    :: Step 5: Take ownership and set permissions (CRITICAL - Handle TrustedInstaller)
    echo.
    echo [STEP 5/8] Setting file permissions...
    echo.
    echo [INFO] Taking ownership of !DISM_ORIGINAL! from TrustedInstaller...
    
    :: Take ownership from TrustedInstaller
    takeown /f "!DISM_ORIGINAL!" /A >nul 2>&1
    if !ERRORLEVEL! neq 0 (
        echo [WARNING] Could not take ownership via takeown command
        echo [INFO] Trying alternative method...
        
        :: Alternative method using icacls
        icacls "!DISM_ORIGINAL!" /setowner "Administrators" >nul 2>&1
        if !ERRORLEVEL! neq 0 (
            echo [ERROR] Failed to take ownership of !DISM_ORIGINAL!
            echo [INFO] The file may be locked by another process.
            call :start_services
            goto :deploy_fail
        )
    )
    
    :: Grant full control to Administrators
    echo [INFO] Granting full control to Administrators...
    icacls "!DISM_ORIGINAL!" /grant "Administrators:F" /T >nul 2>&1
    if !ERRORLEVEL! neq 0 (
        echo [WARNING] Could not set permissions via icacls
        echo [INFO] Trying PowerShell method...
        
        :: Alternative using PowerShell
        powershell -Command "$acl = Get-Acl '!DISM_ORIGINAL!'; $rule = New-Object System.Security.AccessControl.FileSystemAccessRule('BUILTIN\Administrators','FullControl','Allow'); $acl.SetAccessRule($rule); Set-Acl -Path '!DISM_ORIGINAL!' -AclObject $acl" >nul 2>&1
        if !ERRORLEVEL! neq 0 (
            echo [ERROR] Failed to set permissions on !DISM_ORIGINAL!
            call :start_services
            goto :deploy_fail
        )
    )
    
    echo [SUCCESS] File permissions set successfully.
    
    :: Step 6: Rename original Dism.exe to dism-origin.exe
    echo.
    echo [STEP 6/8] Renaming original Dism.exe...
    echo.
    
    if exist "!DISM_ORIGIN!" (
        echo [WARNING] dism-origin.exe already exists
        echo [INFO] This may indicate a previous installation.
        set /p "OVERWRITE=Overwrite existing dism-origin.exe? (Y/N): "
        if /i "!OVERWRITE!"=="Y" (
            del /f /q "!DISM_ORIGIN!" >nul 2>&1
            echo [INFO] Existing dism-origin.exe removed.
        ) else (
            echo [INFO] Keeping existing dism-origin.exe.
        )
    )
    
    if not exist "!DISM_ORIGIN!" (
        :: Attempt rename with multiple methods
        set "RENAME_SUCCESS=0"
        
        :: Method 1: Standard rename
        ren "!DISM_ORIGINAL!" "dism-origin.exe" >nul 2>&1
        if !ERRORLEVEL! equ 0 set "RENAME_SUCCESS=1"
        
        :: Method 2: Using move command
        if !RENAME_SUCCESS! equ 0 (
            move /y "!DISM_ORIGINAL!" "!DISM_ORIGIN!" >nul 2>&1
            if !ERRORLEVEL! equ 0 set "RENAME_SUCCESS=1"
        )
        
        :: Method 3: Using PowerShell
        if !RENAME_SUCCESS! equ 0 (
            powershell -Command "Rename-Item -Path '!DISM_ORIGINAL!' -NewName 'dism-origin.exe' -Force" >nul 2>&1
            if !ERRORLEVEL! equ 0 set "RENAME_SUCCESS=1"
        )
        
        if !RENAME_SUCCESS! equ 1 (
            echo [SUCCESS] Renamed !DISM_ORIGINAL! to dism-origin.exe
        ) else (
            echo [ERROR] Could not rename Dism.exe
            echo.
            echo [TROUBLESHOOTING] Try one of these solutions:
            echo   1. Reboot the system and try again
            echo   2. Boot into Safe Mode and run this script
            echo   3. Use Task Manager to kill any dism.exe processes
            echo   4. Run 'sc stop TrustedInstaller' in an elevated command prompt
            echo.
            call :start_services
            goto :deploy_fail
        )
    )
    
    :: Step 7: Copy wrapper to System32
    echo.
    echo [STEP 7/8] Deploying wrapper...
    echo.
    
    copy /y "!WRAPPER_SOURCE!" "!DISM_ORIGINAL!" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        for %%F in ("!WRAPPER_SOURCE!") do set "WRAPPER_SIZE=%%~zF"
        set /a "WRAPPER_SIZE_KB=!WRAPPER_SIZE! / 1024"
        echo [SUCCESS] Wrapper deployed: !DISM_ORIGINAL!: !WRAPPER_SIZE_KB! KB
        
        :: Verify the copy
        if exist "!DISM_ORIGINAL!" (
            echo [SUCCESS] File copy verification passed
        ) else (
            echo [ERROR] File copy verification failed
            call :start_services
            goto :deploy_fail
        )
    ) else (
        echo [ERROR] Failed to copy wrapper to System32
        echo [INFO] Check if you have sufficient permissions and disk space.
        call :start_services
        goto :deploy_fail
    )
    
    :: Step 8: Restart services and verify deployment
    echo.
    echo [STEP 8/8] Restarting services and verifying deployment...
    echo.
    
    call :start_services
    
    :: Verify deployment
    call :verify_deployment
    
    :: Display success summary
    echo.
    echo ============================================================================
    echo   DEPLOYMENT COMPLETE - SUCCESS
    echo ============================================================================
    echo.
    echo [SUCCESS] DISM wrapper has been successfully deployed!
    echo.
    echo Important: The wrapper will automatically intercept and replace:
    echo   /featurename:IIS-LegacySnapIn
    echo   with these 5 modern IIS features:
    echo     - IIS-WebServerManagementTools
    echo     - IIS-ManagementConsole
    echo     - IIS-ManagementScriptingTools
    echo     - IIS-ManagementService
    echo     - IIS-IIS6ManagementCompatibility
    echo.
    echo Summary:
    echo   Original file (renamed): !DISM_ORIGIN!
    echo   Wrapper file:            !DISM_ORIGINAL!
    if exist "!BACKUP_FILE!" (
        echo   Backup file:           !BACKUP_FILE!
    )
    echo.
    echo Next steps:
    echo   1. You can now run the Citrix installer
    echo   2. The installer should no longer fail due to missing IIS-LegacySnapIn
    echo   3. After successful installation, restore original DISM using option 2
    echo.
    
    goto :deploy_end
    
    :deploy_fail
    echo.
    echo ============================================================================
    echo   DEPLOYMENT FAILED
    echo ============================================================================
    echo.
    echo [ERROR] Deployment was not successful.
    echo Please check the error messages above and try again.
    echo.
    
    :deploy_end
    echo Press any key to continue...
    pause > nul
    exit /b %ERRORLEVEL%
goto :eof

:: ============================================================================
:: Function: Restore original DISM
:: ============================================================================
:restore_original
    cls
    call :print_header "RESTORE ORIGINAL DISM"
    
    :: Step 1: Check if dism-origin.exe exists
    echo [STEP 1/6] Checking system state...
    echo.
    
    if not exist "!DISM_ORIGIN!" (
        echo [ERROR] dism-origin.exe not found at: !DISM_ORIGIN!
        echo.
        echo This could mean:
        echo   1. The wrapper was never deployed
        echo   2. The original file was deleted or moved
        echo   3. You are looking at the wrong location
        echo.
        echo Checking for backup files...
        if exist "!DISM_BACKUP_DIR!\*.exe" (
            echo [INFO] Backups found in: !DISM_BACKUP_DIR!
            echo [INFO] You may need to manually restore from backup.
        ) else (
            echo [INFO] No backup files found.
        )
        echo.
        goto :restore_fail
    )
    
    echo [SUCCESS] Found dism-origin.exe at: !DISM_ORIGIN!
    echo.
    
    :: Step 2: Confirm restoration
    echo [STEP 2/6] Confirmation...
    echo.
    echo ============================================================================
    echo   WARNING: SYSTEM FILE RESTORATION
    echo ============================================================================
    echo.
    echo This operation will:
    echo   1. Remove the DISM wrapper from !DISM_ORIGINAL!
    echo   2. Restore the original Windows DISM tool from dism-origin.exe
    echo   3. Stop and restart related Windows services
    echo.
    echo This is recommended after Citrix installation is complete.
    echo.
    set /p "CONFIRM=Do you want to continue? (Y/N): "
    if /i not "!CONFIRM!"=="Y" (
        echo.
        echo [INFO] Operation cancelled by user.
        goto :restore_fail
    )
    
    :: Step 3: Stop services
    echo.
    echo [STEP 3/6] Stopping services...
    echo.
    
    call :stop_services
    
    :: Step 4: Remove wrapper (requires permission handling)
    echo.
    echo [STEP 4/6] Removing wrapper...
    echo.
    
    if exist "!DISM_ORIGINAL!" (
        echo [INFO] Taking ownership of wrapper file for removal...
        takeown /f "!DISM_ORIGINAL!" /A >nul 2>&1
        icacls "!DISM_ORIGINAL!" /grant "Administrators:F" >nul 2>&1
        
        del /f /q "!DISM_ORIGINAL!" >nul 2>&1
        if !ERRORLEVEL! equ 0 (
            echo [SUCCESS] Removed wrapper: !DISM_ORIGINAL!
        ) else (
            echo [WARNING] Could not delete wrapper, attempting force delete...
            powershell -Command "Remove-Item '!DISM_ORIGINAL!' -Force" >nul 2>&1
            if !ERRORLEVEL! equ 0 (
                echo [SUCCESS] Wrapper removed via PowerShell force delete
            ) else (
                echo [ERROR] Could not remove wrapper file
                call :start_services
                goto :restore_fail
            )
        )
    )
    
    :: Step 5: Restore original
    echo.
    echo [STEP 5/6] Restoring original Dism.exe...
    echo.
    
    :: Take ownership of dism-origin.exe before rename
    takeown /f "!DISM_ORIGIN!" /A >nul 2>&1
    icacls "!DISM_ORIGIN!" /grant "Administrators:F" >nul 2>&1
    
    ren "!DISM_ORIGIN!" "Dism.exe" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        echo [SUCCESS] Restored original: !DISM_ORIGINAL!
    ) else (
        echo [ERROR] Could not restore original
        echo [INFO] Trying alternative rename method...
        move /y "!DISM_ORIGIN!" "!DISM_ORIGINAL!" >nul 2>&1
        if !ERRORLEVEL! neq 0 (
            echo [ERROR] All rename attempts failed
            call :start_services
            goto :restore_fail
        )
        echo [SUCCESS] Restored original using move command
    )
    
    :: Step 6: Restart services and verify
    echo.
    echo [STEP 6/6] Restarting services and verifying restoration...
    echo.
    
    call :start_services
    
    :: Verify restoration
    if exist "!DISM_ORIGINAL!" (
        echo [SUCCESS] Original DISM has been restored successfully!
        echo.
        echo You can test with:
        echo   Dism /online /get-features ^| findstr "IIS"
        echo.
    ) else (
        echo [ERROR] Restoration verification failed
        goto :restore_fail
    )
    
    :: Display success summary
    echo.
    echo ============================================================================
    echo   RESTORATION COMPLETE - SUCCESS
    echo ============================================================================
    echo.
    echo [SUCCESS] Original DISM configuration has been restored!
    echo.
    echo The system is now back to its original state.
    echo The wrapper has been removed and the original DISM tool is active.
    echo.
    
    goto :restore_end
    
    :restore_fail
    echo.
    echo ============================================================================
    echo   RESTORATION FAILED
    echo ============================================================================
    echo.
    echo [ERROR] Restoration was not successful.
    echo Please check the error messages above and try again.
    echo.
    
    :restore_end
    echo Press any key to continue...
    pause > nul
    exit /b %ERRORLEVEL%
goto :eof

:: ============================================================================
:: Function: Verify current configuration
:: ============================================================================
:verify_configuration
    cls
    call :print_header "VERIFY CURRENT CONFIGURATION"
    
    echo Checking system files and wrapper status...
    echo.
    
    set "FILES_EXIST=0"
    set "WRAPPER_INSTALLED=0"
    set "STATUS=UNKNOWN"
    
    :: Check main files
    echo [INFO] Checking main files in %SYSTEM32%:
    echo.
    
    if exist "!DISM_ORIGINAL!" (
        for %%F in ("!DISM_ORIGINAL!") do set "CURRENT_SIZE=%%~zF"
        set /a "CURRENT_SIZE_KB=!CURRENT_SIZE! / 1024"
        echo [FOUND] Dism.exe exists (!CURRENT_SIZE_KB! KB)
        set /a "FILES_EXIST+=1"
        
        :: Try to determine if it's the wrapper or original
        if exist "!WRAPPER_SOURCE!" (
            for %%F in ("!WRAPPER_SOURCE!") do set "WRAPPER_SIZE=%%~zF"
            if !CURRENT_SIZE! equ !WRAPPER_SIZE! (
                echo [INFO]   This appears to be the WRAPPER (size matches source)
                set "WRAPPER_INSTALLED=1"
            ) else (
                echo [INFO]   This appears to be the ORIGINAL DISM
            )
        )
    ) else (
        echo [MISSING] Dism.exe not found!
    )
    
    if exist "!DISM_ORIGIN!" (
        for %%F in ("!DISM_ORIGIN!") do set "ORIGIN_SIZE=%%~zF"
        set /a "ORIGIN_SIZE_KB=!ORIGIN_SIZE! / 1024"
        echo [FOUND] dism-origin.exe exists (!ORIGIN_SIZE_KB! KB)
        set /a "FILES_EXIST+=1"
    ) else (
        echo [MISSING] dism-origin.exe not found
    )
    
    :: Check wrapper source
    echo.
    echo [INFO] Checking wrapper source file:
    echo.
    
    if exist "!WRAPPER_SOURCE!" (
        for %%F in ("!WRAPPER_SOURCE!") do set "WRAPPER_SIZE=%%~zF"
        set /a "WRAPPER_SIZE_KB=!WRAPPER_SIZE! / 1024"
        echo [FOUND] Wrapper source: !WRAPPER_SOURCE! (!WRAPPER_SIZE_KB! KB)
    ) else (
        echo [MISSING] Wrapper source: !WRAPPER_SOURCE!
        echo [INFO]   Expected location: !BUILD_DIR!\Dism.exe
    )
    
    :: Check backup directory
    echo.
    echo [INFO] Checking backup directory:
    echo.
    
    if exist "!DISM_BACKUP_DIR!" (
        echo [FOUND] Backup directory: !DISM_BACKUP_DIR!
        for /f %%A in ('dir /b "!DISM_BACKUP_DIR!\*.exe" 2^>nul ^| find /c /v ""') do set "BACKUP_COUNT=%%A"
        if defined BACKUP_COUNT (
            echo [INFO]   Backup files found: !BACKUP_COUNT!
            echo [INFO]   Latest backup:
            for /f "delims=" %%F in ('dir /b /o-d "!DISM_BACKUP_DIR!\*.exe" 2^>nul') do (
                echo [INFO]     - %%F
                goto :backup_done
            )
        ) else (
            echo [INFO]   No backup files found
        )
        :backup_done
    ) else (
        echo [MISSING] Backup directory not found
    )
    
    :: Determine configuration status
    echo.
    echo ============================================================================
    echo   CONFIGURATION STATUS
    echo ============================================================================
    echo.
    
    if !WRAPPER_INSTALLED! equ 1 (
        echo Status: WRAPPER INSTALLED
        echo.
        echo The DISM wrapper is currently active and will replace IIS-LegacySnapIn.
        echo You can now run the Citrix installer.
        echo.
        echo Recommended action: After Citrix installation, restore original DISM.
    ) else if exist "!DISM_ORIGIN!" (
        if !FILES_EXIST! equ 2 (
            echo Status: MIXED STATE (inconsistent)
            echo.
            echo Both Dism.exe and dism-origin.exe exist but Dism.exe is not the wrapper.
            echo This may indicate an incomplete or failed installation/restoration.
            echo.
            echo Recommended action: Restore consistency by either:
            echo   1. Deploying wrapper (if preparing for Citrix installation)
            echo   2. Restoring original (if Citrix installation is complete)
        )
    ) else if !FILES_EXIST! equ 1 (
        echo Status: ORIGINAL INSTALLED
        echo.
        echo The original DISM is installed. No wrapper is active.
        echo.
        echo Recommended action:
        if exist "!WRAPPER_SOURCE!" (
            echo   Deploy wrapper if preparing for Citrix installation.
        ) else (
            echo   Compile wrapper first, then deploy if needed.
        )
    ) else (
        echo Status: UNKNOWN or CORRUPTED
        echo.
        echo Cannot determine current configuration. System files may be corrupted.
        echo.
        echo Recommended action: Check system integrity or restore from backup.
    )
    
    echo.
    echo Press any key to continue...
    pause > nul
    exit /b 0
goto :eof

:: ============================================================================
:: Function: Check system requirements
:: ============================================================================
:check_requirements
    cls
    call :print_header "SYSTEM REQUIREMENTS CHECK"
    
    echo Checking system requirements for DISM wrapper deployment...
    echo.
    
    set "REQUIREMENTS_MET=1"
    
    :: 1. Check Windows version
    echo [CHECK] Windows Version:
    ver | findstr /i "Microsoft"
    echo.
    
    :: 2. Check architecture
    echo [CHECK] System Architecture:
    if "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
        echo [OK]   x64 (64-bit) - Compatible with Windows Server 2025
    ) else if "%PROCESSOR_ARCHITECTURE%"=="x86" (
        echo [WARNING]   x86 (32-bit) - Not recommended for Server 2025
        set "REQUIREMENTS_MET=0"
    ) else (
        echo [WARNING]   Unknown: %PROCESSOR_ARCHITECTURE%
        set "REQUIREMENTS_MET=0"
    )
    echo.
    
    :: 3. Check admin privileges
    echo [CHECK] Administrator Privileges:
    echo [OK]   Running as Administrator
    echo.
    
    :: 4. Check wrapper file
    echo [CHECK] Wrapper File:
    if exist "!WRAPPER_SOURCE!" (
        for %%F in ("!WRAPPER_SOURCE!") do set "WRAPPER_SIZE=%%~zF"
        set /a "WRAPPER_SIZE_KB=!WRAPPER_SIZE! / 1024"
        echo [OK]   Found: !WRAPPER_SOURCE! (!WRAPPER_SIZE_KB! KB)
    ) else (
        echo [ERROR]   Missing: !WRAPPER_SOURCE!
        echo [INFO]     Please compile the wrapper first
        set "REQUIREMENTS_MET=0"
    )
    echo.
    
    :: 5. Check Dism.exe
    echo [CHECK] System DISM:
    if exist "!DISM_ORIGINAL!" (
        for %%F in ("!DISM_ORIGINAL!") do set "DISM_SIZE=%%~zF"
        set /a "DISM_SIZE_KB=!DISM_SIZE! / 1024"
        echo [OK]   Found: !DISM_ORIGINAL! (!DISM_SIZE_KB! KB)
    ) else (
        echo [ERROR]   Missing: !DISM_ORIGINAL!
        set "REQUIREMENTS_MET=0"
    )
    echo.
    
    :: 6. Check available disk space
    echo [CHECK] Disk Space in System32:
    for /f "tokens=3" %%a in ('dir /-c "%SYSTEM32%" 2^>nul ^| find "bytes free"') do (
        set "FREE_SPACE=%%a"
    )
    if defined FREE_SPACE (
        set /a "FREE_SPACE_MB=!FREE_SPACE! / 1048576"
        if !FREE_SPACE_MB! gtr 50 (
            echo [OK]   Free space: !FREE_SPACE_MB! MB
        ) else (
            echo [WARNING]   Low free space: !FREE_SPACE_MB! MB
        )
    ) else (
        echo [INFO]   Could not determine free space
    )
    
    :: Summary
    echo.
    echo ============================================================================
    if !REQUIREMENTS_MET! equ 1 (
        echo [RESULT] All requirements met. Ready for wrapper deployment.
    ) else (
        echo [RESULT] Requirements not met. Please resolve issues above.
    )
    echo ============================================================================
    echo.
    
    echo Press any key to continue...
    pause > nul
    exit /b 0
goto :eof

:: ============================================================================
:: Function: Show help
:: ============================================================================
:show_help
    cls
    call :print_banner
    
    echo ============================================================================
    echo   HELP - USAGE INFORMATION
    echo ============================================================================
    echo.
    echo DESCRIPTION:
    echo   This tool deploys a wrapper for Dism.exe that automatically replaces
    echo   the deprecated IIS-LegacySnapIn feature with modern IIS features.
    echo   This is required for Citrix installation on Windows Server 2025.
    echo.
    echo SYNOPSIS:
    echo   Double-click script                       (interactive menu)
    echo   !SCRIPT_NAME! /replace                    (deploy wrapper)
    echo   !SCRIPT_NAME! /restore                    (restore original)
    echo   !SCRIPT_NAME! /verify                     (verify configuration)
    echo   !SCRIPT_NAME! /check                      (check system requirements)
    echo   !SCRIPT_NAME! /help                       (this help message)
    echo   !SCRIPT_NAME! /version                    (show version information)
    echo.
    echo INTERACTIVE MENU OPTIONS:
    echo   1. Deploy DISM Wrapper        - Install wrapper to replace IIS-LegacySnapIn
    echo   2. Restore Original DISM      - Remove wrapper and restore original
    echo   3. Verify Current Configuration - Check current system state
    echo   4. Check System Requirements  - Verify system compatibility
    echo   5. Show Help                  - Display help information
    echo   6. Show Version Information   - Display version and author
    echo   0. Exit                       - Exit the program
    echo.
    echo PREREQUISITES:
    echo   1. Compiled wrapper file at: !BUILD_DIR!\Dism.exe
    echo   2. Administrative privileges (script will auto-elevate)
    echo   3. Windows Server 2016/2019/2022/2025 recommended
    echo.
    echo WORKFLOW:
    echo   1. Compile wrapper on Linux using MinGW-w64
    echo   2. Copy wrapper to !BUILD_DIR!\Dism.exe
    echo   3. Run this script and select option 1
    echo   4. Run Citrix installer (it should work now)
    echo   5. After installation, select option 2 to restore original
    echo.
    echo NOTES:
    echo   - The wrapper only replaces IIS-LegacySnapIn, all other features unchanged
    echo   - Backup is automatically created before any modification
    echo   - May require reboot if system files are locked
    echo   - Tested on Windows Server 2025 Datacenter
    echo   - Author: !SCRIPT_AUTHOR!
    echo   - Version: !SCRIPT_VERSION!
    echo.
    echo ============================================================================
    
    echo Press any key to continue...
    pause > nul
    exit /b 0
goto :eof

:: ============================================================================
:: Function: Show version information
:: ============================================================================
:show_version
    cls
    call :print_banner
    
    echo ============================================================================
    echo   VERSION INFORMATION
    echo ============================================================================
    echo.
    echo Script Name:    !SCRIPT_NAME!
    echo Version:        !SCRIPT_VERSION!
    echo Release Date:   !SCRIPT_DATE!
    echo Author:         !SCRIPT_AUTHOR!
    echo.
    echo System Information:
    echo   Computer:     %COMPUTERNAME%
    echo   User:         %USERNAME%
    echo   OS:           %OS%
    echo   Architecture: %PROCESSOR_ARCHITECTURE%
    echo.
    echo Path Information:
    echo   Script Directory:  %~dp0
    echo   Build Directory:   !BUILD_DIR!
    echo   System Directory:  !SYSTEM32!
    echo.
    echo ============================================================================
    
    echo Press any key to continue...
    pause > nul
    exit /b 0
goto :eof

:: ============================================================================
:: Helper Functions
:: ============================================================================

:stop_services
    echo [INFO] Stopping related services...
    
    :: Services that may lock DISM files
    set "SERVICES=TrustedInstaller wuauserv bits cryptsvc"
    
    for %%S in (!SERVICES!) do (
        sc query "%%~S" >nul 2>&1
        if !ERRORLEVEL! equ 0 (
            echo [INFO]   Stopping: %%S
            net stop "%%~S" /y >nul 2>&1
            if !ERRORLEVEL! equ 0 (
                echo [OK]     Successfully stopped
            ) else (
                echo [WARNING] Could not stop %%S (may already be stopped)
            )
        )
    )
    
    :: Additional wait to ensure services are fully stopped
    timeout /t 2 /nobreak >nul
goto :eof

:start_services
    echo [INFO] Starting related services...
    
    set "SERVICES=TrustedInstaller wuauserv bits cryptsvc"
    
    :: Wait to ensure services can start properly
    timeout /t 2 /nobreak >nul
    
    for %%S in (!SERVICES!) do (
        sc query "%%~S" >nul 2>&1
        if !ERRORLEVEL! equ 0 (
            echo [INFO]   Starting: %%S
            net start "%%~S" >nul 2>&1
            if !ERRORLEVEL! equ 0 (
                echo [OK]     Successfully started
            )
        )
    )
goto :eof

:verify_deployment
    echo [INFO] Verifying deployment...
    
    if exist "!DISM_ORIGINAL!" (
        echo [OK]   Wrapper exists at !DISM_ORIGINAL!
    ) else (
        echo [ERROR] Wrapper not found at !DISM_ORIGINAL!
    )
    
    if exist "!DISM_ORIGIN!" (
        echo [OK]   Original file exists at !DISM_ORIGIN!
    ) else (
        echo [ERROR] Original file not found at !DISM_ORIGIN!
    )
    
    :: Quick functionality test
    echo [INFO] Testing basic DISM functionality...
    Dism /? >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        echo [OK]   DISM responds to help command
    ) else (
        echo [WARNING] DISM does not respond to help command
    )
goto :eof

:pause_and_return
    echo.
    echo ============================================================================
    set /p "RETURN_MENU=Press Enter to return to menu or X to exit: "
    if /i "!RETURN_MENU!"=="X" (
        exit /b 0
    )
goto :eof

:: ============================================================================
:: End of script with proper cleanup
:: ============================================================================
:end_script
    echo.
    echo ============================================================================
    echo   OPERATION COMPLETE
    echo ============================================================================
    echo.
    echo Thank you for using DISM Wrapper Deployment Tool v%SCRIPT_VERSION%.
    echo.
    echo Press any key to exit...
    pause > nul
    
    :: Clean up and exit
    endlocal
    exit /b %ERRORLEVEL%
