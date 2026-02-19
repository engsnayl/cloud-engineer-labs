Title: OOM Killer Striking — Memory Pressure and Swap Issues
Difficulty: ⭐⭐⭐ (Advanced)
Time: 15-20 minutes
Category: Memory Management
Skills: free, vmstat, swapon, /proc/meminfo, OOM killer, ulimits

## Scenario

The application server keeps having processes killed by the OOM (Out of Memory) killer. The server has swap configured but it doesn't appear to be active. Meanwhile, a memory-leaking process is consuming far more than it should.

> **INCIDENT-5301**: OOM killer has terminated the main application process 3 times today. Server has 2GB RAM and should have swap configured but `free` shows 0 swap. A background process appears to have a memory leak.

Fix the swap configuration and deal with the memory leak so the application stays stable.

## Objectives

1. Check current memory usage and identify the memory hog
2. Diagnose why swap is not active
3. Enable swap correctly
4. Kill or constrain the memory-leaking process
5. Verify the application process is running stably

## Validation Criteria

- Swap is enabled and active (>0 swap total in `free`)
- The memory-leaking process is not running
- The legitimate application process is running
- Total memory usage is below 80%

## What You're Practising

Understanding Linux memory management, swap, and the OOM killer is critical for right-sizing cloud instances and debugging memory-related outages. These skills directly apply to configuring Kubernetes resource limits and requests.
