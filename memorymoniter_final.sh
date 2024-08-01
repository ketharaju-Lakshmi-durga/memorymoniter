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
    ps -u $(whoami) -eo pid,comm,rss --sort=-rss | awk '$3 ~ /^[0-9]+$/ && ($2 ~ /^-bash$/ || $2 ~ /^\/bin\/bash$/ || $2 ~ /^bash$/ || $2 ~ /^sh$/ || $2 ~ /^sleep$/ || $2 ~ /^\.\/.*$/ || $2 ~ /^policy.*/ || $2 ~ /^.*\.sh$/)'
}

# Function to calculate rate of change
calculate_rate_of_change() {
    local current_rss=$1
    local previous_rss=$2
    local time_diff=$3

    if [[ $time_diff -gt 0 ]]; then
        local rss_diff=$((current_rss - previous_rss))
        local rate_of_change=$(echo "scale=2; $rss_diff / $time_diff" | bc 2>/dev/null)
        echo "$rate_of_change"
    else
        echo "0"
    fi
}

# Function to categorize rate of change
categorize_rate() {
    local rate_of_change=$1

    if (( $(echo "$rate_of_change <= $GRADUAL_THRESHOLD && $rate_of_change > 0" | bc 2>/dev/null) )); then
        echo "gradual increase"
    elif (( $(echo "$rate_of_change >= -$GRADUAL_THRESHOLD && $rate_of_change <= 0" | bc 2>/dev/null) )); then
        echo "gradual decrease"
    elif (( $(echo "$rate_of_change > $EXPONENTIAL_THRESHOLD && $rate_of_change < $SUDDEN_THRESHOLD" | bc 2>/dev/null) )); then
        echo "exponential increase"
    elif (( $(echo "$rate_of_change < -$EXPONENTIAL_THRESHOLD && $rate_of_change > -$SUDDEN_THRESHOLD" | bc 2>/dev/null) )); then
        echo "exponential decrease"
    elif (( $(echo "$rate_of_change > $GRADUAL_THRESHOLD && $rate_of_change < $EXPONENTIAL_THRESHOLD" | bc 2>/dev/null) )); then
        echo "steep increase"
    elif (( $(echo "$rate_of_change < -$GRADUAL_THRESHOLD && $rate_of_change > -$EXPONENTIAL_THRESHOLD" | bc 2>/dev/null) )); then
        echo "steep decrease"
    elif (( $(echo "$rate_of_change > $SUDDEN_THRESHOLD" | bc 2>/dev/null) )); then
        echo "sudden increase"
    elif (( $(echo "$rate_of_change < -$SUDDEN_THRESHOLD" | bc 2>/dev/null) )); then
        echo "sudden decrease"
    fi
}

# Initialize variables
declare -A previous_memory_usage
declare -A previous_time
declare -A policy5_tracking
declare -A policy3_start_times
declare -A policy7_tracking

counter=0
sudden_breach=0
iteration_counter=1
email_message=""

