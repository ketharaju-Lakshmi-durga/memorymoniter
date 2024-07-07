#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define ALLOCATION_SIZE (1024 * 1024 * 1024)  // 1 GB per allocation
#define MAX_ATTEMPTS 5

void read_config(const char *file, long *upper_limit_kb) {
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
    }

    fclose(fp);

    if (*upper_limit_kb <= 0) {
        fprintf(stderr, "Invalid upper limit value in config file. It must be a positive integer.\n");
        exit(EXIT_FAILURE);
    }
}

int main(int argc, char *argv[]) {
   
    long upper_limit_kb = 0;
    read_config(argv[1], &upper_limit_kb);

    printf("Starting memory allocation failure simulator...\n");
    printf("Upper limit: %ld KB\n", upper_limit_kb);

    long total_allocated = 0;

    while (1) {
        char *memory_block = (char *)malloc(ALLOCATION_SIZE);
        if (memory_block == NULL) {
            fprintf(stderr, "Memory allocation failed after allocating %ld KB\n", total_allocated);
            sleep(1);  // Optional delay before retrying
            continue;   // Continue to retry allocation
        }

        memset(memory_block, 'A', ALLOCATION_SIZE);
        total_allocated += ALLOCATION_SIZE / 1024;  // Convert bytes to KB

        printf("Allocated %ld KB of memory, Total allocated: %ld KB\n", ALLOCATION_SIZE / 1024, total_allocated);
        free(memory_block);
        sleep(1);  // Optional delay between allocations

        // Exit the loop if the total allocated exceeds the upper limit
        if (total_allocated >= upper_limit_kb) {
            break;
        }
    }

    return 0;
}
