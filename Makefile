IMAGE_NAME := gcr.io/lagorgeous-helping-hands/stream-recorder:latest
DOCKERFILE := Dockerfile
RUN_CHART := deployment.yaml.template

.PHONY: all build push apply delete

all: build push

build:
	docker build --platform linux/amd64 -t $(IMAGE_NAME) -f $(DOCKERFILE) .

push:
	docker push $(IMAGE_NAME)

apply:
	@if [ -z "$(stream)" ]; then \
		echo "Usage: make apply stream=<stream_name>"; \
		exit 1; \
	fi
	cat $(RUN_CHART) | sed "s/STREAM_NAME/$(stream)/g" | kubectl apply -f -

delete:
	@if [ -z "$(stream)" ]; then \
		echo "Usage: make delete stream=<stream_name>"; \
		exit 1; \
	fi
	cat $(RUN_CHART) | sed "s/STREAM_NAME/$(stream)/g" | kubectl delete -f -

