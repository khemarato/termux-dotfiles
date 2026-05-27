import os
import sys
import re
import time
import threading
from queue import PriorityQueue
from urllib.parse import urlparse
import requests
from prompt_toolkit import prompt
from tqdm import tqdm

# Ensure download directory is provided as a CLI argument
if len(sys.argv) < 2:
  print("Usage: python download_manager.py <download_directory>")
  sys.exit(1)

download_dir = sys.argv[1]
os.makedirs(download_dir, exist_ok=True)

# Priority Queue tracks tasks as (size_in_mb, (filename, url))
download_queue = PriorityQueue()
input_done = threading.Event()
overall_pbar = None

# Thread-safe tracker to bridge quiet background stats into visual bars later
worker_state = {
  'current_size_mb': 0.0,
  'bytes_downloaded': 0,
  'total_file_bytes': 0,
  'is_active': False
}
state_lock = threading.Lock()

def sanitize_filename(name):
  """Removes newlines and unsafe characters while preserving spaces and unicode."""
  name = "".join(name.splitlines())
  name = re.sub(r'[\<\>\:\"\/\\\|\?\*\x00-\x1f]', '_', name)
  return name.strip()

def download_worker():
  """Background worker that processes downloads sorted by size (smallest first)."""
  global overall_pbar
  while True:
    if input_done.is_set() and download_queue.empty():
      break

    try:
      item = download_queue.get(timeout=1)
    except:
      continue

    size, (filename, url) = item
    filepath = os.path.join(download_dir, filename)
    
    success = False
    for attempt in range(5):
      try:
        existing_size = os.path.getsize(filepath) if os.path.exists(filepath) else 0
        headers = {}
        
        if existing_size > 0:
          headers['Range'] = f"bytes={existing_size}-"
        
        response = requests.get(url, headers=headers, stream=True, timeout=15)
        
        if response.status_code == 206:
          mode = 'ab'
          total_size = int(response.headers.get('content-range', '').split('/')[-1])
        elif response.status_code == 200:
          mode = 'wb'
          total_size = int(response.headers.get('content-length', 0))
          existing_size = 0
        elif response.status_code == 416:
          success = True
          break
        else:
          raise requests.RequestException(f"HTTP Status {response.status_code}")

        # Share current download progress context safely with the main thread
        with state_lock:
          worker_state['current_size_mb'] = size
          worker_state['bytes_downloaded'] = existing_size
          worker_state['total_file_bytes'] = total_size
          worker_state['is_active'] = True

        # Render inner progress bar at position 1 if monitoring mode is active
        pbar = None
        if input_done.is_set():
          pbar = tqdm(total=total_size, initial=existing_size, unit='B', unit_scale=True, desc=filename, position=1, leave=False)

        with open(filepath, mode) as f:
          for chunk in response.iter_content(chunk_size=8192):
            if chunk:
              f.write(chunk)
              with state_lock:
                worker_state['bytes_downloaded'] += len(chunk)
              
              # Safely feed progress bars simultaneously
              if overall_pbar:
                overall_pbar.update(len(chunk))
              if input_done.is_set():
                if not pbar:
                  # Catch mid-download transitions seamlessly
                  pbar = tqdm(total=total_size, initial=worker_state['bytes_downloaded'], unit='B', unit_scale=True, desc=filename, position=1, leave=False)
                pbar.update(len(chunk))

        if pbar:
          pbar.close()
        
        success = True
        break
        
      except Exception as e:
        if input_done.is_set():
          tqdm.write(f"[Error] Attempt {attempt + 1}/5 failed for {filename}: {e}")
        time.sleep(2)
    
    with state_lock:
      worker_state['is_active'] = False
      worker_state['current_size_mb'] = 0.0

    if not success and input_done.is_set():
      tqdm.write(f"[Failed] Could not download {filename} after 5 attempts.")
      
    download_queue.task_done()

# Start background downloader thread
worker_thread = threading.Thread(target=download_worker, daemon=True)
worker_thread.start()

# Main Input Loop
try:
  while True:
    print("\n--- Add File to Queue ---")
    filename_raw = prompt(
      "Enter filename (Leave blank & press enter to finalize and see progress):\n", 
      multiline=True
    )
    filename = "".join(filename_raw.splitlines()).strip()
    
    if not filename:
      break
      
    url = prompt("Enter URL: ").strip()
    
    base, ext = os.path.splitext(filename)
    if not ext:
      url_path = urlparse(url).path
      url_ext = os.path.splitext(url_path)[1]
      
      if url_ext:
        filename = filename + url_ext
      else:
        print("Could not guess extension from URL.")
        filename_raw = prompt("Enter filename with extension: ", default=filename)
        filename = "".join(filename_raw.splitlines()).strip()

    filename = sanitize_filename(filename)

    size_str = prompt("Enter estimated file size in MB: ").strip()
    try:
      size = float(size_str)
    except ValueError:
      print("Invalid size format. Defaulting to 0.0 MB for priority routing.")
      size = 0.0

    download_queue.put((size, (filename, url)))
    print(f"-> Added safely as '{filename}' ({size} MB) to background queue.")

except KeyboardInterrupt:
  print("\nInput cancelled. Processing existing queue...")

# Switch to Progress Mode
print("\n==========================================")
print("  SWITCHING TO PROGRESS MONITORING MODE   ")
print("==========================================\n")

# Compute overall remaining bytes based on queue items + active worker progress
with download_queue.mutex:
  queue_items = list(download_queue.queue)

queue_mb = sum(item[0] for item in queue_items)

with state_lock:
  if worker_state['is_active']:
    remaining_current_bytes = max(0, worker_state['total_file_bytes'] - worker_state['bytes_downloaded'])
  else:
    remaining_current_bytes = 0

total_bytes_to_go = int(queue_mb * 1024 * 1024) + remaining_current_bytes

# Initialize the global overall progress bar at position 0
overall_pbar = tqdm(
  total=total_bytes_to_go, 
  position=0, 
  desc="Overall Progress", 
  unit='B', 
  unit_scale=True
)

# Signal worker to start rendering inner bars and processing terminations
input_done.set()

# Block main thread until the queue is completely drained
download_queue.join()

if overall_pbar:
  overall_pbar.close()

print("\nAll background downloads have finished processing.")

