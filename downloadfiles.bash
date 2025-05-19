#!/bin/bash

# Written by Claude.ai in May 2025
# Slightly modified

cd "$1"
echo "Will download files to '$(pwd)'"

# Create temporary files for the queue and communication
QUEUE_FILE=$(mktemp)
STATUS_PIPE=$(mktemp -u)
mkfifo "$STATUS_PIPE"
exec {pipe_fd}<>"$STATUS_PIPE"

# Ensure temp files are cleaned up on exit
trap 'rm -f "$QUEUE_FILE" "$STATUS_PIPE"; jobs -p | xargs -r kill' EXIT INT TERM

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

        # Download the file
        if wget -q "$URL" -O "$FILENAME"; then
            echo "SUCCESS: Downloaded '$FILENAME' ($SIZE MB)" > "$STATUS_PIPE" &
        else
            echo "FAILED: Could not download '$FILENAME' from $URL" > "$STATUS_PIPE" &
        fi
        
        # Remove this entry from the queue
        grep -v "^$FILENAME	$URL	$SIZE$" "$QUEUE_FILE" > "$QUEUE_FILE.tmp"
        mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"
        
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
