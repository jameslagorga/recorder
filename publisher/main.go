package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	"cloud.google.com/go/pubsub"
)

func main() {
	log.Println("--- Go Sequential Publisher Initializing (Synchronous) ---")

	// --- Configuration from Environment Variables ---
	projectID := getEnv("GCP_PROJECT_ID", "lagorgeous-helping-hands")
	topicID := getEnv("TOPIC_ID", "frame-processing-topic")
	streamName := getEnv("STREAM_NAME", "dexerityro")
	baseFramesDir := getEnv("FRAMES_DIR", "/mnt/nfs/streams")

	framesDir := filepath.Join(baseFramesDir, streamName, "frames")
	log.Printf("Watching for new frames in: %s", framesDir)

	// --- Pub/Sub Client Initialization ---
	ctx := context.Background()
	client, err := pubsub.NewClient(ctx, projectID)
	if err != nil {
		log.Fatalf("Failed to create Pub/Sub client: %v", err)
	}
	defer client.Close()
	topic := client.Topic(topicID)

	// --- Main Processing Loop ---
	frameCounter := 1
	for {
		filePath := filepath.Join(framesDir, fmt.Sprintf("frame_%08d.jpg", frameCounter))

		// Wait for the next sequential frame to exist.
		// This is a simple polling mechanism.
		for {
			if _, err := os.Stat(filePath); err == nil {
				// File exists, break the inner loop to process it.
				break
			}
			// Wait a moment before checking again.
			time.Sleep(100 * time.Millisecond)
		}

		log.Printf("Processing frame: %s", filePath)

		// --- Publish the file path to Pub/Sub (Synchronously) ---
		message := fmt.Sprintf(`{"stream_name": "%s", "frame_path": "%s"}`, streamName, filePath)
		result := topic.Publish(ctx, &pubsub.Message{
			Data: []byte(message),
		})

		// Block and wait for the result. This is the crucial part for debugging.
		// If there's any error (permissions, etc.), this will halt the program.
		serverID, err := result.Get(ctx)
		if err != nil {
			log.Fatalf("FATAL: Failed to publish message for %s: %v", filePath, err)
		}

		log.Printf("SUCCESS: Published message for %s (Server ID: %s)", filePath, serverID)
		frameCounter++
	}
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}