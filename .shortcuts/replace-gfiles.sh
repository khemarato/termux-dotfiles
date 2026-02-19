#!/data/data/com.termux/files/usr/bin/bash

# Vibe coded by Gemini 3 Pro
# Not yet tested

# Configuration
DOWNLOAD_DIR="/data/data/com.termux/files/home/storage/shared/Download/"
SCRIPT_PATH="/data/data/com.termux/files/home/storage/shared/Documents/buddhist-uni.github.io/scripts/replace_gfile.py"
MAX_JOBS=4
TEMP_FILE=$(mktemp)

# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "Error: 'dialog' is not installed. Please run 'pkg install dialog'."
    exit 1
fi

# Check if directory exists
if [ ! -d "$DOWNLOAD_DIR" ]; then
    dialog --title "Error" --msgbox "Download directory not found:\n$DOWNLOAD_DIR" 10 50
    exit 1
fi

cd "$DOWNLOAD_DIR"

# Build the file list for dialog
# Format: "Filename" "Size/Info" "OFF"
FILES=()
while IFS= read -r -d '' file; do
    filename=$(basename "$file")
    # Add file to array: tag (path), item (filename), status (off)
    FILES+=("$file" "$filename" "off")
done < <(find . -maxdepth 1 -type f -print0)

# Check if files were found
if [ ${#FILES[@]} -eq 0 ]; then
    dialog --title "Empty" --msgbox "No files found in Download directory." 10 40
    exit 0
fi

# 1. Show Checkbox List
# Store output in TEMP_FILE because dialog writes to stderr
exec 3>&1
dialog --clear --title "Select Files" \
       --checklist "Select files to process (Space to select, Enter to confirm):" \
       20 60 15 \
       "${FILES[@]}" 2> "$TEMP_FILE"
retval=$?
exec 3>&-

# Exit if cancel pressed
if [ $retval -ne 0 ]; then
    clear
    echo "Selection cancelled."
    rm "$TEMP_FILE"
    exit 0
fi

# Read selected files into an array
# Dialog outputs quoted strings: "/path/to/file1" "/path/to/file 2"
SELECTED_FILES_STR=$(cat "$TEMP_FILE")
rm "$TEMP_FILE"

# Parse the quoted string output into a proper bash array
eval "SELECTED_FILES=($SELECTED_FILES_STR)"

if [ ${#SELECTED_FILES[@]} -eq 0 ]; then
    clear
    echo "No files selected."
    exit 0
fi

# Function to limit parallelism
limit_jobs() {
    while [ "$(jobs -r | wc -l)" -ge "$MAX_JOBS" ]; do
        sleep 1
    done
}

# 2. Loop through selections, prompt for ID, and run
clear
echo "Processing ${#SELECTED_FILES[@]} files..."

for localfile in "${SELECTED_FILES[@]}"; do
    filename=$(basename "$localfile")
    
    # Use dialog to prompt for the GFile ID/Link for this specific file
    # Using --inputbox. Output goes to stderr, so we capture it.
    GFILE_INPUT=$(dialog --title "Input Required" \
        --inputbox "Enter Google Drive Link or ID for:\n\n$filename" \
        10 60 \
        3>&1 1>&2 2>&3)
    
    input_retval=$?

    # If user cancels input for a specific file, skip it but continue others
    if [ $input_retval -ne 0 ]; then
        echo "Skipping $filename (Cancelled by user)"
        continue
    fi

    if [ -z "$GFILE_INPUT" ]; then
        echo "Skipping $filename (No ID provided)"
        continue
    fi

    # Wait if we hit max parallelism
    limit_jobs

    echo "Starting job for: $filename"
    
    # Launch Python script in background
    python3 "$SCRIPT_PATH" "$GFILE_INPUT" "$localfile" &

done

# 3. Wait for all background jobs to finish
echo "All inputs collected. Waiting for active jobs to complete..."
wait
echo "All tasks finished."

