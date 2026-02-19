# Cloud Engineer Labs

A self-directed lab framework for practising real-world cloud engineering and Linux troubleshooting skills. Each lab simulates a realistic broken or incomplete environment that you must diagnose and fix — just like you would on the job.

## Structure

```
cloud-engineer-labs/
├── cloud-labs/          # Terraform-based AWS infrastructure labs
│   └── lab-001-vpc-troubleshooting/
├── linux-labs/          # Docker-based Linux troubleshooting labs
│   ├── lab-001-nginx-down/
│   ├── lab-002-dns-broken/
│   └── lab-003-disk-full/
├── tools/               # CLI runner and utilities
│   └── labrunner.sh
└── README.md
```

## How It Works

### Linux Troubleshooting Labs (Docker-based)

Each lab is a Docker container with a deliberately introduced fault. Your job is to:

1. Read the `CHALLENGE.md` for the scenario
2. Start the lab with the runner tool or `docker compose up -d`
3. Exec into the container and diagnose the problem
4. Fix it
5. Run the validation to confirm your fix

**No internet required. No AWS costs. Fully local.**

### Cloud Infrastructure Labs (Terraform-based)

Each lab uses Terraform to provision a deliberately broken or incomplete AWS environment. Your job is to:

1. Read the `CHALLENGE.md` for the scenario
2. Run `terraform apply` to create the broken environment
3. Diagnose and fix the infrastructure (via console, CLI, or Terraform)
4. Run the validation script to confirm

**Requires an AWS account or KodeKloud Playground session.**

## Quick Start

```bash
# Run a random Linux lab
./tools/labrunner.sh random linux

# Run a specific lab
./tools/labrunner.sh start linux-labs/lab-001-nginx-down

# List all available labs
./tools/labrunner.sh list
```

## Prerequisites

- Docker and Docker Compose
- Terraform (for cloud labs)
- AWS CLI configured (for cloud labs)
- Bash 4+

## Building Your Own Labs

See [CREATING_LABS.md](CREATING_LABS.md) for the full guide on adding your own labs to this framework.
