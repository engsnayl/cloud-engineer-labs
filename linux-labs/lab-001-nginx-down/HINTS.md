# Hints — Lab 001: Nginx Down

## Hint 1 — Where to start
Start with `nginx -t` to test the configuration. Read the error messages carefully — they tell you exactly what's wrong and on which line.

## Hint 2 — There's more than one issue
Even after fixing the config syntax, Nginx still won't start. Think about what else Nginx needs to function — where does it write logs?

## Hint 3 — Check what's in sites-enabled
Run `ls -la /etc/nginx/sites-enabled/` — is everything there supposed to be there? Does the config make sense for what this server should be doing?
