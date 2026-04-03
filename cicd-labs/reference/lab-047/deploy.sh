#!/bin/bash 

set -euo pipefail   # -e means exit if any command fails, -u means error if you try to use a var that has not been set
                    # -o pipefail means if any command in a pipeline fails then the whole pipe fails

IMAGE_NAME="api-service"                  # Set Image name variable
CONTAINER_NAME="api-service"              # Set Container name variable
PORT=3000                                 # Set port to 3000
TAG="${1:?Usage: deploy.sh <image-tag>}"  # Set 1st argument to TAG. If there's no 1st argument, stop and display message

echo "=== Deploying ${IMAGE_NAME}:${TAG} ==="       # If TAG is set correctly print this output to the terminal

echo "Stopping existing container..."               # Stops and removes existing container if running
docker stop "$CONTAINER_NAME" 2>/dev/null || true   # Redirect error messages to nowhere with 2>/dev/null
docker rm "$CONTAINER_NAME" 2>/dev/null || true     # || true stops the -e from killing the script if nothing running

echo "Starting new container with tag: ${TAG}"
docker run -d \                                     # Docker Run -d (run in detached mode i.e. in the background)
    --name "$CONTAINER_NAME" \                      # Give the container a name as per our variable i.e. api-service
    -p "${PORT}:${PORT}" \                          # Map the port i.e. 3000 (Host Port) : 3000 (Container Port)
    "${IMAGE_NAME}:${TAG}"                          # Tell it which image to run 

echo "Waiting for container to start..."            # Start the health check - try 5 times to call API for a 200 response
for i in 1 2 3 4 5; do
  sleep 2
  STATUS=$(curl -sf -o /dev/null -w "%{http_code}" "http://localhost:${PORT}/health" || true)
  if [[ "$STATUS" == "200" ]]; then
    echo "Deploy successful — container is healthy"
    exit 0                                              # Note that exit 0 is the success output.  
  fi                                                    # exit 0 will terminate the script here and now - no futher action
  echo "  Attempt ${i}: status ${STATUS}, retrying..."
done

echo "ERROR: Container failed health check after deploy"    # This is the rollback script
echo "Rolling back — stopping unhealthy container"          # If the health check fails then stop and remove the container
docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm "$CONTAINER_NAME" 2>/dev/null || true
exit 1
