# Solution Walkthrough — Nginx Down

## The Problem

Nginx, a popular web server, is completely down and refuses to start. There are actually **three separate issues** stacked on top of each other — which is realistic because in the real world, problems rarely come one at a time. Here's what's broken:

1. **A syntax error in the main config file** — someone removed a semicolon from a configuration line. Nginx is very strict about syntax and won't start if even one semicolon is missing.
2. **The log directory has no permissions** — Nginx needs to write access logs and error logs when it runs. If it can't write to its log directory, it refuses to start.
3. **A bogus site configuration was left behind** — a file in `sites-enabled` points to a directory that doesn't exist and proxies to a service that isn't running. While this alone might not prevent Nginx from starting, it's a broken config that should be cleaned up.

## Thought Process

An experienced engineer would start with the most direct diagnostic tool available: `nginx -t`. This command tests the Nginx configuration without actually starting the server, and it gives you clear error messages pointing to the exact file and line number where something is wrong. You fix one error, run `nginx -t` again, and keep going until it passes.

If the config test passes but Nginx still won't start, the next thought is: "What resources does Nginx need?" It needs to write logs, bind to network ports, and read its web content files. Checking permissions on those directories is the natural next step.

Finally, you'd review what sites are configured to make sure nothing is pointing to missing resources or conflicting with other configurations.

## Step-by-Step Solution

### Step 1: Test the Nginx configuration

```bash
nginx -t
```

**What this does:** The `-t` flag tells Nginx to test its configuration files for syntax errors without actually starting the server. It will report any problems it finds, including the file name and line number. You'll see an error about a missing semicolon in `/etc/nginx/nginx.conf`.

### Step 2: Fix the missing semicolon in nginx.conf

```bash
sed -i 's/worker_connections 768$/worker_connections 768;/' /etc/nginx/nginx.conf
```

**What this does:** This finds the line `worker_connections 768` (without a semicolon at the end) and adds the missing semicolon back. The `sed -i` command edits the file in place. You could also open the file with `nano` or `vi` and add the semicolon manually — the key is that every directive in Nginx config must end with a semicolon.

### Step 3: Run the config test again

```bash
nginx -t
```

**What this does:** Verifies that the syntax error is fixed. You may still see other errors or warnings — that's expected because there are more issues to fix.

### Step 4: Fix the log directory permissions

```bash
chmod 755 /var/log/nginx
```

**What this does:** Restores proper permissions on the Nginx log directory. The number `755` means the owner (root) can read, write, and enter the directory, and everyone else can read and enter it. The log directory was set to `000` (no access for anyone), which prevented Nginx from writing its logs. Nginx will refuse to start if it can't open its log files.

### Step 5: Remove the broken site configuration

```bash
rm /etc/nginx/sites-enabled/broken-site
```

**What this does:** Removes the bogus site configuration file that was pointing to a non-existent document root (`/var/www/nonexistent`) and proxying to a service that isn't running on port 9999. In the `sites-enabled` directory, each file represents a website or service that Nginx should serve. Leaving broken configs here is messy and can cause unexpected behavior.

### Step 6: Verify the configuration is now clean

```bash
nginx -t
```

**What this does:** One final config test to make sure everything is valid before we start the server. You should see `syntax is ok` and `test is successful`.

### Step 7: Start Nginx

```bash
service nginx start
```

**What this does:** Starts the Nginx web server process. It will read its configuration files, open its log files, bind to port 80, and begin accepting web requests.

### Step 8: Verify Nginx is running and responding

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:80
```

**What this does:** Sends an HTTP request to the local web server and prints only the HTTP status code. You should see `200`, which means "OK — the server is working." The `-s` flag silences progress output, `-o /dev/null` discards the page content (we don't need it), and `-w "%{http_code}"` tells curl to print just the status code.

## Docker Lab vs Real Life

- **Starting Nginx:** In this lab we use `service nginx start` because Docker containers typically don't run systemd. On a real production Ubuntu/Debian server, you'd use `systemctl start nginx` and `systemctl enable nginx` to make sure it starts on boot.
- **Checking status:** In this lab, `service nginx status` works. On a real server, `systemctl status nginx` gives you much richer information including recent log entries.
- **Config editing:** In production, you'd ideally use a configuration management tool (like Ansible) to manage Nginx config files, rather than editing them by hand on the server.

## Key Concepts Learned

- **Always run `nginx -t` before starting or restarting Nginx** — it's the single most useful diagnostic command for Nginx problems
- **Nginx configuration syntax requires semicolons** at the end of every directive — a missing semicolon will prevent the entire server from starting
- **File permissions matter** — a web server needs read/write access to its log directories and read access to its configuration and content files
- **The `sites-enabled` directory** controls which site configurations are active — stale or broken configs should be removed
- **Layered problems are common** — in the real world, you often have to fix multiple issues before a service comes back online

## Common Mistakes

- **Stopping after fixing one issue** — the biggest trap here. You fix the semicolon, try to start Nginx, it still fails, and you think your fix didn't work. In reality, there are multiple problems to find.
- **Using `chmod 777` to fix permissions** — while this would "work," it's a terrible security practice. Use the minimum permissions needed (755 for directories, 644 for config files).
- **Forgetting to test the config before starting** — if you just run `service nginx start` without testing first, the error messages are less clear and the service simply fails to start.
- **Editing the wrong config file** — Nginx has a main config (`/etc/nginx/nginx.conf`) and per-site configs in `sites-available` and `sites-enabled`. Make sure you're editing the right one.
- **Not checking `sites-enabled`** — many people focus only on `nginx.conf` and forget that additional config files are loaded from `sites-enabled/`.
