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

LOG_FILE="process_log.txt"

# Function to log details
log_details() {
    local message="$1"
    echo "$(date +"%a %b %d %T %Z %Y"): $message" >> "$LOG_FILE"
}

# Function to get RSS memory usage of each process in KB
get_process_memory_usage() {
    ps -eo pid,comm,rss --sort=-rss | awk '$3 ~ /^[0-9]+$/'
}

# Initialize variables for Policy 5
declare -A policy5_tracking

# Initialize email message buffer
email_message=""

# Monitoring loop
while true; do

   email_message="Memory Usage Alert:\n"  # Initialize email_message for each iteration

    while read -r pid comm rss; do
        # Skip the header line
        if [[ "$pid" == "PID" ]]; then
            continue
        fi

       # Check if RSS exceeds the upper limit for Policy 1
        if [[ $rss -gt $UPPER_LIMIT ]]; then
            log_details "Policy1: Process (PID: $pid), commad: $comm - memory usage crossed upper limit: ${rss}KB"

            # Wait for the specified wait time
            sleep $WAIT_TIME

            # Check memory usage again
            new_rss=$(ps -p $pid -o rss=)

            if [[ $new_rss -gt $UPPER_LIMIT && $new_rss -gt $rss ]]; then
                log_details "Policy1: Process $comm (PID: $pid) memory usage is still increasing: ${new_rss}KB"
                #send_mail "$SUBJECT" "Policy1: Process $comm (PID: $pid) memory usage has crossed the upper limit and is increasing. Current usage: ${new_rss}KB"$'\n'
                email_message+="Policy1: Process comm:$comm (PID: $pid) memory usage has crossed the upper limit and is increasing. Current usage: ${new_rss}KB"$'\n'
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

            log_details "Policy2: Process (PID: $pid) memory usage crossed upper limit: ${rss}KB"

            # Check if breaches are too frequent
            if [[ $breach_count -gt $FREQUENCY_THRESHOLD ]]; then
                #send_mail "$SUBJECT" "Policy2 Frequent Memory Breach Alert:Process $comm (PID: $pid) frequently breaching the upper memory limit. Breached $breach_count times in the last $TIME_FRAME seconds.\n"
                email_message+="Policy2 Frequent Memory Breach Alert:Process comm: $comm (PID: $pid) frequently breaching the upper memory limit. Breached $breach_count times in the last $TIME_FRAME seconds."$'\n'
                breach_count=0  # Reset the count after sending alert
                log_details "Sent Mail: Policy2 Frequent Memory Breach Alert" "Process comm: $comm (PID: $pid) frequently breaching the upper memory limit. Breached $breach_count times in the last $TIME_FRAME seconds."
            fi
        fi

        # Check if memory usage returns below the lower limit for Policy 2
        if [[ $rss -lt $LOWER_LIMIT ]]; then
            log_details "Policy2: Process (PID: $pid) memory usage returned to normal: ${rss}KB"
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
                    log_details "Policy3: Process (PID: $pid) memory usage has been gradually declining below lower limit for $TIME_FRAME seconds: ${rss}KB"
                    unset policy3_start_times[$pid]
                fi
            fi
        else
            unset policy3_start_times[$pid]
        fi

      # Initialize flag for Policy 4
       allocation_failed=false

      # Check for memory allocation failure for Policy 4
        if [[ "$comm" == "policy4" && $rss -lt $LOWER_LIMIT ]]; then
            log_details "Memory allocation failed after allocating 0 KB"
            allocation_failed=true
        fi

    # Check if memory allocation failure was detected for Policy4
    if $allocation_failed; then
        log_details "Policy4: Memory allocation failure detected (PID: $pid). Please check the log file for details."
        #send_mail "$SUBJECT" "Policy4: Memory allocation failure detected (PID: $pid). Please check the log file for details.\n"
        emaail_message+="Policy4: Memory allocation failure detected (PID: $pid). Please check the log file for details."$'\n'
        log_details "Sent Mail--- Policy4: Memory Allocation failure for process (PID: $pid)"
    fi

        # Check if RSS is consistently near the upper limit for Policy 5
        if [[ $rss -gt $((UPPER_LIMIT - 1000)) && $rss -lt $UPPER_LIMIT ]]; then
            current_time=$(date +%s)

            if [[ -z ${policy5_tracking[$pid]} ]]; then
                policy5_tracking[$pid]=$current_time
            else
                start_time=${policy5_tracking[$pid]}
                elapsed_time=$((current_time - start_time))

                if [[ $elapsed_time -ge $TIME_FRAME ]]; then
                    log_details "Policy5: Process comm: $comm (PID: $pid) memory usage has been near the upper limit for $TIME_FRAME seconds: ${rss}KB"
                    #send_mail "$SUBJECT" "Policy5: Process $comm (PID: $pid) memory usage has been near the upper limit for $TIME_FRAME seconds: ${rss}KB\n"
                    email_message+="Policy5: Process comm: $comm (PID: $pid) memory usage has been near the upper limit for $TIME_FRAME seconds: ${rss}KB"$'\n'
                    log_details "Sent Mail--- Policy5 for process (PID: $pid)"
                    unset policy5_tracking[$pid]
                fi
            fi
        else
            unset policy5_tracking[$pid]
        fi

    done < <(get_process_memory_usage)

    if [[ -n "$email_message" ]]; then
        send_mail "${SUBJECT} Memory Usage Alerts" "$email_message"
        email_message=""
    fi

    # Send email with all collected details if there are any alerts
   # if [[ -n "$email_message" ]]; then
    #    send_mail "${SUBJECT} Memory Usage Alerts" "$email_message"
   # fi

    # Sleep before the next check
   # sleep $SLEEP_TIME
done
