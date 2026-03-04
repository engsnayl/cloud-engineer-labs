#!/bin/bash
# =============================================================================
# Fault Injection: Image Build Failing
# =============================================================================

mkdir -p /opt/webapp

# Create the application
cat > /opt/webapp/app.js << 'EOF'
const http = require('http');
const server = http.createServer((req, res) => {
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({status: 'ok', service: 'webapp'}));
});
server.listen(8080, () => console.log('Server running on port 8080'));
EOF

cat > /opt/webapp/package.json << 'EOF'
{
    "name": "webapp",
    "version": "1.0.0",
    "main": "app.js",
    "scripts": {
        "start": "node app.js"
    }
}
EOF

# Create a broken Dockerfile with multiple issues
cat > /opt/webapp/Dockerfile << 'DEOF'

FROM node:23-alpine

WORKDIR /app

RUN npm install

# COPY package.json .
# COPY app.js .

CMD npm start
DEOF

echo "Docker build faults injected."
