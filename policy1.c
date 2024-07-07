#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <time.h>

#define ALLOCATION_SIZE 1048576  // Size of each allocation in bytes
#define SLEEP_TIME 1             // Time to sleep between allocations in seconds

void read_config(const char *file, long *upper_limit_kb, long *lower_limit_kb) {
    FILE *fp = fopen("config.cfg", "r");
    if (fp == NULL) {
        fprintf(stderr, "Could not open config file\n");
        exit(EXIT_FAILURE);
    }

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        if (sscanf(line, "UPPER_LIMIT=%ld", upper_limit_kb) == 1) {
            continue;
        }
        if (sscanf(line, "LOWER_LIMIT=%ld", lower_limit_kb) == 1) {
            continue;
        }
    }

    fclose(fp);

    if (*upper_limit_kb <= 0 || *lower_limit_kb <= 0) {
        fprintf(stderr, "Invalid limit values in config file. Both upper and lower limits must be positive integers.\n");
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
    fork();  // Simulate process forking
    long upper_limit_kb = 0;
    long lower_limit_kb = 0;

    // Read configuration from the config file
    read_config(argv[1], &upper_limit_kb, &lower_limit_kb);

    printf("Starting memory leak simulator...\n");
    printf("Upper limit: %ld KB, Lower limit: %ld KB\n", upper_limit_kb, lower_limit_kb);
   // log_details("Starting memory leak simulator...");
   // log_details("Configuration loaded successfully.");

    long total_allocated = 0;

    // Continuously allocate memory without releasing it
    while (1) {
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

        // Print the current memory allocation
        printf("Allocated %ld KB of memory, Total allocated: %ld KB\n", ALLOCATION_SIZE / 1024, total_allocated);

        // Log the current memory allocation
        char log_message[256];
       // snprintf(log_message, sizeof(log_message), "Policy1: Process (PID: %d), command: %s - memory usage crossed upper limit: %ld KB", getpid(), argv[0], total_allocated);
       // log_details(log_message);

        // Check if total allocated memory crosses the upper limit
        if (total_allocated >= upper_limit_kb) {
            printf("Upper limit reached, continuing to allocate more memory...\n");
           // log_details("Upper limit reached, continuing to allocate more memory...");

            // Continue allocating to simulate memory leak violation
            while (1) {
                memory_block = (char *)malloc(ALLOCATION_SIZE);
                if (memory_block == NULL) {
                    fprintf(stderr, "Memory allocation failed\n");
                    log_details("Memory allocation failed");
                    exit(EXIT_FAILURE);
                }

                memset(memory_block, 'A', ALLOCATION_SIZE);

                total_allocated += ALLOCATION_SIZE / 1024;
                printf("Allocated %ld KB of memory, Total allocated: %ld KB\n", ALLOCATION_SIZE / 1024, total_allocated);
                snprintf(log_message, sizeof(log_message), "Policy1: Process (PID: %d), command: %s - memory usage crossed upper limit: %ld KB", getpid(), argv[0], total_allocated);
                log_details(log_message);

                sleep(SLEEP_TIME);
            }
        }

        // Sleep for a specified time
        sleep(SLEEP_TIME);
    }

    return 0;
}
