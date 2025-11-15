# --- Build Stage ---
FROM golang:1.24 as builder

WORKDIR /app

# Copy the Go module files and download dependencies first
COPY publisher/go.mod publisher/go.sum ./
RUN go mod download

# Copy the source code and build the application
COPY publisher/main.go .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -installsuffix cgo -o publisher .

# --- Final Stage ---
FROM google/cloud-sdk:slim

# Install ffmpeg and streamlink
RUN apt-get update && apt-get install -y \
    ffmpeg \
    streamlink \
    bc \
    jq \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the compiled Go application from the builder stage
COPY --from=builder /app/publisher .

# Copy the entrypoint script
COPY record.sh .
COPY check_copy_condition.sh .
RUN chmod +x record.sh check_copy_condition.sh

CMD ["./record.sh"]