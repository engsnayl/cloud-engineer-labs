# ── Interview Drill (cloud-engineer-labs lab 095) ───────────────────────────
# Adds an `interview` command that launches the MCQ drill directly.
#
# Install:
#   cat cloud-labs/lab-095-interview-drill-mcq/bashrc-snippet.sh >> ~/.bashrc
#   source ~/.bashrc
#
# If the repo is NOT at ~/cloud-engineer-labs, set CLOUD_LABS_REPO first, e.g.:
#   export CLOUD_LABS_REPO="$HOME/Labs/cloud-engineer-labs"
interview() {
  local repo="${CLOUD_LABS_REPO:-$HOME/cloud-engineer-labs}"
  local runner="$repo/cloud-labs/lab-095-interview-drill-mcq/runner.sh"
  if [[ ! -x "$runner" ]]; then
    echo "interview: runner not found (or not executable) at: $runner" >&2
    echo "Set CLOUD_LABS_REPO to your cloud-engineer-labs checkout and retry." >&2
    return 1
  fi
  bash "$runner"
}
