# Hints — Lab 017: Proxy Headers and CORS

## Hint 1 — Add proxy headers
In the location block, add: `proxy_set_header Host $host;` `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;` `proxy_set_header X-Real-IP $remote_addr;`

## Hint 2 — Add CORS headers
Add: `add_header Access-Control-Allow-Origin *;` `add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";` `add_header Access-Control-Allow-Headers "Content-Type, Authorization";`

## Hint 3 — Handle OPTIONS
Add a block: `if ($request_method = OPTIONS) { return 204; }` or handle it in a separate location block.
