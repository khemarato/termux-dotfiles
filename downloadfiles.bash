#!/bin/bash

# Written together with Claude.ai

cd "$1"
echo "Will download files to '$(pwd)'"

# Create temporary files for the queue and communication
QUEUE_FILE=$(mktemp)
STATUS_PIPE=$(mktemp -u)
mkfifo "$STATUS_PIPE"
exec {pipe_fd}<>"$STATUS_PIPE"

# Variables for tracking download performance
TOTAL_MB_DOWNLOADED=0
TOTAL_MS_ELAPSED=0

# Ensure temp files are cleaned up on exit
trap 'rm -f "$QUEUE_FILE" "$STATUS_PIPE"; jobs -p | xargs -r kill' EXIT INT TERM

# Function to calculate estimated completion time based on current performance
calculate_completion_time() {
    # Calculate total size of remaining queue (excluding current file that was just downloaded)
    local REMAINING_MB=0
    if [ -s "$QUEUE_FILE" ]; then
        REMAINING_MB=$(awk -F'\t' '{sum += $3} END {print sum}' "$QUEUE_FILE")
    fi


    if (( $(echo "$REMAINING_MB < 0.1" | bc -l) )); then
        date '+%I:%M %p'
        return
    fi

    # If we have download history and remaining files to download
    if [ "$TOTAL_MS_ELAPSED" -gt 0 ]; then
        # Calculate download rate (MB per millisecond)
        local RATE=$(echo "$TOTAL_MB_DOWNLOADED / $TOTAL_MS_ELAPSED" | bc -l)
        
        # If rate is too small (approaching zero), handle it
        if (( $(echo "$RATE < 0.0001" | bc -l) )); then
            echo "unknown"
            return
        fi
        
        # Calculate estimated remaining time (in milliseconds)
        local REMAINING_MS=$(echo "$REMAINING_MB / $RATE" | bc -l)
        
        # Get current timestamp and add the remaining milliseconds
        local CURRENT_TIMESTAMP=$(date +%s)
        local COMPLETION_TIMESTAMP=$(echo "$CURRENT_TIMESTAMP + ($REMAINING_MS / 1000)" | bc | cut -d. -f1)
        
        # Format the timestamp to a readable date and time
        echo "$(date -d @"$COMPLETION_TIMESTAMP" '+%I:%M %p')"
    else
        echo "calculation error"
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
            # Record end time and calculate duration
            END_TIME=$(date +%s%3N)
            DURATION_MS=$((END_TIME - START_TIME))
            
            # Update tracking variables
            TOTAL_MB_DOWNLOADED=$(echo "$TOTAL_MB_DOWNLOADED + $SIZE" | bc)
            TOTAL_MS_ELAPSED=$(echo "$TOTAL_MS_ELAPSED + $DURATION_MS" | bc)
            
            # Remove this entry from the queue first, so it's not counted in remaining calculation
            grep -v "^$FILENAME	$URL	$SIZE$" "$QUEUE_FILE" > "$QUEUE_FILE.tmp"
            mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"
            
            # Calculate estimated completion time
            COMPLETION_TIME=$(calculate_completion_time)
            
            echo "SUCCESS: Downloaded '$FILENAME' ($SIZE MB) - ETA $COMPLETION_TIME" > "$STATUS_PIPE" &
        else
            echo "FAILED: Could not download '$FILENAME' from $URL" > "$STATUS_PIPE" &
            
            # Remove this entry from the queue
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
        echo "  FILENAME | URL | SIZE(MB)"
        sort -t $'\t' -k 3 -n "$QUEUE_FILE" | while read -r LINE; do
            FILENAME=$(echo "$LINE" | cut -f1)
            URL=$(echo "$LINE" | cut -f2)
            SIZE=$(echo "$LINE" | cut -f3)
            echo "  $FILENAME | $URL | $SIZE MB"
        done
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

