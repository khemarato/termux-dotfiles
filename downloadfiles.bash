#!/bin/bash

cd "$1"
echo "Will download files to '$(pwd)'"

# Create temporary files for the queue and communication
QUEUE_FILE=$(mktemp)
STATUS_PIPE=$(mktemp -u)
TIMING_DATA=$(mktemp)
mkfifo "$STATUS_PIPE"
exec {pipe_fd}<>"$STATUS_PIPE"

# Initialize timing data with Bayesian priors
# Format: size_mb duration_seconds
cat > "$TIMING_DATA" << EOF
0	1
1	13
10	121
EOF

# Ensure temp files are cleaned up on exit
trap 'rm -f "$QUEUE_FILE" "$STATUS_PIPE" "$TIMING_DATA"; jobs -p | xargs -r kill' EXIT INT TERM

# Function to calculate linear regression parameters (a, b) for y = ax + b
calculate_regression() {
    local data_file="$1"
    
    # Read data points
    local n=0
    local sum_x=0
    local sum_y=0
    local sum_xy=0
    local sum_x2=0
    
    while IFS=$'\t' read -r x y; do
        n=$((n + 1))
        sum_x=$(echo "$sum_x + $x" | bc -l)
        sum_y=$(echo "$sum_y + $y" | bc -l)
        sum_xy=$(echo "$sum_xy + $x * $y" | bc -l)
        sum_x2=$(echo "$sum_x2 + $x * $x" | bc -l)
    done < "$data_file"
    
    # Calculate slope (a) and intercept (b)
    local denominator=$(echo "$n * $sum_x2 - $sum_x * $sum_x" | bc -l)
    if [ $(echo "$denominator == 0" | bc -l) -eq 1 ]; then
        echo "1 10"  # Default fallback
        return
    fi
    
    local a=$(echo "scale=6; ($n * $sum_xy - $sum_x * $sum_y) / $denominator" | bc -l)
    local b=$(echo "scale=6; ($sum_y - $a * $sum_x) / $n" | bc -l)
    
    echo "$a $b"
}

# Function to predict download time for a given file size
predict_time() {
    local size_mb="$1"
    local regression_params=$(calculate_regression "$TIMING_DATA")
    local a=$(echo "$regression_params" | cut -d' ' -f1)
    local b=$(echo "$regression_params" | cut -d' ' -f2)
    
    local predicted_time=$(echo "scale=2; $a * $size_mb + $b" | bc -l)
    
    # Ensure minimum time of 1 second
    if [ $(echo "$predicted_time < 1" | bc -l) -eq 1 ]; then
        predicted_time=1
    fi
    
    echo "$predicted_time"
}

# Function to estimate total remaining time
estimate_remaining_time() {
    local total_time=0
    
    if [ -s "$QUEUE_FILE" ]; then
        while IFS=$'\t' read -r filename url size; do
            local predicted=$(predict_time "$size")
            total_time=$(echo "$total_time + $predicted" | bc -l)
        done < <(sort -t $'\t' -k 3 -n "$QUEUE_FILE")
    fi
    
    echo "$total_time"
}

# Function to format time in human-readable format
format_time() {
    local seconds="$1"
    local hours=$(echo "$seconds / 3600" | bc)
    local minutes=$(echo "($seconds % 3600) / 60" | bc)
    local secs=$(echo "$seconds % 60" | bc)
    
    if [ "$hours" -gt 0 ]; then
        printf "%dh %dm %ds" "$hours" "$minutes" "$secs"
    elif [ "$minutes" -gt 0 ]; then
        printf "%dm %ds" "$minutes" "$secs"
    else
        printf "%.1fs" "$seconds"
    fi
}