# Monitoring loop
while true; do
   # email_message="Memory Usage Alert:"$'\n'  # Initialize email_message for each iteration
    log_details "[ ITERATION $iteration_counter ]"

    while read -r pid comm rss; do
        current_time=$(date +%s)

        if [[ -n ${previous_memory_usage[$pid]} ]]; then
            previous_rss=${previous_memory_usage[$pid]}
            time_diff=$((current_time - previous_time[$pid]))

            rate_of_change=$(calculate_rate_of_change $rss $previous_rss $time_diff)
            rate_category=$(categorize_rate $rate_of_change)

            # Log rate of change
            log_details "[ I$iteration_counter ]Process comm: $comm (PID: $pid) has a $rate_category change in memory usage. Rate: ${rate_of_change}KB/s, RSS: ${rss}KB"
        fi

        # Update previous values
        previous_memory_usage[$pid]=$rss
        previous_time[$pid]=$current_time

        # Check if RSS exceeds the upper limit for Policy 1
        if [[ $rss -gt $UPPER_LIMIT ]]; then
            # Log initial detection
            log_details "[ I$iteration_counter ]Policy1: Process (PID: $pid), command: $comm - memory usage crossed upper limit: ${rss}KB"

            # Wait for the specified wait time
            sleep $WAIT_TIME

            # Check memory usage again
            new_rss=$(ps -p $pid -o rss=)

            if [[ $new_rss -gt $UPPER_LIMIT && $new_rss -gt $rss ]]; then
                rate_of_change=$(calculate_rate_of_change $new_rss $rss $WAIT_TIME)
                rate_category=$(categorize_rate $rate_of_change)

                log_details "[ I$iteration_counter ]Policy1: Process comm: $comm (PID: $pid) increasing: ${new_rss} KB, Rate: $rate_of_change KB/s ($rate_category)"
                email_message+="[ I$iteration_counter ]Policy1: Process comm: $comm (PID: $pid) memory usage has crossed the upper limit and is increasing. Current usage: ${new_rss}KB, Rate: $rate_of_change KB/s ($rate_category)"$'\n'
                log_details "[ I$iteration_counter ]Sent Mail --- Policy1 Violation for process (PID: $pid)"
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

            log_details "[ I$iteration_counter ]Policy2 Frequent Memory Breach Alert: Process comm: $comm (PID: $pid) frequently breaching the upper memory limit. Breached $breach_count times in the last $TIME_FRAME seconds. Rate: $rate_of_change KB/s ($rate_category)\n"

            # Check if breaches are too frequent
            if [[ $breach_count -gt $FREQUENCY_THRESHOLD ]]; then
                rate_of_change=$(calculate_rate_of_change $rss $previous_rss $time_diff)
                rate_category=$(categorize_rate $rate_of_change)

                email_message+="[ I$iteration_counter ]Policy2 Frequent Memory Breach Alert: Process comm: $comm (PID: $pid) frequently breaching the upper memory limit. Breached $breach_count times in the last $TIME_FRAME seconds. Rate: $rate_of_change KB/s ($rate_category)"$'\n'
                breach_count=0  # Reset the count after sending alert
                log_details "[ I$iteration_counter ]Sent Mail: Policy2 Frequent Memory Breach Alert: Process comm: $comm (PID: $pid) frequently breaching the upper memory limit."
                #log_details "[ I$iteration_counter ]Sent Mail --- Policy2 Violation for process (PID: $pid)"
            fi
        fi

        # Check if memory usage returns below the lower limit for Policy 2
        if [[ $rss -lt $LOWER_LIMIT ]]; then
            rate_of_change=$(calculate_rate_of_change $rss $previous_rss $time_diff)
            rate_category=$(categorize_rate $rate_of_change)

            log_details "[ I$iteration_counter ]Policy2: Process (PID: $pid) comm: $comm memory usage returned to normal: ${rss}KB, Rate: $rate_of_change KB/s ($rate_category)"
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
                    log_details "[ I$iteration_counter ]Policy3: Process (PID: $pid) comm: $comm  memory usage has been gradually declining below lower limit for $TIME_FRAME seconds: ${rss}KB, Rate: $rate_of_change KB/s ($rate_category)"
                    email_message+="[ I$iteration_counter ]Policy3: Process (PID: $pid) comm: $comm  memory usage has been gradually declining below lower limit for $TIME_FRAME seconds: ${rss}KB, Rate: $rate_of_change KB/s ($rate_category)"$'\n'
                   # log_details "[ I$iteration_counter ]Sent Mail --- Policy3 Violation for process (PID: $pid)"
                    unset policy3_start_times[$pid]
                fi
            fi
        else
            unset policy3_start_times[$pid]
        fi

        # Check if RSS is consistently near the upper limit for Policy 4
        if [[ $rss -gt $((UPPER_LIMIT - 1000)) && $rss -lt $UPPER_LIMIT ]]; then
            current_time=$(date +%s)

            if [[ -z ${policy4_tracking[$pid]} ]]; then
                policy4_tracking[$pid]=$current_time
            else
                start_time=${policy4_tracking[$pid]}
                elapsed_time=$((current_time - start_time))

                if [[ $elapsed_time -ge $TIME_FRAME ]]; then
                    rate_of_change=$(calculate_rate_of_change $rss $previous_rss $elapsed_time)
                    rate_category=$(categorize_rate $rate_of_change)
                    log_details "[ I$iteration_counter ]Policy4: Process (PID: $pid) comm: $comm memory usage consistently near upper limit for $TIME_FRAME seconds: ${rss}KB, Rate: $rate_of_change KB/s ($rate_category)"
                    email_message+="[ I$iteration_counter ]Policy4: Process (PID: $pid) comm: $comm  memory usage consistently near upper limit for $TIME_FRAME seconds: ${rss}KB, Rate: $rate_of_change KB/s ($rate_category)"$'\n'
                    #log_details "[ I$iteration_counter ]Sent Mail --- Policy4 Violation for process (PID: $pid)"
                    unset policy4_tracking[$pid]
                fi
            fi
        else
            unset policy4_tracking[$pid]
        fi

        # Policy 5: Persistent High and Increasing Memory Usage
        if ([[ $rss -gt $UPPER_LIMIT ]] && [[ ! -z ${policy5_tracking[$pid]} ]] && [[ ! -z ${policy5_start_time[$pid]} ]]); then
            start_time=${policy5_tracking[$pid]}
            elapsed_time=$((current_time - start_time))

            if [[ $elapsed_time -ge $TIME_FRAME ]]; then
                log_details "[ I$iteration_counter ]Policy5: Process comm: $comm (PID: $pid) memory usage constant for $TIME_FRAME seconds at ${rss}KB"

                # Check for increase in memory usage after constant period
                sleep $WAIT_TIME
                new_rss=$(ps -p $pid -o rss=)
                rate_of_change=$(calculate_rate_of_change $new_rss $rss $WAIT_TIME)
                rate_category=$(categorize_rate $rate_of_change)

                if [[ $new_rss -gt $rss ]]; then
                    log_details "[ I$iteration_counter ]Policy5: Process comm: $comm (PID: $pid) memory usage increasing after constant period: ${new_rss}KB, Rate: $rate_of_change KB/s ($rate_category)"
                    email_message+="[ I$iteration_counter ]Policy5: Process comm: $comm (PID: $pid) memory usage increasing after constant period. New usage: ${new_rss}KB, Rate: $rate_of_change KB/s ($rate_category)"$'\n'
                    #log_details "[ I$iteration_counter ]Sent Mail --- Policy5 Violation for process (PID: $pid)"                   
                    policy5_tracking[$pid]=$current_time # Reset tracking for continuous increase
                else
                    log_details "[ I$iteration_counter ]Policy5: Process comm: $comm (PID: $pid) memory usage did not increase: ${new_rss}KB, Rate: $rate_of_change KB/s ($rate_category)"
                fi
            fi
        else
            unset policy5_tracking[$pid]
            unset policy5_start_time[$pid]
        fi

        # Policy 6
        if (( $(echo "$rate_of_change > $SUDDEN_THRESHOLD" | bc 2>/dev/null) )) && [[ $rss -gt $UPPER_LIMIT ]]; then
            irregular_pattern=true
            sudden_breach=$((sudden_breach + 1))
            log_details "[ I$iteration_counter ]Policy6: Sudden increase detected for process comm: $comm (PID: $pid). Rate: ${rate_of_change}KB/s, ($rate_category)"
        elif (( $(echo "$rate_of_change < -$SUDDEN_THRESHOLD" | bc 2>/dev/null) )) && [[ $rss -gt $UPPER_LIMIT ]]; then
            irregular_pattern=true
            sudden_breach=$((sudden_breach + 1))
            log_details "[ I$iteration_counter ]Policy6: Sudden decrease detected for process comm: $comm (PID: $pid). Rate: ${rate_of_change}KB/s, ($rate_category)"
        fi

        if (( irregular_pattern && $sudden_breach > 5 )); then
            email_message+="[ I$iteration_counter ]Policy6: Irregular memory usage detected for process comm: $comm (PID: $pid). Rate: ${rate_of_change}KB/s, ($rate_category)"$'\n'
           # log_details "[ I$iteration_counter ]Sent Mail --- Policy6 Violation for process (PID: $pid)"       
        fi

        # Policy 7: Persistent High and Decreasing Memory Usage
        if [[ $rss -gt $UPPER_LIMIT ]]; then
            if [[ -z ${policy7_tracking[$pid]} ]]; then
                policy7_tracking[$pid]=$current_time
                log_details "[ I$iteration_counter ]Policy7: Process (PID: $pid), command: $comm - memory usage crossed upper limit: ${rss}KB"
            else
                start_time=${policy7_tracking[$pid]}
                elapsed_time=$((current_time - start_time))

                if [[ $elapsed_time -ge $TIME_FRAME ]]; then
                    log_details "[ I$iteration_counter ]Policy7: Process comm: $comm (PID: $pid) memory usage constant for $TIME_FRAME seconds at ${rss}KB"

                    # Check for decrease in memory usage after constant period
                    sleep $WAIT_TIME
                    new_rss=$(ps -p $pid -o rss=)
                    rate_of_change=$(calculate_rate_of_change $new_rss $rss $WAIT_TIME)
                    rate_category=$(categorize_rate $rate_of_change)

                    if [[ $new_rss -lt $rss ]]; then
                        log_details "[ I$iteration_counter ]Policy7: Process comm: $comm (PID: $pid) memory usage decreasing after constant period: ${new_rss}KB, Rate: $rate_of_change KB/s ($rate_category)"
                        email_message+="[ I$iteration_counter ]Policy7: Process comm: $comm (PID: $pid) memory usage decreasing after constant period. New usage: ${new_rss}KB, Rate: $rate_of_change KB/s ($rate_category)"$'\n'
                        #log_details "[ I$iteration_counter ]Sent Mail --- Policy7 Violation for process (PID: $pid)"
                        policy7_tracking[$pid]=$current_time # Reset tracking for continuous decrease
                    else
                        log_details "[ I$iteration_counter ]Policy7: Process comm: $comm (PID: $pid) memory usage did not decrease: ${new_rss}KB, Rate: $rate_of_change KB/s ($rate_category)"
                    fi
                fi
            fi
        else
            unset policy7_tracking[$pid]
        fi

    done < <(get_process_memory_usage)

    counter=$((counter + 1))
    iteration_counter=$((iteration_counter+1))

      # Send email if there are any alerts
    if [[ -n "$email_message" && $((counter % 3)) -eq 0 ]]; then
        send_mail "${SUBJECT} Memory Usage Alerts" "$email_message"
        log_details "----Email Sent for list of processess that violates policies"
        email_message=""
        sudden_breach=0
    fi

    log_details "Sleep 60 Seconds"
    sleep $SLEEP_TIME
done
