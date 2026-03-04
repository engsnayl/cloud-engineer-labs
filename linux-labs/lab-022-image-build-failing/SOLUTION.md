# Solution Walkthrough — Image Build Failing

## TLDR Summary

A Dockerfile for a Node.js app won't build. There are three things actually broken: the lines that copy your application files into the container are commented out (so nothing gets put inside), the install command runs before those files are copied in (so it has nothing to work with), and the order is wrong. Fix those three things and the app builds and runs. There are also two optional improvements you can make — better command syntax and adding a port label — but these don't affect whether the app works or not.

---

## What You're Looking At

When you open this lab, you've got a directory at `/opt/webapp/` containing three files:

- **`app.js`** — a small Node.js web application that listens on port 8080 and responds with a status message
- **`package.json`** — a file that lists what external packages the app depends on (more on this below)
- **`Dockerfile`** — the set of instructions Docker follows to build this app into a container image

The Dockerfile is broken. Your job is to figure out why and fix it.

---

## What Is npm and package.json?

Before looking at the Dockerfile, it helps to understand what these are, even at a surface level.

Most applications use code written by other people — things like web server frameworks or security tools. These are called **packages** or **dependencies**. Rather than writing everything yourself, you pull in packages that already exist.

**npm** (Node Package Manager) is the tool that downloads these packages. It comes bundled with Node.js.

**`package.json`** is a file that says "this app needs these specific packages." It's a list of requirements.

**`npm install`** reads that list and downloads everything on it into the project.

You don't need to understand the contents of `package.json` or `app.js` to fix this lab. You just need to know that:
- `package.json` must be present before `npm install` can run
- `app.js` is the application code that needs to be inside the container
- Both files need to be **copied into the container** — they don't appear there automatically

---

## The Broken Dockerfile — What Each Line Does

```bash
cat /opt/webapp/Dockerfile
```

Here's what you'll see, with an explanation of every line:

```dockerfile
FROM node:23-alpine
```
- `FROM` — every Dockerfile starts with this. It sets the base image — a pre-built starting point that already has an operating system and tools installed
- `node:23-alpine` — this means "use the Node.js image, version 23, alpine variant." Alpine is a tiny version of Linux that keeps the image small
- **This line is fine.** The image exists and pulls successfully

```dockerfile
WORKDIR /app
```
- `WORKDIR` — sets the working directory inside the container. Think of it as doing `cd /app`. Every instruction after this happens inside `/app`
- If `/app` doesn't exist, Docker creates it automatically
- **This line is fine.**

```dockerfile
RUN npm install
```
- `RUN` — executes a command during the build
- `npm install` — reads `package.json` and downloads the listed packages
- **BUG: `package.json` hasn't been copied into the container yet.** The `/app` directory is empty at this point. npm can't read a file that isn't there. This either errors out or silently does nothing

```dockerfile
# COPY package.json .
# COPY app.js .
```
- The `#` at the start makes these comments — Docker ignores them completely
- `COPY` — takes a file from your machine and puts it inside the container
- `package.json .` — would copy `package.json` into the current directory (`/app`)
- `app.js .` — would copy the application code into `/app`
- **BUG: These are commented out.** No files ever get into the container. Even if `npm install` somehow worked, there would be no `app.js` to run

```dockerfile
CMD npm start
```
- `CMD` — tells Docker what to do when the container starts (not during the build, but when you `docker run` it)
- `npm start` — runs the start script defined in `package.json`, which launches `app.js`
- **This works**, but there's a better way to write it (covered in the improvements section below)

### Summary of what's broken

There are really two problems that cause the build to fail:

1. **The COPY lines are commented out** — nothing gets into the container
2. **`RUN npm install` comes before the COPY lines** — even if you uncomment them, the order is wrong. npm runs before `package.json` exists in the container

---

## How to Fix It

### Step 1: Try building to see the errors

```bash
docker build -t webapp:fixed /opt/webapp/
```

- `docker build` — build a Docker image from a Dockerfile
- `-t webapp:fixed` — name the image `webapp` and tag it `fixed`. The `-t` stands for tag
- `/opt/webapp/` — the directory containing the Dockerfile and the application files. This is called the "build context"

This will fail. **Read the error output** — it tells you what went wrong and which line caused it.

### Step 2: Read the Dockerfile

```bash
cat /opt/webapp/Dockerfile
```

- `cat` — prints a file's contents to the terminal

Look for the issues: commented-out COPY lines, and npm install running with no files to work with.

### Step 3: Check what files exist

```bash
ls -la /opt/webapp/
```

- `ls` — list the contents of a directory
- `-l` — long format showing permissions, sizes, and dates
- `-a` — include hidden files (files starting with a dot)

This shows you what files need to get into the container: `app.js`, `package.json`, and the Dockerfile itself.

### Step 4: Write the fixed Dockerfile

```bash
cat > /opt/webapp/Dockerfile << 'EOF'
FROM node:20-alpine

WORKDIR /app

COPY package.json .
RUN npm install

COPY app.js .

CMD ["npm", "start"]
EOF
```

- `cat >` — redirects text into a file, overwriting whatever was there
- `<< 'EOF'` — a "here document." Everything between this line and the closing `EOF` becomes the file contents. The quotes around `'EOF'` stop the shell from interpreting special characters

