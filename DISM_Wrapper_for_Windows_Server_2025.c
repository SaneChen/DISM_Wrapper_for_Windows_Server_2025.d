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
 * Version: 2.1
 * License: MIT
 *
 * New features in v2.1:
 *   - Modified replacement features to only use 2 modern features
 *   - Intercepts output of dism /online /english /get-features
 *   - Replaces "IIS-ManagementScriptingTools" with "IIS-LegacySnapIn" in output
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

/* Replacement features - ONLY 2 features now */
static const char* REPLACEMENT_FEATURES[] = {
    "/featurename:IIS-ManagementScriptingTools",
    "/featurename:IIS-ManagementService",
    NULL /* Sentinel */
};

/* Number of replacement features */
#define REPLACEMENT_COUNT 2

/* Feature name to replace in output */
#define OLD_FEATURE_NAME "IIS-ManagementScriptingTools"
#define NEW_FEATURE_NAME "IIS-LegacySnapIn"

/* Maximum command line length supported by Windows */
#define MAX_CMD_LENGTH 32767

/* Buffer size for reading process output */
#define OUTPUT_BUFFER_SIZE 16384

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

/**
 * Check if command is requesting feature list in English.
 *
 * @param argc Number of arguments.
 * @param argv Array of argument strings.
 * @return true if command is "dism /online /english /get-features"
 */
static bool is_get_features_command(int argc, char* argv[])
{
    bool has_online = false;
    bool has_english = false;
    bool has_get_features = false;

    for (int i = 1; i < argc; i++) {
        char* lower_arg = string_to_lowercase(argv[i]);
        if (lower_arg) {
            if (strcmp(lower_arg, "/online") == 0 ||
                strcmp(lower_arg, "-online") == 0) {
                has_online = true;
            }
            else if (strcmp(lower_arg, "/english") == 0 ||
                     strcmp(lower_arg, "-english") == 0) {
                has_english = true;
            }
            else if (strcmp(lower_arg, "/get-features") == 0 ||
                     strcmp(lower_arg, "-get-features") == 0 ||
                     strstr(lower_arg, "/get-features") != NULL ||
                     strstr(lower_arg, "-get-features") != NULL) {
                has_get_features = true;
            }
            free(lower_arg);
        }
    }

    return has_online && has_english && has_get_features;
}

/* ============================================================================
 * Output Processing Functions
 * ============================================================================ */

/**
 * Simple string replacement function.
 *
 * @param src Source string.
 * @param old_str String to replace.
 * @param new_str Replacement string.
 * @return New string with replacements (caller must free), or NULL on error.
 */
static char* string_replace(const char* src, const char* old_str, const char* new_str)
{
    if (src == NULL || old_str == NULL || new_str == NULL) {
        return NULL;
    }

    size_t src_len = strlen(src);
    size_t old_len = strlen(old_str);
    size_t new_len = strlen(new_str);

    /* Count occurrences of old_str */
    const char* pos = src;
    size_t count = 0;
    while ((pos = strstr(pos, old_str)) != NULL) {
        count++;
        pos += old_len;
    }

    /* Allocate memory for new string */
    size_t new_size = src_len + count * (new_len - old_len) + 1;
    char* result = (char*)malloc(new_size);
    if (result == NULL) {
        return NULL;
    }

    /* Perform replacement */
    char* dest = result;
    const char* current = src;

    while (*current != '\0') {
        if (strstr(current, old_str) == current) {
            /* Found old_str, replace it */
            strcpy(dest, new_str);
            dest += new_len;
            current += old_len;
        } else {
            /* Copy character */
            *dest++ = *current++;
        }
    }

    *dest = '\0';
    return result;
}

/**
 * Process output chunk to replace feature names.
 *
 * @param chunk The output chunk to process.
 * @param chunk_size Size of chunk.
 * @return Processed chunk (caller must free), or NULL on error.
 */
