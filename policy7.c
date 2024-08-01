#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <time.h>

#define SMALL_ALLOCATION_SIZE 256  // Size of each small allocation in KB
#define SLEEP_TIME 10               // Time to sleep between allocations in seconds

// Configuration variables
long UPPER_LIMIT;
long LOWER_LIMIT;
int TIME_FRAME;
int FLUCTUATION_RANGE = 3000; // Fluctuation range above the upper limit

// Function to read configuration from file
void read_config(const char *file) {
    FILE *fp = fopen("config.cfg", "r");
    if (fp == NULL) {
        fprintf(stderr, "Could not open config file\n");
        exit(EXIT_FAILURE);
    }

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        if (sscanf(line, "UPPER_LIMIT=%ld", &UPPER_LIMIT) == 1) continue;
        if (sscanf(line, "LOWER_LIMIT=%ld", &LOWER_LIMIT) == 1) continue;
        if (sscanf(line, "TIME_FRAME=%d", &TIME_FRAME) == 1) continue;
    }

    fclose(fp);

    if (UPPER_LIMIT <= 0 || LOWER_LIMIT <= 0) {
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

void allocate_memory(long size, int is_fluctuation) {
    static char **memory_blocks = NULL;
    static int num_blocks = 0;

    memory_blocks = (char **)realloc(memory_blocks, (num_blocks + 1) * sizeof(char *));
    if (memory_blocks == NULL) {
        fprintf(stderr, "Memory allocation failed\n");
        log_details("Memory allocation failed");
        exit(1);
    }

    memory_blocks[num_blocks] = (char *)malloc(size * 1024);
    if (memory_blocks[num_blocks] == NULL) {
        fprintf(stderr, "Memory allocation failed\n");
        log_details("Memory allocation failed");
        exit(1);
    }
    memset(memory_blocks[num_blocks], 'A', size * 1024);
    num_blocks++;

    if (is_fluctuation) {
        printf("Maintained %ld KB of memory\n", size);
    } else {
        printf("Allocated %ld KB of memory\n", size);
    }
    sleep(SLEEP_TIME);
}

void deallocate_memory(long size) {
    static char **memory_blocks = NULL;
    static int num_blocks = 0;

    if (num_blocks > 0) {
        free(memory_blocks[num_blocks - 1]);
        num_blocks--;
        printf("Deallocated %ld KB of memory\n", size);
        sleep(SLEEP_TIME);
    }
}

void simulate_memory_usage(const char *config_file) {
    read_config(config_file);

    printf("Starting memory leak simulator...\n");
    printf("Upper limit: %ld KB, Lower limit: %ld KB\n", UPPER_LIMIT, LOWER_LIMIT);

    long total_allocated = 0;

    // Step 1: Gradually increase to cross the upper limit
    while (total_allocated < UPPER_LIMIT) {
        allocate_memory(SMALL_ALLOCATION_SIZE, 0);
        total_allocated += SMALL_ALLOCATION_SIZE;  // Accumulate memory
    }

    // Step 2: Fluctuate above the upper limit for the specified time frame
    time_t start_time = time(NULL);
    while (difftime(time(NULL), start_time) < TIME_FRAME) {
        long fluctuation = rand() % (FLUCTUATION_RANGE / 2);
        long fluctuated_size = UPPER_LIMIT + fluctuation;
        allocate_memory(fluctuated_size, 1);
    }

    // Step 3: Continuous decrease in memory usage
    while (1) {
        deallocate_memory(SMALL_ALLOCATION_SIZE);
        total_allocated -= SMALL_ALLOCATION_SIZE;  // Reduce memory

        // Log the current memory allocation
        char log_message[256];
        snprintf(log_message, sizeof(log_message), "Policy7: Process (PID: %d), memory usage decreased: %ld KB", getpid(), total_allocated);
        log_details(log_message);

        sleep(SLEEP_TIME);
    }
}

int main(int argc, char *argv[]) {

    simulate_memory_usage(argv[1]);

    return 0;
}