What changed:
- **Uncommented the COPY lines** — `package.json` and `app.js` now actually get copied into the container
- **Moved COPY before RUN** — `package.json` is copied in first, then `npm install` reads it and downloads the packages, then `app.js` is copied in
- **Changed `FROM node:23-alpine` to `FROM node:20-alpine`** — version 20 is an LTS (Long Term Support) release, meaning it gets security updates for years. Version 23 works fine, but 20 is the safer choice for production
- **Changed CMD to exec form** — see the improvements section below for why

### Step 5: Build the fixed image

```bash
docker build -t webapp:fixed /opt/webapp/
```

Same command as Step 1. This time every step should complete successfully.

### Step 6: Run the container

```bash
docker run -d --name webapp webapp:fixed
```

- `docker run` — create and start a container from an image
- `-d` — detached mode. Runs in the background so you get your terminal back
- `--name webapp` — gives the container the name `webapp`. The validation script checks for this specific name
- `webapp:fixed` — the image to create the container from

### Step 7: Check it's working

```bash
docker exec webapp wget -qO- http://localhost:8080
```

- `docker exec` — run a command inside a running container
- `webapp` — the container name
- `wget` — makes an HTTP request. Alpine images include `wget` but not `curl`, so we use this instead
- `-q` — quiet mode, hides wget's own progress output
- `-O-` — the capital O means "output to..." and the dash means "the terminal" rather than saving to a file
- `http://localhost:8080` — the address to request. `localhost` means "this machine" (inside the container), and `8080` is the port the app listens on

You should see: `{"status":"ok","service":"webapp"}`

---

## Best Practice Improvements (Not Bugs)

These two changes make the Dockerfile better but aren't required to fix the build. The app works without them.

### CMD exec form

**Before:** `CMD npm start`
**After:** `CMD ["npm", "start"]`

The first version is called "shell form" — Docker wraps it as `/bin/sh -c npm start`, which means a shell process runs, and then npm runs inside that shell.

The second version is "exec form" — Docker runs npm directly, without a shell wrapper.

Why it matters: when Docker wants to stop a container, it sends a signal. With shell form, the signal goes to the shell, which might not pass it on to npm. With exec form, npm receives the signal directly and can shut down cleanly.

In this lab it makes no practical difference. In production, use exec form.

### EXPOSE

The fixed Dockerfile could optionally include:

```dockerfile
EXPOSE 8080
```

This doesn't open a port or change how the app works. It's a label — a note in the image metadata that says "this container expects traffic on port 8080." Some tools read this label, and it helps other people understand the image. But removing it changes nothing about whether the app runs.

To actually make the app reachable from outside the container, you'd use `-p 8080:8080` on the `docker run` command. `EXPOSE` alone doesn't do that.

---

## Why COPY package.json and COPY app.js Are Separate

You might wonder why we don't just copy both files at once and then run npm install. You can. It works. The app builds and runs.

The reason they're separated is about **rebuild speed**. Here's how it works:

Docker remembers what it did last time you built. Each line in the Dockerfile creates a "layer." If nothing has changed at a particular line, Docker reuses the cached result and skips it.

**But here's the key rule: if one layer changes, Docker throws away the cache for that layer and every layer after it.**

So with our order:

```
COPY package.json .    ← Layer 1
RUN npm install        ← Layer 2
COPY app.js .          ← Layer 3
```

If you edit `app.js` (change your code) and rebuild:
- Layer 1: `package.json` hasn't changed → **cached, skipped**
- Layer 2: `npm install` hasn't changed → **cached, skipped** (no re-downloading)
- Layer 3: `app.js` changed → **rebuilt**

Fast rebuild. Seconds.

If both COPYs were together:

```
COPY package.json .    ← Layer 1
COPY app.js .          ← Layer 2
RUN npm install        ← Layer 3
```

If you edit `app.js` and rebuild:
- Layer 1: `package.json` hasn't changed → **cached, skipped**
- Layer 2: `app.js` changed → **rebuilt**
- Layer 3: everything after a changed layer must re-run → **npm install runs again for no reason**

Slow rebuild. Downloads all packages again even though they haven't changed.

In this lab with one tiny app, it doesn't matter. In a real project with hundreds of packages, it saves minutes on every build.

---

## Key Concepts Learned

- **Instruction order matters** — you can't use a file before COPY'ing it into the container. The file simply doesn't exist yet
- **Alpine images are minimal** — they include `wget` but not `curl`, and many tools you'd expect on a full Linux system aren't installed
- **Read the error messages** — Docker build errors tell you exactly which line failed and why. Start with the first error and work down
- **Separate real bugs from best practices** — some things break the build (missing files, wrong order). Other things are improvements that make the Dockerfile better but don't affect whether it works (exec form CMD, EXPOSE, layer ordering)

---

## Common Mistakes

- **Not reading the build output** — Docker tells you exactly what's wrong. Read the error before staring at the Dockerfile
- **Using `curl` in alpine containers** — alpine doesn't have curl. Use `wget` instead
- **Using `node:latest`** — the `latest` tag changes without warning. Pin to a specific version like `node:20-alpine`
- **Forgetting `WORKDIR`** — without it, files get copied to the root filesystem, which is messy and can conflict with system files
- **Confusing EXPOSE with publishing ports** — `EXPOSE` is just a label. Use `-p` on `docker run` to actually make ports accessible from outside the container