# Start background process to handle download queue
(
    # Process to read from the queue and execute downloads
    while true; do
        # Check if queue is empty
        if [ ! -s "$QUEUE_FILE" ]; then
            sleep 1
            continue
        fi

        # Get the smallest file (by size) from the queue
        NEXT_DOWNLOAD=$(sort -t $'\t' -k 3 -n "$QUEUE_FILE" | head -1)
        FILENAME=$(echo "$NEXT_DOWNLOAD" | cut -f1)
        URL=$(echo "$NEXT_DOWNLOAD" | cut -f2)
        SIZE=$(echo "$NEXT_DOWNLOAD" | cut -f3)

        # Record start time in milliseconds
        START_TIME=$(date +%s%3N)
        
        # Download the file
        if wget -q "$URL" -O "$FILENAME"; then
            END_TIME=$(date +%s%3N)
            DURATION_MS=$((END_TIME - START_TIME))
            DURATION_SEC=$(echo "scale=3; $DURATION_MS / 1000" | bc -l)

            # Add this data point to our timing data
            echo -e "$SIZE\t$DURATION_SEC" >> "$TIMING_DATA"

            # Remove this entry from the queue
            grep -v "^$FILENAME	$URL	$SIZE$" "$QUEUE_FILE" > "$QUEUE_FILE.tmp"
            mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"
            
            # Calculate remaining time estimate
            REMAINING_TIME=$(estimate_remaining_time)
            REMAINING_FORMATTED=$(format_time "$REMAINING_TIME")
            
            echo "SUCCESS: Downloaded '$FILENAME' ($SIZE MB) in $(format_time "$DURATION_SEC") | Est. remaining: $REMAINING_FORMATTED" > "$STATUS_PIPE" &
        else
            echo "FAILED: Could not download '$FILENAME' from $URL" > "$STATUS_PIPE" &
            
            # Remove this entry from the queue (don't add to timing data for failures)
            grep -v "^$FILENAME	$URL	$SIZE$" "$QUEUE_FILE" > "$QUEUE_FILE.tmp"
            mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"
        fi
        
    done
) &
QUEUE_PROCESSOR_PID=$!

# Function to display the current queue
display_queue() {
    echo "Current queue (smallest first):"
    if [ ! -s "$QUEUE_FILE" ]; then
        echo "  Queue is empty"
    else
        echo "  FILENAME | URL | SIZE(MB) | EST. TIME"
        sort -t $'\t' -k 3 -n "$QUEUE_FILE" | while read -r LINE; do
            FILENAME=$(echo "$LINE" | cut -f1)
            URL=$(echo "$LINE" | cut -f2)
            SIZE=$(echo "$LINE" | cut -f3)
            PREDICTED_TIME=$(predict_time "$SIZE")
            FORMATTED_TIME=$(format_time "$PREDICTED_TIME")
            echo "  $FILENAME | $URL | $SIZE MB | $FORMATTED_TIME"
        done
        
        # Show total estimated time
        TOTAL_REMAINING=$(estimate_remaining_time)
        TOTAL_FORMATTED=$(format_time "$TOTAL_REMAINING")
        echo "  Total estimated time remaining: $TOTAL_FORMATTED"
    fi
}

display_statuses() {
  if [[ -p "$STATUS_PIPE" ]]; then
    if read -t 0.01 -r line < "$STATUS_PIPE"; then
        echo "$line"
    fi
  fi
}

# Main input loop
while true; do
    echo -n "Enter filename (or empty to finish): "
    read -r FILENAME
    
    # Exit condition
    if [ -z "$FILENAME" ]; then
        break
    fi
    
    display_statuses
    
    echo -n "Enter URL: "
    read -r URL
    
    display_statuses
    
    echo -n "Enter file size in MB: "
    read -r SIZE
    
    display_statuses
    
    # Validate input
    if [ -z "$URL" ] || ! [[ "$SIZE" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "Invalid input. URL cannot be empty and size must be a number."
        continue
    fi
    
    # Add to queue
    echo -e "$FILENAME\t$URL\t$SIZE" >> "$QUEUE_FILE"
    echo "Added to queue: $FILENAME ($SIZE MB)"
    display_queue
done

echo "Waiting for downloads to complete..."

# Wait for queue to become empty
while [ -s "$QUEUE_FILE" ]; do
    sleep 1
    display_statuses
done

echo "All downloads completed. Exiting."