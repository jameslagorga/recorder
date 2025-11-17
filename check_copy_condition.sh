#!/bin/bash
set -e

# --- Configuration ---
STREAM_NAME="${STREAM_NAME}"
POD_NAME="${POD_NAME}"
SHORT_POD_ID=$(echo "${POD_NAME}" | rev | cut -d- -f1 | rev)
QA_SERVICE_URL="http://qa-service.default.svc.cluster.local:80/api/qa/needs_qa"

# Log a message
log() {
  echo "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ") INFO: $1"
}

log "--- Notifying QA Service ---"
log "Stream Name: ${STREAM_NAME}"
log "Short Pod ID: ${SHORT_POD_ID}"

# --- Notify QA Service ---
curl -v -X POST -H "Content-Type: application/json" \
  -d "{\"stream_name\": \"${STREAM_NAME}\", \"short_pod_id\": \"${SHORT_POD_ID}\"}" \
  "${QA_SERVICE_URL}"

log "--- Notification sent ---"
