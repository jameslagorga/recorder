IMAGE_NAME := gcr.io/lagorgeous-helping-hands/stream-recorder:latest
DOCKERFILE := Dockerfile
RUN_CHART := deployment.yaml

.PHONY: all build push apply delete

all: build push apply

build:
	docker build --platform linux/amd64 -t $(IMAGE_NAME) -f $(DOCKERFILE) .

push:
	docker push $(IMAGE_NAME)

apply:
	kubectl apply -f  $(RUN_CHART)

delete:
	kubectl delete -f $(RUN_CHART)
