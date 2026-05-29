import os
import sys
import re
import time
import threading
import mimetypes
from queue import PriorityQueue
from urllib.parse import urlparse
import requests
from prompt_toolkit import prompt
from prompt_toolkit.completion import WordCompleter
from tqdm import tqdm

# Initialize the mimetypes database
mimetypes.init()
ADDITIONAL_EXTS = set([
  '.epub',
])

# Ensure download directory is provided as a CLI argument
if len(sys.argv) < 2:
  print("Usage: python download_manager.py <download_directory>")
  sys.exit(1)

download_dir = sys.argv[1]
os.makedirs(download_dir, exist_ok=True)

# Scan for existing subfolders to populate the initial autocomplete list
known_subfolders = set(
  f for f in os.listdir(download_dir) if os.path.isdir(os.path.join(download_dir, f))
)

# Priority Queue tracks tasks as (size_in_mb, (filename, url, subfolder))
download_queue = PriorityQueue()
input_done = threading.Event()
overall_pbar = None

# Thread-safe tracker to bridge background stats into visual bars later
worker_state = {
  'current_size_mb': 0.0,
  'bytes_downloaded': 0,
  'total_file_bytes': 0,
  'is_active': False
}
state_lock = threading.Lock()

def is_valid_extension(ext):
  """Checks if the extension is recognized by the standard mimetypes library."""
  if not ext or not ext.startswith('.'):
    return False
  ext_lower = ext.lower()
  return ext_lower in mimetypes.types_map or ext_lower in mimetypes.common_types or ext_lower in ADDITIONAL_EXTS

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

    size, (filename, url, subfolder) = item
    
    # Target path includes subfolder if provided
    target_dir = os.path.join(download_dir, subfolder) if subfolder else download_dir
    os.makedirs(target_dir, exist_ok=True)
    filepath = os.path.join(target_dir, filename)
    
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

        with state_lock:
          worker_state['current_size_mb'] = size
          worker_state['bytes_downloaded'] = existing_size
          worker_state['total_file_bytes'] = total_size
          worker_state['is_active'] = True

        pbar = None
        if input_done.is_set():
          pbar = tqdm(total=total_size, initial=existing_size, unit='B', unit_scale=True, desc=filename, position=1, leave=False)

        with open(filepath, mode) as f:
          for chunk in response.iter_content(chunk_size=8192):
            if chunk:
              f.write(chunk)
              with state_lock:
                worker_state['bytes_downloaded'] += len(chunk)
              
              if overall_pbar:
                overall_pbar.update(len(chunk))
              if input_done.is_set():
                if not pbar:
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
    
    # Extract extension and validate it against registered MIME types
    base, ext = os.path.splitext(filename)
    if not is_valid_extension(ext):
      # Try to find a valid extension from the URL path instead
      url_path = urlparse(url).path
      _, url_ext = os.path.splitext(url_path)
      
      if is_valid_extension(url_ext):
        filename = filename + url_ext
      else:
        print("Could not find a recognized file extension from the name or URL.")
        filename_raw = prompt("Enter filename with extension: ", default=filename)
        filename = "".join(filename_raw.splitlines()).strip()

    filename = sanitize_filename(filename)

    size_str = prompt("Enter estimated file size in MB: ").strip()
    try:
      size = float(size_str)
    except ValueError:
      print("Invalid size format. Defaulting to 0.0 MB for priority routing.")
      size = 0.0

    # Provision tab completion for subfolders dynamically
    subfolder_completer = WordCompleter(sorted(list(known_subfolders)), ignore_case=True)
    subfolder = prompt("Enter subfolder (Tab to autocomplete, blank for root): ", completer=subfolder_completer).strip()
    
    if subfolder:
      known_subfolders.add(subfolder)

    download_queue.put((size, (filename, url, subfolder)))
    
    display_dest = os.path.join(subfolder, filename) if subfolder else filename
    print(f"-> Added safely as '{display_dest}' ({size} MB) to background queue.")

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

# Signal worker to start rendering inner bars
input_done.set()

# Block main thread until the queue is completely drained
download_queue.join()

if overall_pbar:
  overall_pbar.close()

print("\nAll background downloads have finished processing.")

