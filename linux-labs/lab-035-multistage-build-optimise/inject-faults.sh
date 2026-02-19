#!/bin/bash
mkdir -p /opt/webapp

# Create a simple Go application
cat > /opt/webapp/main.go << 'EOF'
package main
import (
    "fmt"
    "net/http"
)
func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Hello from optimised container!")
    })
    fmt.Println("Server starting on :8080")
    http.ListenAndServe(":8080", nil)
}
EOF

cat > /opt/webapp/go.mod << 'EOF'
module webapp
go 1.21
EOF

# Create an unoptimised Dockerfile (the problem)
cat > /opt/webapp/Dockerfile << 'DEOF'
# This Dockerfile produces a huge image
FROM golang:1.21

WORKDIR /app
COPY . .
RUN go build -o server main.go

# All of golang toolchain is still in the image!
EXPOSE 8080
CMD ["./server"]
DEOF

echo "Build optimisation lab prepared."
echo "Current Dockerfile at /opt/webapp/Dockerfile produces a ~1GB image."
echo "Optimise it using multi-stage builds."
