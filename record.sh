#!/bin/bash

# --- Configuration ---
STREAM_NAME="${STREAM_NAME:-dexerityro}" # Default to dexerityro if not set
TWITCH_URL="https://www.twitch.tv/${STREAM_NAME}"
SAMPLING_FPS="${SAMPLING_FPS:-20}" # Default to 20 FPS if not set
DURATION="${DURATION:-}"
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



# --- Calculate FPS Filter ---

# Use bc for floating point comparison

IS_LESS_THAN_ONE=$(echo "$SAMPLING_FPS < 1" | bc -l)



if [ "$IS_LESS_THAN_ONE" -eq 1 ]; then

  # Calculate the denominator for the fraction

  DENOMINATOR=$(echo "1 / $SAMPLING_FPS" | bc)

  FPS_FILTER="fps=1/${DENOMINATOR}"

  echo "Calculated FPS filter for values < 1: ${FPS_FILTER}"

else

  FPS_FILTER="fps=${SAMPLING_FPS}"

  echo "Using standard FPS filter: ${FPS_FILTER}"

fi

echo "------------------------------------"



# --- Main Loop ---

while true; do

  echo "Checking for live stream..."

  STREAM_URL=$(streamlink --stream-url "$TWITCH_URL" best)

  EXIT_CODE=$?



  if [ $EXIT_CODE -ne 0 ]; then

    echo "Streamlink exited with code $EXIT_CODE. Stream is not live or could not be fetched. Exiting gracefully."

    sleep 5 # Give time for logs to be collected

    exit 0

  fi



  if [ -z "$STREAM_URL" ]; then

    echo "Stream URL is empty. Stream is not live or could not be fetched. Exiting gracefully."

    sleep 5 # Give time for logs to be collected

    exit 0

  fi

  echo "Stream is live. Starting Go publisher and ffmpeg."

  # Start the Go publisher in the background to watch for files
  /app/publisher > "${LOG_DIR}/publisher.log" 2>&1 &
  PUBLISHER_PID=$!
  echo "Go publisher started with PID $PUBLISHER_PID"

  # Add duration option if DURATION is set
  DURATION_OPT=""
  if [ -n "$DURATION" ]; then
    echo "Recording for a duration of $DURATION"
    DURATION_OPT="-t $DURATION"
  fi

  # Start ffmpeg to write frames to the directory
  # This will run in the foreground of the script
  ffmpeg -re -i "$STREAM_URL" \
    -threads 0 \
    -loglevel verbose \
    -nostats \
    -progress "${LOG_DIR}/ffmpeg_progress.log" \
    -fflags +igndts -fflags +discardcorrupt \
    -err_detect ignore_err \
    -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 2 \
    -an \
    -vf "$FPS_FILTER" \
    -q:v 4 \
    $DURATION_OPT \
    "${FRAMES_DIR}/frame_%08d.jpg"

  # If ffmpeg exits (stream ends), kill the publisher and loop
  echo "ffmpeg process ended. Cleaning up publisher."
  kill $PUBLISHER_PID
  wait $PUBLISHER_PID 2>/dev/null

  if [ -n "$DURATION" ]; then
    echo "Recording duration reached. Exiting."
    exit 0
  fi

  echo "Stream ended or was interrupted. Restarting loop after 10 seconds."
  sleep 10
done