static char* process_output_chunk(const char* chunk, size_t chunk_size)
{
    if (chunk == NULL || chunk_size == 0) {
        return NULL;
    }

    /* Create null-terminated copy of chunk */
    char* chunk_copy = (char*)malloc(chunk_size + 1);
    if (chunk_copy == NULL) {
        return NULL;
    }

    memcpy(chunk_copy, chunk, chunk_size);
    chunk_copy[chunk_size] = '\0';

    /* Replace feature name */
    char* processed = string_replace(chunk_copy, OLD_FEATURE_NAME, NEW_FEATURE_NAME);

    free(chunk_copy);
    return processed;
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
            /* Replace with modern features (only 2 now) */
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
 * Execute DISM command with output interception for get-features command.
 *
 * @param command_line Full command line to execute.
 * @param is_get_features Whether this is a get-features command.
 * @return Process exit code, or 1 on execution error.
 */
static int execute_dism_command(const char* command_line, bool is_get_features)
{
    if (command_line == NULL) {
        fprintf(stderr, "ERROR: NULL command line passed to execute_dism_command\n");
        return 1;
    }

    /* Log the command being executed */
    printf("[DISM WRAPPER] Executing: %s\n", command_line);
    if (is_get_features) {
        printf("[DISM WRAPPER] Output will be intercepted and modified\n");
    }
    printf("\n");

    STARTUPINFO startup_info;
    PROCESS_INFORMATION process_info;
    SECURITY_ATTRIBUTES security_attrs;

    /* Initialize structures */
    ZeroMemory(&startup_info, sizeof(startup_info));
    startup_info.cb = sizeof(startup_info);
    ZeroMemory(&process_info, sizeof(process_info));
    ZeroMemory(&security_attrs, sizeof(security_attrs));

    HANDLE stdout_read = NULL;
    HANDLE stdout_write = NULL;
    HANDLE stderr_read = NULL;
    HANDLE stderr_write = NULL;

    /* Set up security attributes for inheritable handles */
    security_attrs.nLength = sizeof(SECURITY_ATTRIBUTES);
    security_attrs.bInheritHandle = TRUE;
    security_attrs.lpSecurityDescriptor = NULL;

    if (is_get_features) {
        /* Create pipes for stdout and stderr */
        if (!CreatePipe(&stdout_read, &stdout_write, &security_attrs, 0)) {
            fprintf(stderr, "ERROR: Failed to create stdout pipe\n");
            return 1;
        }

        if (!CreatePipe(&stderr_read, &stderr_write, &security_attrs, 0)) {
            fprintf(stderr, "ERROR: Failed to create stderr pipe\n");
            CloseHandle(stdout_read);
            CloseHandle(stdout_write);
            return 1;
        }

        /* Ensure the read handles are not inherited */
        SetHandleInformation(stdout_read, HANDLE_FLAG_INHERIT, 0);
        SetHandleInformation(stderr_read, HANDLE_FLAG_INHERIT, 0);

        /* Set up startup info with redirected output */
        startup_info.dwFlags = STARTF_USESTDHANDLES;
        startup_info.hStdOutput = stdout_write;
        startup_info.hStdError = stderr_write;
        startup_info.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    }

    /* Create mutable copy of command line for CreateProcess */
    char* mutable_cmdline = _strdup(command_line);
    if (mutable_cmdline == NULL) {
        fprintf(stderr, "ERROR: Memory allocation failed for command line\n");
        if (is_get_features) {
            CloseHandle(stdout_read);
            CloseHandle(stdout_write);
            CloseHandle(stderr_read);
            CloseHandle(stderr_write);
        }
        return 1;
    }

    /* Create the process */
    BOOL success = CreateProcess(
        NULL,               /* No module name (use command line) */
        mutable_cmdline,    /* Command line */
        NULL,               /* Process handle not inheritable */
        NULL,               /* Thread handle not inheritable */
        is_get_features,    /* Inherit handles if redirecting output */
        is_get_features ? CREATE_NO_WINDOW : 0, /* Creation flags */
        NULL,               /* Use parent's environment block */
        NULL,               /* Use parent's starting directory */
        &startup_info,      /* Pointer to STARTUPINFO structure */
        &process_info       /* Pointer to PROCESS_INFORMATION structure */
    );

    free(mutable_cmdline);

    /* Close write ends of pipes so child process can exit */
    if (is_get_features) {
        CloseHandle(stdout_write);
        CloseHandle(stderr_write);
    }

    if (!success) {
        DWORD error_code = GetLastError();
        fprintf(stderr, "ERROR: CreateProcess failed (Error %lu)\n", error_code);

        if (is_get_features) {
            CloseHandle(stdout_read);
            CloseHandle(stderr_read);
        }

        return 1;
    }

    /* Handle output interception if needed */
    if (is_get_features) {
        /* Buffer for reading output */
        char output_buffer[OUTPUT_BUFFER_SIZE];
        DWORD bytes_read = 0;
        BOOL read_result = FALSE;

        /* Read and process stdout */
        while (1) {
            /* Check if process has finished */
            DWORD wait_result = WaitForSingleObject(process_info.hProcess, 100);
            if (wait_result == WAIT_OBJECT_0) {
                /* Process has finished, read any remaining output */
                do {
                    read_result = ReadFile(stdout_read, output_buffer,
                                         sizeof(output_buffer) - 1, &bytes_read, NULL);

                    if (read_result && bytes_read > 0) {
                        /* Process output chunk */
                        char* processed = process_output_chunk(output_buffer, bytes_read);
                        if (processed != NULL) {
                            printf("%.*s", (int)strlen(processed), processed);
                            fflush(stdout);
                            free(processed);
                        } else {
                            /* If processing failed, output original */
                            printf("%.*s", (int)bytes_read, output_buffer);
                            fflush(stdout);
                        }
                    }
                } while (read_result && bytes_read > 0);
                break;
            } else if (wait_result == WAIT_TIMEOUT) {
                /* Process still running, try to read if data is available */
                DWORD bytes_available = 0;
                if (PeekNamedPipe(stdout_read, NULL, 0, NULL, &bytes_available, NULL) &&
                    bytes_available > 0) {

                    read_result = ReadFile(stdout_read, output_buffer,
                                         sizeof(output_buffer) - 1, &bytes_read, NULL);

                    if (read_result && bytes_read > 0) {
                        /* Process output chunk */
                        char* processed = process_output_chunk(output_buffer, bytes_read);
                        if (processed != NULL) {
                            printf("%.*s", (int)strlen(processed), processed);
                            fflush(stdout);
                            free(processed);
                        } else {
                            /* If processing failed, output original */
                            printf("%.*s", (int)bytes_read, output_buffer);
                            fflush(stdout);
                        }
                    }
                }
            } else {
                /* Wait failed, break */
                break;
            }
        }

        /* Read and pass through stderr unchanged */
        while (1) {
            DWORD bytes_available = 0;
            if (!PeekNamedPipe(stderr_read, NULL, 0, NULL, &bytes_available, NULL)) {
                break;
            }

            if (bytes_available > 0) {
                read_result = ReadFile(stderr_read, output_buffer,
                                     sizeof(output_buffer) - 1, &bytes_read, NULL);

                if (read_result && bytes_read > 0) {
                    /* Output stderr unchanged */
                    fwrite(output_buffer, 1, bytes_read, stderr);
                    fflush(stderr);
                }
            } else {
                /* No more data in stderr, check if process has finished */
                if (WaitForSingleObject(process_info.hProcess, 100) == WAIT_OBJECT_0) {
                    break;
                }
            }
        }

        /* Close pipe handles */
        CloseHandle(stdout_read);
        CloseHandle(stderr_read);
    } else {
        /* Not a get-features command, wait for process to complete */
        WaitForSingleObject(process_info.hProcess, INFINITE);
    }

    /* Get the exit code */
    DWORD exit_code = 0;
    if (!GetExitCodeProcess(process_info.hProcess, &exit_code)) {
        fprintf(stderr, "WARNING: Failed to get process exit code\n");
        exit_code = 1;
    }

    /* Close process and thread handles */
    CloseHandle(process_info.hProcess);
    CloseHandle(process_info.hThread);

    if (!is_get_features) {
        printf("\n[DISM WRAPPER] Process completed with exit code %lu\n", exit_code);
    }

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
    printf("[DISM WRAPPER] Version 2.1 - IIS Legacy SnapIn Interceptor\n");
    printf("[DISM WRAPPER] Detected command: ");
    for (int i = 0; i < argc; i++) {
        printf("%s ", argv[i]);
    }
    printf("\n");

    /* Check if this is a get-features command */
    bool is_get_features = is_get_features_command(argc, argv);

    /* Check for legacy feature in arguments */
    int legacy_count = count_legacy_features(argc, argv);

    if (legacy_count > 0) {
        /* Legacy feature found - perform replacement */
        printf("[DISM WRAPPER] Detected %d occurrence(s) of '%s'\n",
               legacy_count, LEGACY_FEATURE_NAME);
        printf("[DISM WRAPPER] Replacing with 2 modern IIS management features\n");

        /* Build new command line with replacements */
        char new_cmdline[MAX_CMD_LENGTH];
        if (!build_replacement_command_line(argc, argv, new_cmdline, sizeof(new_cmdline))) {
            fprintf(stderr, "ERROR: Failed to build replacement command line\n");
            return 1;
        }

        /* Execute the modified command */
        return execute_dism_command(new_cmdline, is_get_features);
    } else {
        /* No legacy feature - pass through unchanged */
        printf("[DISM WRAPPER] No legacy features detected in command line\n");
        if (is_get_features) {
            printf("[DISM WRAPPER] Will intercept and modify /get-features output\n");
        }

        /* Build command line without modifications */
        char new_cmdline[MAX_CMD_LENGTH];
        if (!build_passthrough_command_line(argc, argv, new_cmdline, sizeof(new_cmdline))) {
            fprintf(stderr, "ERROR: Failed to build pass-through command line\n");
            return 1;
        }

        /* Execute the original command */
        return execute_dism_command(new_cmdline, is_get_features);
    }
}
