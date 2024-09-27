#!/bin/bash

# Function to start the NFS service
start_nfs_service() {
  echo "Starting NFS service after 59 seconds..."
  sleep 59  # Wait for 59 seconds before starting the NFS service
  sudo service nfs-kernel-server start
  echo "NFS service started."
}

# Stop the NFS service initially
echo "Stopping NFS service..."
sudo service nfs-kernel-server stop

# Initialize a counter to track how many times the error message appears
error_count=0
last_timestamp=""

# Monitor logs for the longhorn-manager DaemonSet
echo "Monitoring logs for 'Failed to get info from backup store' message..."

while true; do
  # Get the log output from all longhorn-manager pods in the longhorn-system namespace with timestamps
  log_output=$(kubectl logs -n longhorn-system -l app=longhorn-manager --since=1m --timestamps)

  # Convert log output into an array to process each line
  log_lines=($(echo "$log_output" | grep "Failed to get info from backup store"))

  # Loop through each log line that contains the "Failed to get info from backup store" message
  for line in "${log_lines[@]}"; do
    # Extract the timestamp from the log line, assuming the timestamp is in ISO 8601 format
    current_timestamp=$(echo "$line" | grep -oP '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.\d+Z')

    # Ensure current_timestamp is not empty
    if [ -n "$current_timestamp" ]; then
      # Debugging output: Print current and last timestamp
      echo "Current timestamp: $current_timestamp"
      echo "Last timestamp: $last_timestamp"

      # Check if this is a new occurrence (i.e., the timestamp is different from the previous one)
      if [ "$current_timestamp" != "$last_timestamp" ]; then
        error_count=$((error_count+1))
        echo "'Failed to get info from backup store' found at $current_timestamp. Count: $error_count"

        # Update the last_timestamp to the current one (after processing a valid, new occurrence)
        last_timestamp="$current_timestamp"

        # If the error message appears twice, wait 59 seconds and start the NFS service
        if [ "$error_count" -ge 2 ]; then
          start_nfs_service
          exit 0  # Exit the script after starting the NFS service
        fi
      fi
    fi
  done

  # Wait for 5 seconds before checking the logs again
  sleep 5
done

