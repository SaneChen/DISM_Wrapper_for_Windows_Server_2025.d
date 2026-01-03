/**
 * DISM Wrapper for Windows Server 2025
 * 
 * Purpose: Intercept DISM commands and replace IIS-LegacySnapIn feature
 *          with modern IIS management features for Citrix compatibility.
 * 
 * Compilation on Linux:
 *   x86_64-w64-mingw32-gcc -o dism.exe dism-wrapper.c -s -O2 -static -D_WIN32_WINNT=0x0600
 * 
 * Deployment:
 *   1. Rename original C:\Windows\System32\dism.exe to dism-origin.exe
 *   2. Copy this wrapper as C:\Windows\System32\dism.exe
 * 
 * Author: System Administrator
 * Version: 2.0
 * License: MIT
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdbool.h>

/* ============================================================================
 * Constants and Configuration
 * ============================================================================ */

/* Original DISM executable name */
#define ORIGINAL_DISM_EXE "dism-origin.exe"

/* Feature to search for (case-insensitive) */
#define LEGACY_FEATURE_NAME "IIS-LegacySnapIn"

/* Replacement features */
static const char* REPLACEMENT_FEATURES[] = {
    "/featurename:IIS-WebServerManagementTools",
    "/featurename:IIS-ManagementConsole",
    "/featurename:IIS-ManagementScriptingTools", 
    "/featurename:IIS-ManagementService",
    "/featurename:IIS-IIS6ManagementCompatibility",
    NULL /* Sentinel */
};

/* Number of replacement features */
#define REPLACEMENT_COUNT 5

/* Maximum command line length supported by Windows */
#define MAX_CMD_LENGTH 32767

/* ============================================================================
 * Utility Functions
 * ============================================================================ */

/**
 * Convert a string to lowercase for case-insensitive comparison.
 * 
 * @param str The input string to convert.
 * @return Newly allocated lowercase string (caller must free), or NULL on error.
 */
static char* string_to_lowercase(const char* str)
{
    if (str == NULL) {
        return NULL;
    }
    
    size_t length = strlen(str);
    char* result = (char*)malloc(length + 1);
    
    if (result == NULL) {
        return NULL;
    }
    
    for (size_t i = 0; i < length; i++) {
        result[i] = (char)tolower((unsigned char)str[i]);
    }
    
    result[length] = '\0';
    return result;
}

/**
 * Check if a string contains the legacy feature name.
 * 
 * @param argument The command line argument to check.
 * @return true if argument contains LEGACY_FEATURE_NAME, false otherwise.
 */
static bool contains_legacy_feature(const char* argument)
{
    if (argument == NULL) {
        return false;
    }
    
    char* lower_arg = string_to_lowercase(argument);
    if (lower_arg == NULL) {
        return false;
    }
    
    bool found = false;
    
    /* Check for various forms of the parameter */
    const char* patterns[] = {
        "/featurename:iis-legacysnapin",
        "-featurename:iis-legacysnapin",
        "featurename:iis-legacysnapin",
        NULL
    };
    
    for (int i = 0; patterns[i] != NULL; i++) {
        if (strstr(lower_arg, patterns[i]) != NULL) {
            found = true;
            break;
        }
    }
    
    free(lower_arg);
    return found;
}

/**
 * Count occurrences of legacy feature in command line arguments.
 * 
 * @param argc Number of arguments.
 * @param argv Array of argument strings.
 * @return Number of times legacy feature appears in arguments.
 */
static int count_legacy_features(int argc, char* argv[])
{
    int count = 0;
    
    for (int i = 1; i < argc; i++) {
        if (contains_legacy_feature(argv[i])) {
            count++;
        }
    }
    
    return count;
}

/**
 * Quote a string for command line usage if it contains spaces or quotes.
 * 
 * @param buffer Destination buffer.
 * @param buffer_size Size of destination buffer.
 * @param str String to quote.
 * @return true if successful, false if buffer too small.
 */
