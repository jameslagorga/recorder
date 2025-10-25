#!/bin/bash

# --- Configuration ---
STREAM_NAME="${STREAM_NAME:-dexerityro}" # Default to dexerityro if not set
TWITCH_URL="https://www.twitch.tv/${STREAM_NAME}"
SAMPLING_FPS="${SAMPLING_FPS:-1}"
FRAMES_DIR="/mnt/nfs/streams/${STREAM_NAME}/frames"
LOG_DIR="/mnt/nfs/jobs/recorder/${POD_NAME}"

# --- Initialization ---
mkdir -p "$FRAMES_DIR"
mkdir -p "$LOG_DIR"
exec > >(tee -a "${LOG_DIR}/recorder.log") 2>&1
set -e

echo "--- Starting Simplified Recorder ---"
echo "Twitch URL: $TWITCH_URL"
echo "Sampling FPS: $SAMPLING_FPS"
echo "------------------------------------"

# --- Main Loop ---
while true; do
  echo "Checking for live stream..."
  STREAM_URL=$(streamlink --stream-url "$TWITCH_URL" best || echo "")

  if [ -z "$STREAM_URL" ]; then
    echo "Stream is not live or could not be fetched. Waiting 30 seconds..."
    sleep 30
    continue
  fi

  echo "Stream is live. Starting Go publisher and ffmpeg."

  # Start the Go publisher in the background to watch for files
  /app/publisher > "${LOG_DIR}/publisher.log" 2>&1 &
  PUBLISHER_PID=$!
  echo "Go publisher started with PID $PUBLISHER_PID"

  # Start ffmpeg to write frames to the directory
  # This will run in the foreground of the script
  ffmpeg -re -i "$STREAM_URL" \
    -loglevel verbose \
    -fflags +igndts -fflags +discardcorrupt \
    -err_detect ignore_err \
    -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 2 \
    -an \
    -vf fps="$SAMPLING_FPS" \
    -q:v 2 \
    "${FRAMES_DIR}/frame_%08d.jpg"

  # If ffmpeg exits (stream ends), kill the publisher and loop
  echo "ffmpeg process ended. Cleaning up publisher."
  kill $PUBLISHER_PID
  wait $PUBLISHER_PID 2>/dev/null

  echo "Stream ended or was interrupted. Restarting loop after 10 seconds."
  sleep 10
done