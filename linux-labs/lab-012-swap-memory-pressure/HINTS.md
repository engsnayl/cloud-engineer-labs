# Hints — Lab 012: Swap and Memory Pressure

## Hint 1 — Check memory and swap status
`free -h` shows current memory and swap usage. If swap shows all zeros, it's not enabled. Check if a swap file exists with `ls -la /swapfile`.

## Hint 2 — Enable the swap
The swap file exists and is formatted, just not enabled. Use `swapon /swapfile` to activate it. Verify with `free -h`.

## Hint 3 — Find and kill the leak
Use `ps aux --sort=-%mem | head` to find the memory hog. Kill it with `kill <PID>`. Make sure you kill the leaking Python process, not the legitimate app.
