#!/bin/bash

# --- Configuration ---
TWITCH_URL="${TWITCH_URL:-https://www.twitch.tv/dexerityro}"
SAMPLING_FPS="${SAMPLING_FPS:-10}"
STREAM_NAME="${STREAM_NAME:-dexerityro}"
FRAMES_DIR="/mnt/nfs/streams/${STREAM_NAME}/frames/new"
LOG_DIR="/mnt/nfs/jobs/recorder/${POD_NAME}"

# --- Initialization ---
mkdir -p "$FRAMES_DIR"
mkdir -p "$LOG_DIR"
exec > >(tee -a "${LOG_DIR}/recorder.log") 2>&1
set -e

echo "--- Starting Recorder with Directory Watcher ---"
echo "Twitch URL: $TWITCH_URL"
echo "Sampling FPS: $SAMPLING_FPS"
echo "------------------------------------------------"

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

  # Start the Go publisher in the background
  /app/publisher > "${LOG_DIR}/publisher.log" 2>&1 &
  PUBLISHER_PID=$!
  echo "Go publisher started with PID $PUBLISHER_PID"

  # Give the publisher a moment to start up
  sleep 2

  # Start ffmpeg to write frames to the directory
  ffmpeg -i "$STREAM_URL" \
    -loglevel error \
    -an \
    -vf fps="$SAMPLING_FPS" \
    -q:v 2 \
    -strftime 1 \
    "${FRAMES_DIR}/frame_%Y%m%d-%H%M%S_%%04d.jpg"

  # If ffmpeg exits (stream ends), kill the publisher and loop
  echo "ffmpeg process ended. Cleaning up publisher."
  kill $PUBLISHER_PID
  wait $PUBLISHER_PID 2>/dev/null

  echo "Stream ended or was interrupted. Restarting loop after 10 seconds."
  sleep 10
done
