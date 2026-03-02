FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .

# BUG 1: Trying to use build ARG for runtime secret (wrong pattern)
ARG DATABASE_URL
ENV DATABASE_URL=$DATABASE_URL

# BUG 2: AWS credentials baked into the image (security risk!)
ARG AWS_ACCESS_KEY_ID
ARG AWS_SECRET_ACCESS_KEY
ENV AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
ENV AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY

CMD ["node", "server.js"]
