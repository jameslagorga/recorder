package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sort"
	"time"

	"cloud.google.com/go/pubsub"
)

const stateTimeFormat = time.RFC3339Nano

func main() {
	log.Println("--- Go Stateful Publisher Initializing (Timestamp-based) ---")

	// --- Configuration from Environment Variables ---
	projectID := getEnv("GCP_PROJECT_ID", "lagorgeous-helping-hands")
	topicID := getEnv("TOPIC_ID", "frame-processing-topic")
	streamName := getEnv("STREAM_NAME", "dexerityro")
	baseFramesDir := getEnv("FRAMES_DIR", "/mnt/nfs/streams")
	pollIntervalStr := getEnv("POLL_INTERVAL_MS", "500") // Polling interval in milliseconds

	pollInterval, err := time.ParseDuration(pollIntervalStr + "ms")
	if err != nil {
		log.Fatalf("Invalid POLL_INTERVAL_MS: %v", err)
	}

	framesDir := filepath.Join(baseFramesDir, streamName, "frames")
	stateFilePath := filepath.Join(baseFramesDir, streamName, "publisher.state.timestamp")
	log.Printf("Watching for new frames in: %s", framesDir)
	log.Printf("Using state file: %s", stateFilePath)

	// --- Pub/Sub Client Initialization ---
	ctx := context.Background()
	client, err := pubsub.NewClient(ctx, projectID)
	if err != nil {
		log.Fatalf("Failed to create Pub/Sub client: %v", err)
	}
	defer client.Close()
	topic := client.Topic(topicID)

	// --- Main Processing Loop ---
	lastProcessedTime := readTimestampState(stateFilePath)
	log.Printf("Starting to process files modified after: %s", lastProcessedTime.Format(stateTimeFormat))

	ticker := time.NewTicker(pollInterval)
	defer ticker.Stop()

	for range ticker.C {
		// Find files modified after the last processed time
		entries, err := os.ReadDir(framesDir)
		if err != nil {
			log.Printf("WARNING: Could not read frames directory %s: %v", framesDir, err)
			continue
		}

		var filesToProcess []string
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			filePath := filepath.Join(framesDir, entry.Name())
			info, err := entry.Info()
			if err != nil {
				log.Printf("WARNING: Could not get file info for %s: %v", filePath, err)
				continue
			}

			if info.ModTime().After(lastProcessedTime) {
				filesToProcess = append(filesToProcess, filePath)
			}
		}

		if len(filesToProcess) == 0 {
			continue
		}

		// Sort files to process them in order (by name, which is chronological)
		sort.Strings(filesToProcess)

		log.Printf("Found %d new frame(s) to process.", len(filesToProcess))

		for _, filePath := range filesToProcess {
			// Get the most up-to-date mod time right before processing
			info, err := os.Stat(filePath)
			if err != nil {
				log.Printf("WARNING: Could not stat file %s right before publishing: %v", filePath, err)
				continue
			}
			
			// Double-check in case of race conditions
			if !info.ModTime().After(lastProcessedTime) {
				continue
			}

			log.Printf("Processing frame: %s", filePath)

			// --- Publish the file path to Pub/Sub ---
			message := fmt.Sprintf(`{"stream_name": "%s", "frame_path": "%s"}`, streamName, filePath)
			result := topic.Publish(ctx, &pubsub.Message{
				Data: []byte(message),
				Attributes: map[string]string{
					"stream_name": streamName,
				},
			})

			serverID, err := result.Get(ctx)
			if err != nil {
				// If publishing fails, we stop and will retry this file on the next tick
				log.Printf("ERROR: Failed to publish message for %s: %v. Will retry.", filePath, err)
				break // Break from the inner loop, will retry on next tick
			}

			log.Printf("SUCCESS: Published message for %s (Server ID: %s)", filePath, serverID)

			// Update state with the timestamp of the file we just successfully processed
			lastProcessedTime = info.ModTime()
			if err := writeTimestampState(stateFilePath, lastProcessedTime); err != nil {
				log.Printf("WARNING: Failed to write state file: %v", err)
			}
		}
	}
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}

func readTimestampState(filePath string) time.Time {
	data, err := os.ReadFile(filePath)
	if err != nil {
		if os.IsNotExist(err) {
			// State file doesn't exist, so we start from now to avoid processing all old files.
			log.Println("No state file found. Starting to process files from this point in time.")
			return time.Now()
		}
		log.Printf("WARNING: Could not read state file %s: %v. Starting from now.", filePath, err)
		return time.Now()
	}

	t, err := time.Parse(stateTimeFormat, string(data))
	if err != nil {
		log.Printf("WARNING: Could not parse timestamp in state file %s: %v. Starting from now.", filePath, err)
		return time.Now()
	}

	return t
}

func writeTimestampState(filePath string, t time.Time) error {
	data := []byte(t.Format(stateTimeFormat))
	return os.WriteFile(filePath, data, 0644)
}