static bool quote_argument(char* buffer, size_t buffer_size, const char* str)
{
    if (str == NULL || buffer == NULL || buffer_size == 0) {
        return false;
    }
    
    /* Check if quoting is needed */
    bool needs_quotes = (strchr(str, ' ') != NULL) || (strchr(str, '"') != NULL);
    
    if (!needs_quotes) {
        /* Safe to copy directly */
        if (strlen(str) < buffer_size) {
            strcpy(buffer, str);
            return true;
        }
        return false;
    }
    
    /* Need to quote and escape */
    size_t pos = 0;
    buffer[pos++] = '"';
    
    for (const char* p = str; *p != '\0'; p++) {
        if (*p == '"') {
            /* Escape double quote */
            if (pos + 2 >= buffer_size) return false;
            buffer[pos++] = '\\';
            buffer[pos++] = '"';
        } else {
            if (pos + 1 >= buffer_size) return false;
            buffer[pos++] = *p;
        }
    }
    
    if (pos + 1 >= buffer_size) return false;
    buffer[pos++] = '"';
    buffer[pos] = '\0';
    
    return true;
}

/* ============================================================================
 * Command Line Processing
 * ============================================================================ */

/**
 * Build new command line with legacy features replaced.
 * 
 * @param argc Original argument count.
 * @param argv Original argument array.
 * @param new_cmdline Buffer to receive new command line.
 * @param buffer_size Size of buffer.
 * @return true if successful, false on error.
 */
static bool build_replacement_command_line(int argc, char* argv[], 
                                         char* new_cmdline, size_t buffer_size)
{
    if (new_cmdline == NULL || buffer_size < 2) {
        return false;
    }
    
    /* Start with original DISM executable */
    size_t pos = 0;
    strcpy(new_cmdline, ORIGINAL_DISM_EXE);
    pos = strlen(new_cmdline);
    
    /* Process each argument */
    for (int i = 1; i < argc; i++) {
        if (pos >= buffer_size - 2) {
            return false; /* Buffer too small */
        }
        
        new_cmdline[pos++] = ' ';
        
        if (contains_legacy_feature(argv[i])) {
            /* Replace with all modern features */
            for (int j = 0; j < REPLACEMENT_COUNT; j++) {
                if (j > 0) {
                    if (pos >= buffer_size - 2) return false;
                    new_cmdline[pos++] = ' ';
                }
                
                /* Copy replacement feature */
                size_t feature_len = strlen(REPLACEMENT_FEATURES[j]);
                if (pos + feature_len >= buffer_size) return false;
                
                strcpy(new_cmdline + pos, REPLACEMENT_FEATURES[j]);
                pos += feature_len;
            }
        } else {
            /* Copy original argument (with quoting if needed) */
            char quoted_arg[1024];
            if (!quote_argument(quoted_arg, sizeof(quoted_arg), argv[i])) {
                return false;
            }
            
            size_t arg_len = strlen(quoted_arg);
            if (pos + arg_len >= buffer_size) return false;
            
            strcpy(new_cmdline + pos, quoted_arg);
            pos += arg_len;
        }
    }
    
    new_cmdline[pos] = '\0';
    return true;
}

/**
 * Build command line without replacements (pass-through mode).
 * 
 * @param argc Original argument count.
 * @param argv Original argument array.
 * @param new_cmdline Buffer to receive new command line.
 * @param buffer_size Size of buffer.
 * @return true if successful, false on error.
 */
static bool build_passthrough_command_line(int argc, char* argv[],
                                         char* new_cmdline, size_t buffer_size)
{
    if (new_cmdline == NULL || buffer_size < 2) {
        return false;
    }
    
    /* Start with original DISM executable */
    size_t pos = 0;
    strcpy(new_cmdline, ORIGINAL_DISM_EXE);
    pos = strlen(new_cmdline);
    
    /* Copy all arguments unchanged */
    for (int i = 1; i < argc; i++) {
        if (pos >= buffer_size - 2) {
            return false;
        }
        
        new_cmdline[pos++] = ' ';
        
        char quoted_arg[1024];
        if (!quote_argument(quoted_arg, sizeof(quoted_arg), argv[i])) {
            return false;
        }
        
        size_t arg_len = strlen(quoted_arg);
        if (pos + arg_len >= buffer_size) return false;
        
        strcpy(new_cmdline + pos, quoted_arg);
        pos += arg_len;
    }
    
    new_cmdline[pos] = '\0';
    return true;
}

