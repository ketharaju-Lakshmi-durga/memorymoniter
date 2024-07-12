#!/bin/bash

# Source the configuration file
CONFIG_FILE="config.cfg"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found!"
    exit 1
fi

# Function to send email
send_mail() {
    local subject=$1
    local message=$2
    echo "$message" | mail -s "$subject" "$EMAIL"
}

LOG_FILE="process_log1.txt"

# Function to log details
log_details() {
    local message="$1"
    echo "$(date +"%a %b %d %T %Z %Y"): $message" >> "$LOG_FILE"
}

# Function to get RSS memory usage of each process in KB
get_process_memory_usage() {
    ps -u $(whoami) -eo pid,comm,rss --sort=-rss | awk '$3 ~ /^[0-9]+$/'
}

# Function to calculate rate of change
calculate_rate_of_change() {
    local current_rss=$1
    local previous_rss=$2
    local time_diff=$3

    if [[ $time_diff -gt 0 ]]; then
        local rss_diff=$((current_rss - previous_rss))
        local rate_of_change=$(echo "scale=2; $rss_diff / $time_diff" | bc -l)
        echo "$rate_of_change"
    else
        echo "0"
    fi
}

# Function to categorize rate of change
categorize_rate() {
    local rate_of_change=$1

    if (( $(echo "$rate_of_change < $GRADUAL_THRESHOLD" | bc -l) )); then
        echo "gradual"
    elif (( $(echo "$rate_of_change > $STEEP_THRESHOLD" | bc -l) )); then
        echo "steep"
    else
        echo "exponential"
    fi
}

# Initialize variables
declare -A previous_memory_usage
declare -A previous_time
declare -A policy5_tracking
declare -A policy3_start_times

