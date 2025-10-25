package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	"cloud.google.com/go/pubsub"
	"github.com/fsnotify/fsnotify"
)

func main() {
	log.Println("--- Go Directory Watcher Publisher Initializing ---")

	// --- Configuration from Environment Variables ---
	projectID := getEnv("GCP_PROJECT_ID", "lagorgeous-helping-hands")
	topicID := getEnv("TOPIC_ID", "frame-processing-topic")
	streamName := getEnv("STREAM_NAME", "dexerityro")
	baseFramesDir := getEnv("FRAMES_DIR", "/mnt/nfs/streams")

	// Define directories
	framesDir := filepath.Join(baseFramesDir, streamName, "frames")
	newDir := filepath.Join(framesDir, "new")
	processedDir := filepath.Join(framesDir, "processed")

	// Ensure directories exist
	if err := os.MkdirAll(newDir, 0755); err != nil {
		log.Fatalf("Failed to create 'new' directory %s: %v", newDir, err)
	}
	if err := os.MkdirAll(processedDir, 0755); err != nil {
		log.Fatalf("Failed to create 'processed' directory %s: %v", processedDir, err)
	}

	log.Printf("Watching for new frames in: %s", newDir)

	// --- Pub/Sub Client Initialization ---
	ctx := context.Background()
	client, err := pubsub.NewClient(ctx, projectID)
	if err != nil {
		log.Fatalf("Failed to create Pub/Sub client: %v", err)
	}
	defer client.Close()
	topic := client.Topic(topicID)
	topic.PublishSettings.ByteThreshold = 5000
	topic.PublishSettings.CountThreshold = 100
	topic.PublishSettings.DelayThreshold = 100 * time.Millisecond

	// --- Filesystem Watcher Initialization ---
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		log.Fatalf("Failed to create filesystem watcher: %v", err)
	}
	defer watcher.Close()

	// --- Main Processing Loop ---
	go func() {
		for {
			select {
			case event, ok := <-watcher.Events:
				if !ok {
					return
				}
				// We only care about new files being written.
				// 'Write' is the event fsnotify often uses when a file is closed after writing.
				if event.Op&fsnotify.Write == fsnotify.Write {
					processFile(event.Name, newDir, processedDir, streamName, topic, ctx)
				}
			case err, ok := <-watcher.Errors:
				if !ok {
					return
				}
				log.Println("Watcher error:", err)
			}
		}
	}()

	err = watcher.Add(newDir)
	if err != nil {
		log.Fatalf("Failed to add directory to watcher: %v", err)
	}

	// Block forever
	<-make(chan struct{})
}

func processFile(filePath, newDir, processedDir, streamName string, topic *pubsub.Topic, ctx context.Context) {
	// Sometimes events fire on the directory itself, ignore those.
	if filePath == newDir {
		return
	}
	
	log.Printf("Detected new frame: %s", filePath)

	// --- Publish the file path to Pub/Sub ---
	message := fmt.Sprintf(`{"stream_name": "%s", "frame_path": "%s"}`, streamName, filePath)
	result := topic.Publish(ctx, &pubsub.Message{
		Data: []byte(message),
	})

	// Asynchronously check for publish errors
	go func(res *pubsub.PublishResult, path string) {
		_, err := res.Get(ctx)
		if err != nil {
			log.Printf("Failed to publish message for %s: %v", path, err)
		}
	}(result, filePath)

	// --- Move the processed file ---
	destPath := filepath.Join(processedDir, filepath.Base(filePath))
	err := os.Rename(filePath, destPath)
	if err != nil {
		log.Printf("Failed to move file from %s to %s: %v", filePath, destPath, err)
	}
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}