/* ============================================================================
 * Process Execution
 * ============================================================================ */

/**
 * Execute DISM command with error handling.
 * 
 * @param command_line Full command line to execute.
 * @return Process exit code, or 1 on execution error.
 */
static int execute_dism_command(const char* command_line)
{
    if (command_line == NULL) {
        fprintf(stderr, "ERROR: NULL command line passed to execute_dism_command\n");
        return 1;
    }
    
    /* Log the command being executed */
    printf("[DISM WRAPPER] Executing: %s\n\n", command_line);
    
    STARTUPINFO startup_info;
    PROCESS_INFORMATION process_info;
    
    /* Initialize structures */
    ZeroMemory(&startup_info, sizeof(startup_info));
    startup_info.cb = sizeof(startup_info);
    ZeroMemory(&process_info, sizeof(process_info));
    
    /* Create mutable copy of command line for CreateProcess */
    char* mutable_cmdline = _strdup(command_line);
    if (mutable_cmdline == NULL) {
        fprintf(stderr, "ERROR: Memory allocation failed for command line\n");
        return 1;
    }
    
    /* Create the process */
    BOOL success = CreateProcess(
        NULL,               /* No module name (use command line) */
        mutable_cmdline,    /* Command line */
        NULL,               /* Process handle not inheritable */
        NULL,               /* Thread handle not inheritable */
        FALSE,              /* Set handle inheritance to FALSE */
        0,                  /* No creation flags */
        NULL,               /* Use parent's environment block */
        NULL,               /* Use parent's starting directory */
        &startup_info,      /* Pointer to STARTUPINFO structure */
        &process_info       /* Pointer to PROCESS_INFORMATION structure */
    );
    
    free(mutable_cmdline);
    
    if (!success) {
        DWORD error_code = GetLastError();
        fprintf(stderr, "ERROR: CreateProcess failed (Error %lu)\n", error_code);
        return 1;
    }
    
    /* Wait until child process exits */
    WaitForSingleObject(process_info.hProcess, INFINITE);
    
    /* Get the exit code */
    DWORD exit_code = 0;
    if (!GetExitCodeProcess(process_info.hProcess, &exit_code)) {
        fprintf(stderr, "WARNING: Failed to get process exit code\n");
        exit_code = 1;
    }
    
    /* Close process and thread handles */
    CloseHandle(process_info.hProcess);
    CloseHandle(process_info.hThread);
    
    printf("[DISM WRAPPER] Process completed with exit code %lu\n", exit_code);
    return (int)exit_code;
}

/* ============================================================================
 * Main Function
 * ============================================================================ */

/**
 * Main entry point of the wrapper.
 * 
 * @param argc Number of command line arguments.
 * @param argv Array of argument strings.
 * @return Exit code of the DISM process, or 1 on wrapper error.
 */
int main(int argc, char* argv[])
{
    /* Check for legacy feature in arguments */
    int legacy_count = count_legacy_features(argc, argv);
    
    if (legacy_count > 0) {
        /* Legacy feature found - perform replacement */
        printf("[DISM WRAPPER] Detected %d occurrence(s) of '%s'\n", 
               legacy_count, LEGACY_FEATURE_NAME);
        printf("[DISM WRAPPER] Replacing with modern IIS management features\n");
        
        /* Build new command line with replacements */
        char new_cmdline[MAX_CMD_LENGTH];
        if (!build_replacement_command_line(argc, argv, new_cmdline, sizeof(new_cmdline))) {
            fprintf(stderr, "ERROR: Failed to build replacement command line\n");
            return 1;
        }
        
        /* Execute the modified command */
        return execute_dism_command(new_cmdline);
    } else {
        /* No legacy feature - pass through unchanged */
        printf("[DISM WRAPPER] No legacy features detected - passing through\n");
        
        /* Build command line without modifications */
        char new_cmdline[MAX_CMD_LENGTH];
        if (!build_passthrough_command_line(argc, argv, new_cmdline, sizeof(new_cmdline))) {
            fprintf(stderr, "ERROR: Failed to build pass-through command line\n");
            return 1;
        }
        
        /* Execute the original command */
        return execute_dism_command(new_cmdline);
    }
}