counter=0
# Monitoring loop
while true; do
    email_message="Memory Usage Alert:\n"  # Initialize email_message for each iteration

    while read -r pid comm rss; do
        # Skip the header line
        if [[ "$pid" == "PID" ]]; then
            continue
        fi

        current_time=$(date +%s)

        if [[ -n ${previous_memory_usage[$pid]} ]]; then
            previous_rss=${previous_memory_usage[$pid]}
            time_diff=$((current_time - previous_time[$pid]))

            rate_of_change=$(calculate_rate_of_change $rss $previous_rss $time_diff)
            rate_category=$(categorize_rate $rate_of_change)

            # Log rate of change
            log_details "Process com: $comm (PID: $pid) has a $rate_category change in memory usage. Rate: ${rate_of_change}KB/s, RSS: ${rss}KB"
        fi

        # Update previous values
        previous_memory_usage[$pid]=$rss
        previous_time[$pid]=$current_time

        # Check if RSS exceeds the upper limit for Policy 1
        if [[ $rss -gt $UPPER_LIMIT ]]; then
            #log_details "Policy1: Process (PID: $pid), command: $comm - memory usage crossed upper limit: ${rss}KB"

            # Wait for the specified wait time
            sleep $WAIT_TIME

            # Check memory usage again
            new_rss=$(ps -p $pid -o rss=)

            if [[ $new_rss -gt $UPPER_LIMIT && $new_rss -gt $rss ]]; then
                rate_of_change=$(calculate_rate_of_change $new_rss $rss $WAIT_TIME)
                rate_category=$(categorize_rate $rate_of_change)

                log_details "Policy1: Process  comm: $comm (PID: $pid)  increasing: ${new_rss} KB, Rate: $rate_of_change KB/s ($rate_category)"
                email_message+="Policy1: Process comm: $comm (PID: $pid) memory usage has crossed the upper limit and is increasing. Current usage: ${new_rss}KB, Rate: $rate_of_change KB/s ($rate_category)\n"
                log_details "Sent Mail --- Policy1 Violation for process (PID: $pid)"
            fi
        fi

        # Check if RSS exceeds the upper limit for Policy 2
        if [[ $rss -gt $UPPER_LIMIT ]]; then
            current_time=$(date +%s)
            time_since_last_breach=$((current_time - last_breach_time))

            # Check if the time since the last breach is within the TIME_FRAME
            if [[ $time_since_last_breach -le $TIME_FRAME ]]; then
                breach_count=$((breach_count + 1))
            else
                breach_count=1
            fi

            last_breach_time=$current_time

            log_details "Policy2 Frequent Memory Breach Alert: Process comm: $comm (PID: $pid) frequently breaching the upper memory limit. Breached $breach_count times in the last $TIME_FRAME seconds. Rate: $rate_of_change KB/s ($rate_category)\n"

            # Check if breaches are too frequent
            if [[ $breach_count -gt $FREQUENCY_THRESHOLD ]]; then
                rate_of_change=$(calculate_rate_of_change $rss $previous_rss $time_diff)
                rate_category=$(categorize_rate $rate_of_change)

                email_message+="Policy2 Frequent Memory Breach Alert: Process comm: $comm (PID: $pid) frequently breaching the upper memory limit. Breached $breach_count times in the last $TIME_FRAME seconds. Rate: $rate_of_change KB/s ($rate_category)\n"
                breach_count=0  # Reset the count after sending alert
                log_details "Sent Mail: Policy2 Frequent Memory Breach Alert: Process comm: $comm (PID: $pid) frequently breaching the upper memory limit.)"
            fi
        fi

        # Check if memory usage returns below the lower limit for Policy 2
        if [[ $rss -lt $LOWER_LIMIT ]]; then
            rate_of_change=$(calculate_rate_of_change $rss $previous_rss $time_diff)
            rate_category=$(categorize_rate $rate_of_change)

            log_details "Policy2: Process (PID: $pid) com : $comm memory usage returned to normal: ${rss}KB, Rate: $rate_of_change KB/s ($rate_category)"
        fi

        # Check for gradual decline below lower limit for Policy 3
        if [[ $rss -lt $LOWER_LIMIT ]]; then
            current_time=$(date +%s)

            if [[ -z ${policy3_start_times[$pid]} ]]; then
                policy3_start_times[$pid]=$current_time
            else
                start_time=${policy3_start_times[$pid]}
                elapsed_time=$((current_time - start_time))

                if [[ $elapsed_time -ge $TIME_FRAME ]]; then
                    rate_of_change=$(calculate_rate_of_change $rss $previous_rss $elapsed_time)
                    rate_category=$(categorize_rate $rate_of_change)

                    log_details "Policy3: Process (PID: $pid) memory usage has been gradually declining below lower limit for $TIME_FRAME seconds: ${rss}KB, Rate: $rate_of_change KB/s ($rate_category)"
                    unset policy3_start_times[$pid]
                fi
            fi
        else
            unset policy3_start_times[$pid]
        fi

        # Initialize flag for Policy 4
        

        # Check if RSS is consistently near the upper limit for Policy 5
        if [[ $rss -gt $((UPPER_LIMIT - 1000)) && $rss -lt $UPPER_LIMIT ]]; then
            current_time=$(date +%s)

            if [[ -z ${policy5_tracking[$pid]} ]]; then
                policy5_tracking[$pid]=$current_time
            else
                start_time=${policy5_tracking[$pid]}
                elapsed_time=$((current_time - start_time))

                if [[ $elapsed_time -ge $TIME_FRAME ]]; then
                    rate_of_change=$(calculate_rate_of_change $rss $previous_rss $elapsed_time)
                    rate_category=$(categorize_rate $rate_of_change)

                    log_details "Policy5: Process comm: $comm (PID: $pid) memory usage has been near the upper limit for $TIME_FRAME seconds: ${rss}KB, Rate: $rate_of_change KB/s ($rate_category)"
                    email_message+="Policy5: Process comm: $comm (PID: $pid) memory usage has been near the upper limit for $TIME_FRAME seconds: ${rss}KB, Rate: $rate_of_change KB/s ($rate_category)\n"
                    log_details "Sent Mail--- Policy5 for process (PID: $pid)"
                    unset policy5_tracking[$pid]
                fi
            fi
        else
            unset policy5_tracking[$pid]
        fi
    
    done < <(get_process_memory_usage)
    counter=$((counter + 1))

    # Send email with
    if [[  -n "$email_message" && $((counter % 4)) -eq 0 ]]; then
        send_mail "${SUBJECT} Memory Usage Alerts" "$email_message"
        $counter=0
        $email_message=""
    fi

    # Sleep before the next check
   sleep $SLEEP_TIME
done

