#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

#define ALLOCATION_SIZE 262144  // Size of each allocation in bytes (256KB)
#define SLEEP_TIME 10           // Time to sleep between allocations in seconds

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

int main(int argc, char *argv[]) {
    fork();
    long upper_limit_kb = 0;
    long lower_limit_kb = 0;

    // Read configuration from the config file
    read_config(argv[1], &upper_limit_kb, &lower_limit_kb);

    printf("Starting gradual memory decline simulator...\n");
    printf("Upper limit: %ld KB, Lower limit: %ld KB\n", upper_limit_kb, lower_limit_kb);

    long total_allocated = upper_limit_kb; // Start at upper limit for simulation
    int free_memory = 1; // Flag to indicate whether to free memory
    char **memory_blocks = NULL;
    size_t block_count = upper_limit_kb / (ALLOCATION_SIZE / 1024);

    // Allocate initial memory to upper limit
    for (size_t i = 0; i < block_count; i++) {
        memory_blocks = (char **)realloc(memory_blocks, (i + 1) * sizeof(char *));
        if (memory_blocks == NULL) {
            fprintf(stderr, "Memory allocation failed\n");
            return EXIT_FAILURE;
        }
        memory_blocks[i] = (char *)malloc(ALLOCATION_SIZE);
        if (memory_blocks[i] == NULL) {
            fprintf(stderr, "Memory allocation failed\n");
            return EXIT_FAILURE;
        }
        memset(memory_blocks[i], 'A', ALLOCATION_SIZE);
    }

    printf("Memory initially allocated to upper limit: %ld KB\n", total_allocated);

    // Continuously monitor and adjust memory usage
    while (1) {
        if (free_memory && total_allocated > lower_limit_kb) {
            // Free memory
            free(memory_blocks[--block_count]);
            memory_blocks = (char **)realloc(memory_blocks, block_count * sizeof(char *));
            total_allocated -= ALLOCATION_SIZE / 1024;
            printf("Freed %ld KB of memory, Total allocated: %ld KB\n", ALLOCATION_SIZE / 1024, total_allocated);

            if (total_allocated <= lower_limit_kb) {
                printf("Memory usage has gradually declined below the lower limit.\n");
                free_memory = 0; // Stop freeing memory
            }
        }

        // Sleep for a specified time
        sleep(SLEEP_TIME);
    }

    // Free remaining allocated memory
    for (size_t i = 0; i < block_count; i++) {
        free(memory_blocks[i]);
    }
    free(memory_blocks);

    return 0;
}
