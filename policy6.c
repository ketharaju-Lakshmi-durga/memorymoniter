#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>

#define MIN_ALLOCATION 10000    // Minimum memory allocation size in bytes
#define MAX_ALLOCATION 1000000  // Maximum memory allocation size in bytes
#define MIN_SLEEP 1             // Minimum sleep time in seconds
#define MAX_SLEEP 5             // Maximum sleep time in seconds

void simulate_memory_usage() {
    srand(time(NULL));

    while (1) {
        // Randomly choose to allocate or deallocate memory
        if (rand() % 2) {
            // Allocate random memory size between MIN_ALLOCATION and MAX_ALLOCATION
            size_t size = rand() % (MAX_ALLOCATION - MIN_ALLOCATION + 1) + MIN_ALLOCATION;
            void *mem = malloc(size);
            if (mem == NULL) {
                perror("malloc");
                exit(EXIT_FAILURE);
            }
            printf("Allocated %zu bytes\n", size);
        } else {
            // Simulate deallocation by sleeping
            printf("Deallocating memory\n");
        }

        // Sleep for a random time
        sleep(rand() % (MAX_SLEEP - MIN_SLEEP + 1) + MIN_SLEEP);
    }
}

int main() {
    simulate_memory_usage();
    return 0;
}
