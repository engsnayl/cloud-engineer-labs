Title: SSH Access Denied — Key Authentication Failing
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: Authentication / SSH
Skills: ssh, file permissions, sshd_config, authorized_keys, journalctl

## Scenario

The development team can't deploy to the staging server. Their CI/CD pipeline uses SSH key authentication to push code, but since the security hardening last week, all SSH connections are being rejected with "Permission denied (publickey)".

> **INCIDENT-4856**: CI/CD pipeline failing — SSH key auth rejected on staging server. Deployments blocked for 3 hours. Dev team escalating.

You need to fix SSH key authentication so the deploy user can connect.

## Objectives

1. Diagnose why SSH key authentication is failing
2. Identify all SSH-related misconfigurations
3. Fix permissions and configuration issues
4. Ensure the deploy user can authenticate with their SSH key
5. Verify sshd is running and accepting connections

## What You're Practising

SSH key authentication issues are extremely common in cloud environments. Every time you provision a new EC2 instance, set up a bastion host, or configure CI/CD, you need to understand the SSH permission model. Getting the file permissions wrong is the #1 cause of SSH auth failures.
