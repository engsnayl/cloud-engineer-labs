# git-drills

A practice toolkit for daily-driver git fluency. Two modes:

- **Scenario drills** (`gitdrill start NNN`) - pre-built broken repos, you fix
  them with real commands, validator checks actual git state, deep walkthrough
  per drill. The teaching mode.
- **Quickfire** (`gitdrill quickfire N`) - rapid-fire questions covering the
  breadth of daily-driver git. Type the command, instant feedback, auto-advance.
  The muscle-memory mode.

Both share progress tracking via `gitdrill progress`.

## What's in this batch

### Scenario drills

| Drill                              | Topic                                                  |
|------------------------------------|--------------------------------------------------------|
| 001 staging-basics                 | git add, git restore --staged, working tree vs index   |
| 002 amend-last-commit              | git commit --amend, history rewriting before push      |
| 003 create-and-switch-branch       | git switch -c, branch hygiene, switch vs checkout      |
| 004 simple-rebase                  | git rebase, rebase vs merge mental model               |
| 005 reflog-rescue                  | git reflog, recovering from a bad reset                |

### Quickfire question bank (40 questions)

Categories: inspection, staging, committing, branching, merging, rebasing,
conflicts, rescue, remotes, stash, tags, diff.

## Install on the Pi

This directory lives inside the `cloud-engineer-labs` repo at
`~/cloud-engineer-labs/git-drills/`. After pulling the latest changes:

```bash
cd ~/cloud-engineer-labs
git pull
chmod +x git-drills/tools/gitdrill.sh
chmod +x git-drills/drills/*/seed.sh
chmod +x git-drills/drills/*/validate.sh
```

Add a `gitdrill` function to `~/.bashrc` (mirrors the existing `lab` pattern):

```bash
gitdrill() {
    bash "$HOME/cloud-engineer-labs/git-drills/tools/gitdrill.sh" "$@"
}
```

Then `source ~/.bashrc` (or open a new shell).

## Workflow (scenario drills)

```bash
gitdrill list                    # see all drills
gitdrill start 1                 # seed drill 001 in /tmp/gitdrill-001-staging-basics
cd /tmp/gitdrill-001-staging-basics
# ... do real git work ...
gitdrill validate                # check whether the drill is solved
gitdrill show                    # read the investigative walkthrough
gitdrill reset                   # re-seed the current drill to try again
```

## Workflow (quickfire)

```bash
gitdrill quickfire 10            # 10 random questions, instant feedback
gitdrill quickfire all           # every question once, shuffled
gitdrill progress                # session history, accuracy, weak spots
```

Inside a quickfire session:

- Type the command you'd run, press Enter
- Multiple acceptable spellings count as correct (e.g. `git restore --staged X`
  and `git reset HEAD X` both work)
- `:skip` skips a question (shows you the canonical answer)
- `:quit` ends the session early with a partial summary

## File layout

```
git-drills/
├── tools/
│   ├── gitdrill.sh             # the runner (dispatches to subcommands)
│   ├── quickfire.sh            # quickfire session + progress logic
│   ├── seed-helpers.sh         # shared functions for scenario seed.sh scripts
│   └── validate-helpers.sh     # assertion library for validate.sh scripts
├── drills/                     # scenario drills
│   ├── 001-staging-basics/
│   │   ├── CHALLENGE.md
│   │   ├── SOLUTION.md
│   │   ├── seed.sh
│   │   └── validate.sh
│   └── ...
└── quickfire/
    └── questions/              # one .md file per question, ~40 questions
        ├── q001.md
        └── ...
```

Progress is stored in `~/.gitdrill-progress.json` (per user, not in the repo).

## Design notes (carried over from cloud-engineer-labs standards)

- **No `# BUG` hint comments** anywhere in seed files
- **CHALLENGE.md never names bugs** or coaches toward diagnosis
- **validate.sh tests real git state**, not stdout grep - if you merge
  instead of rebase, validation catches it
- **SOLUTION.md is investigative cold-ticket format**: arrive without
  context, diagnose from symptoms, fix and explain why
- **Each drill is fully self-contained**: seed builds a fresh repo,
  `gitdrill reset` is `rm -rf` + re-run seed

## Adding new drills

Pattern: pick a number (next free), create `drills/NNN-short-name/`,
write the four files. The runner picks them up automatically. See any
existing drill for a working example.

## What's next

Categories on the roadmap (once these five feel right):

- 010s: more staging patterns (`add -p`, `restore <file>` for unstaging working tree changes, `clean`)
- 020s: more branching (delete merged/unmerged branches, rename branches, track remote branches)
- 030s: history rewriting (`rebase -i` for squash/reorder/fixup, autosquash workflow)
- 040s: conflicts (merge conflicts, rebase conflicts, theirs/ours strategies)
- 050s: more rescue (deleted branch recovery, undoing a pushed commit safely, ORIG_HEAD)
- 060s: collaboration (force-with-lease, fetch vs pull, tracking, upstream)
