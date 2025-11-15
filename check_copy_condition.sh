#!/bin/bash
set -e

# --- Configuration ---
STREAM_NAME="${STREAM_NAME}"
POD_NAME="${POD_NAME}"
THRESHOLD="${PROPORTION_THRESHOLD:-0.0}"

# Log a message
log() {
  echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ") INFO: $1"
}

log "--- Starting Hand Count Proportion Check ---"
log "Stream Name: ${STREAM_NAME}"
log "Pod Name: ${POD_NAME}"
log "Threshold: ${THRESHOLD}"

# --- Directory and File Validation ---
RESULTS_DIR="/mnt/nfs/streams/${STREAM_NAME}/${POD_NAME}/hamer/results"

if [ ! -d "${RESULTS_DIR}" ]; then
  log "Results directory not found: ${RESULTS_DIR}. Exiting with failure status 1."
  exit 1
fi

JSON_FILES=($(find "${RESULTS_DIR}" -name "*_data.json"))
TOTAL_FILES=${#JSON_FILES[@]}

if [ "${TOTAL_FILES}" -eq 0 ]; then
  log "No JSON result files found to analyze. Exiting with failure status 1."
  exit 1
fi

# --- Analysis ---
HIGH_COUNT_FRAMES=0
for json_file in "${JSON_FILES[@]}"; do
  # Safely extract hand_count, default to 0 if null or not present
  hand_count=$(jq '.hand_count // 0' "${json_file}")
  if [ "${hand_count}" -ge 4 ]; then
    HIGH_COUNT_FRAMES=$((HIGH_COUNT_FRAMES + 1))
  fi
done

log "Total frames analyzed: ${TOTAL_FILES}"
log "Frames with 4 or more hands: ${HIGH_COUNT_FRAMES}"

# --- Calculation and Comparison ---
# Use bc for floating point comparison
PROPORTION=$(echo "scale=4; ${HIGH_COUNT_FRAMES} / ${TOTAL_FILES}" | bc)
COMPARISON=$(echo "${PROPORTION} > ${THRESHOLD}" | bc -l)

log "Proportion: ${PROPORTION}"

if [ "${COMPARISON}" -eq 1 ]; then
  log "Proportion exceeds threshold of ${THRESHOLD}. Adding to QA queue."
  SOURCE_DIR="/mnt/nfs/streams/${STREAM_NAME}/${POD_NAME}"
  echo "${SOURCE_DIR}" >> /mnt/nfs/qa_queue.txt
  log "Added ${SOURCE_DIR} to queue. Exiting with success status 0."
  exit 0
else
  log "Proportion is at or below threshold of ${THRESHOLD}. Deleting data from NFS."
  SOURCE_DIR="/mnt/nfs/streams/${STREAM_NAME}/${POD_NAME}/"
  log "Source: ${SOURCE_DIR}"
  rm -rf "${SOURCE_DIR}"
  log "Deletion complete. Exiting with failure status 1."
  exit 1
fi
