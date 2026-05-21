# git-drills

A practice drill runner for daily-driver git fluency. Modelled on the
`cloud-engineer-labs` lab runner pattern - each drill seeds its own
throwaway repo, you do real git work in a real terminal, then
`gitdrill validate` checks the actual git state (refs, log shape,
working tree, index), not stdout.

## What's in this initial batch

| Drill                              | Topic                                                  |
|------------------------------------|--------------------------------------------------------|
| 001 staging-basics                 | git add, git restore --staged, working tree vs index   |
| 002 amend-last-commit              | git commit --amend, history rewriting before push      |
| 003 create-and-switch-branch       | git switch -c, branch hygiene, switch vs checkout      |
| 004 simple-rebase                  | git rebase, rebase vs merge mental model               |
| 005 reflog-rescue                  | git reflog, recovering from a bad reset                |

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

## Workflow

```bash
gitdrill list                    # see all drills
gitdrill start 1                 # seed drill 001 in /tmp/gitdrill-001-staging-basics
cd /tmp/gitdrill-001-staging-basics
# ... do real git work ...
gitdrill validate                # check whether the drill is solved
gitdrill show                    # read the investigative walkthrough
gitdrill reset                   # re-seed the current drill to try again
```

## File layout

```
git-drills/
├── tools/
│   ├── gitdrill.sh             # the runner
│   ├── seed-helpers.sh         # shared functions for seed.sh scripts
│   └── validate-helpers.sh     # assertion library for validate.sh scripts
└── drills/
    ├── 001-staging-basics/
    │   ├── CHALLENGE.md        # what to do, no spoilers, no bug hints
    │   ├── SOLUTION.md         # cold-ticket investigative walkthrough
    │   ├── seed.sh             # builds the starting repo
    │   └── validate.sh         # tests actual git state
    └── ...
```

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
