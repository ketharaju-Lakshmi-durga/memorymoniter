#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <time.h>

#define ALLOCATION_SIZE 1048576  // Size of each allocation in bytes (1MB)
#define SLEEP_TIME 2             // Time to sleep between allocations in seconds
#define FREE_DELAY 1             // Time to sleep after freeing memory to observe changes

long upper_limit_kb = 0;
long lower_limit_kb = 0;

void read_config(const char *file) {
    FILE *fp = fopen("config.cfg", "r");
    if (fp == NULL) {
        fprintf(stderr, "Could not open config file\n");
        exit(EXIT_FAILURE);
    }

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        if (sscanf(line, "UPPER_LIMIT=%ld", &upper_limit_kb) == 1) {
            continue;
        }
        if (sscanf(line, "LOWER_LIMIT=%ld", &lower_limit_kb) == 1) {
            continue;
        }
    }

    fclose(fp);

    if (upper_limit_kb <= 0 || lower_limit_kb <= 0 || lower_limit_kb >= upper_limit_kb) {
        fprintf(stderr, "Invalid or misconfigured limits in config file.\n");
        exit(EXIT_FAILURE);
    }
}

void log_details(const char *message) {
    FILE *log_fp = fopen("process_log.txt", "a");
    if (log_fp == NULL) {
        fprintf(stderr, "Could not open log file\n");
        exit(EXIT_FAILURE);
    }

    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    char time_str[100];
    strftime(time_str, sizeof(time_str) - 1, "%a %b %d %T %Z %Y", t);
    fprintf(log_fp, "%s: %s\n", time_str, message);
    fclose(log_fp);
}

int main(int argc, char *argv[]) {
    char log_message[256];
    if (fork() == 0) {  // Create a child process

        // Read configuration from the config file
        read_config(argv[1]);

        printf("Starting intermittent high memory usage simulator with fluctuations...\n");
        printf("Upper limit: %ld KB, Lower limit: %ld KB\n", upper_limit_kb, lower_limit_kb);

        long total_allocated = 0;
        int up = 1;
        char **memory_blocks = NULL;
        size_t block_count = 0;

        // Continuously allocate and free memory to simulate intermittent high memory usage
        while (1) {
            if (up) {
                // Allocate memory
                char *memory_block = (char *)malloc(ALLOCATION_SIZE);
                if (memory_block == NULL) {
                    fprintf(stderr, "Memory allocation failed\n");
                   // log_details("Memory allocation failed");
                    exit(EXIT_FAILURE);
                }

                // Fill the allocated memory with some data
                memset(memory_block, 'A', ALLOCATION_SIZE);

                // Update total allocated memory
                total_allocated += ALLOCATION_SIZE / 1024;  // Convert bytes to KB

                // Store the allocated block pointer
                block_count++;
                memory_blocks = (char **)realloc(memory_blocks, block_count * sizeof(char *));
                if (memory_blocks == NULL) {
                    fprintf(stderr, "Memory reallocation failed\n");
                   // log_details("Memory reallocation failed");
                    exit(EXIT_FAILURE);
                }
                memory_blocks[block_count - 1] = memory_block;

                // Print and log the current memory allocation
                printf("Allocated %ld KB of memory, Total allocated: %ld KB\n", ALLOCATION_SIZE / 1024, total_allocated);
        
               // snprintf(log_message, sizeof(log_message), "Allocated %ld KB of memory, Total allocated: %ld KB", ALLOCATION_SIZE / 1024, total_allocated);
               // log_details(log_message);

                // Check if total allocated memory crosses the upper limit
                if (total_allocated >= upper_limit_kb) {
                    printf("Upper limit reached, will now free memory intermittently...\n");
                    snprintf(log_message, sizeof(log_message), "Policy2: Process (PID: %d), command: %s - memory usage crossed upper limit: %ld KB", getpid(), argv[0], total_allocated);
                    log_details(log_message);

                    up = 0;
                }
            } else {
                // Free some memory
                if (block_count > 0) {
                    free(memory_blocks[block_count - 1]);
                    block_count--;
                    memory_blocks = (char **)realloc(memory_blocks, block_count * sizeof(char *));
                    total_allocated -= ALLOCATION_SIZE / 1024;
                    printf("Freed %ld KB of memory, Total allocated: %ld KB\n", ALLOCATION_SIZE / 1024, total_allocated);
               //     char log_message[256];
                   // snprintf(log_message, sizeof(log_message), "Freed %ld KB of memory, Total allocated: %ld KB", ALLOCATION_SIZE / 1024, total_allocated);
                   // log_details(log_message);
                }

                // Check if total allocated memory drops below the lower limit
                if (total_allocated <= lower_limit_kb) {
                    printf("Lower limit reached, will now allocate memory intermittently...\n");
                    snprintf(log_message, sizeof(log_message), "Policy2: Process (PID: %d), command: %s - memory usage dropped below lower limit: %ld KB", getpid(), argv[0], total_allocated);
                    log_details(log_message);
                    up = 1;
                }

                // Sleep for a specified time to allow the operating system to update the RSS value
                sleep(FREE_DELAY);
            }

            // Sleep for a specified time
            sleep(SLEEP_TIME);
        }

        // Free remaining allocated memory
        for (size_t i = 0; i < block_count; i++) {
            free(memory_blocks[i]);
        }
        free(memory_blocks);
    }

    return 0;
}
