#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define ALLOCATION_STEP (1024 * 1024) // 1 MB per allocation

void read_config(const char *file, long *upper_limit_kb) {
    FILE *fp = fopen(file, "r");
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
   fork();
    long upper_limit_kb = 0;
    read_config("config.cfg", &upper_limit_kb);

    printf("Starting memory usage simulator near upper limit...\n");
    printf("Upper limit: %ld KB\n", upper_limit_kb);

    long total_allocated_kb = 0;
    long allocation_step_kb = ALLOCATION_STEP / 1024; // Convert bytes to KB

    while (1) {
        if (total_allocated_kb + allocation_step_kb <= upper_limit_kb - allocation_step_kb) {
            char *memory_block = (char *)malloc(ALLOCATION_STEP);
            if (memory_block == NULL) {
                fprintf(stderr, "Memory allocation failed after allocating %ld KB\n", total_allocated_kb);
                break;
            }

            memset(memory_block, 'A', ALLOCATION_STEP);
            total_allocated_kb += allocation_step_kb;

            printf("Total allocated memory is near the upper limit: %ld KB\n", total_allocated_kb);
            sleep(1); // Sleep for a second before next allocation
        } else {
            printf("Memory usage near upper limit, total allocated: %ld KB\n", total_allocated_kb);
            sleep(5); // Sleep for 5 seconds to simulate consistent usage near the upper limit
        }
    }

    return 0;
}
