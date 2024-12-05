#!/bin/bash

# Function to copy data and check integrity
copy_and_verify() {
  local bx=$1
  local rx=$2
  local sleep_interval=$3

  while true; do
    echo "Starting copy from /dev/$bx to /dev/$rx..."

    # Step 1: Copy data from bX to rX
    if ! dd if=/dev/$bx of=/dev/$rx bs=1M status=progress; then
      echo "Error: Failed to copy from /dev/$bx to /dev/$rx"
      exit 1
    fi

    echo "Copy from /dev/$bx to /dev/$rx completed."

    # Step 2: Calculate checksums of both devices
    echo "Calculating checksums for /dev/$bx and /dev/$rx..."
    local checksum_bx=$(md5sum /dev/$bx | awk '{print $1}')
    local checksum_rx=$(md5sum /dev/$rx | awk '{print $1}')

    # Step 3: Compare the checksums
    if [ "$checksum_bx" != "$checksum_rx" ]; then
      echo "Error: Checksum mismatch between /dev/$bx ($checksum_bx) and /dev/$rx ($checksum_rx)"
      exit 1  # Exit with an error if the checksums don't match
    else
      echo "Success: /dev/$bx and /dev/$rx are identical."
    fi

    # Wait before the next iteration (configurable sleep interval)
    echo "Waiting for $sleep_interval seconds before the next iteration..."
    sleep "$sleep_interval"
  done
}

# Check if the user provided the correct number of arguments
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <sleep_interval> <bX1> <rX1> [<bX2> <rX2> ...]"
  exit 1
fi

# Get the sleep interval (time between iterations)
sleep_interval=$1
shift  # Remove the first argument (sleep interval)

# Check if we have an even number of remaining arguments (bX, rX pairs)
if [ "$(($# % 2))" -ne 0 ]; then
  echo "Error: You must provide an even number of device pairs (bX rX)."
  exit 1
fi

# Export the function for GNU parallel
export -f copy_and_verify

# Build the device pairs input for parallel
device_list=()
while [ "$#" -gt 1 ]; do
  device_list+=("$1" "$2")
  shift 2
done

# Use GNU parallel to copy and verify in parallel
parallel --link copy_and_verify ::: "${device_list[@]}" ::: "$sleep_interval"
