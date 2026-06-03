# Batch T3.2 — checkpoint (GATE: HOLD for ruling)

**Tier 3, batch T3.2 — 13 items: 12 full reauthors + 1 option-balance.** Surface format = summaries + borderlines-only (per Stephen). Completes the locked Tier-3 universe (T3.1 15 + T3.2 13 = 28).

## Gate results

| Check | Result |
|---|---|
| Pilot-dupe pre-flight (13 ids) | 0 matches |
| `validate_mcqs.py` (banks 1/2/3) | OK / OK / OK (0 errors) |
| `check_drift.py` T3.2 | **PASS** — 13/13 touched cleared, 0 regressions |
| `audit_suspect.py` on touched ids | 5 entries — all recorded FPs (standing rule; see §E) |
| Explanation length | all ≤130 words (85–101) |
| Length-tell (B2) | 0/13 trip the giveaway threshold; correct-longest 13/13 but within the parity band (distractors lengthened to carry their own mechanism). Bank-wide correct-is-longest check deferred to Tier-3 close. |

## A. Compare-pairs (4) — strike-test + distinctness (reported per Stephen)

- **`tf-012-mcq-2`** — KEY: `terraform import`. **Strike-test:** remove *"An engineer created an S3 bucket by hand… holds production data"* → *"Which command brings it under management?"* loses its referent → **COLLAPSES ✓** (options classify which command for THIS situation, not `state mv` vs `import` definitions). **Distinctness:** sibling `tf-012-mcq-1` = in-state `for_each` rename via `moved {}`; this = adopting an OUT-of-state live resource via `import`; `moved {}` appears here as a wrong-tool distractor, reinforcing the split. Distractors: state-mv-adopts / apply-auto-adopts / moved-block-adopts — real misconceptions.
- **`docker-001-mcq-1`** — KEY: shared host kernel (namespaces/cgroups) vs separate-kernel VMs. **Strike-test:** remove *"A container on a shared host is compromised through a kernel-level escape CVE"* → *"Why can this impact other containers when VMs would be unaffected?"* → **COLLAPSES ✓**. **Distinctness:** sibling `docker-001-mcq-2` = when to choose a VM (hostile/multi-tenant); this = why a kernel escape's blast radius differs. Distractors: containerd-as-hypervisor / namespace-inheritance / per-container-kernel.
- **`docker-007-mcq-1`** — KEY: named volume (Docker-managed, portable). **Strike-test:** remove *"works on every laptop via a bind mount to /home/$USER/data… fails on CI and a Pi"* → *"What change fixes portability while keeping data persistent?"* → **COLLAPSES ✓**. **Distinctness:** sibling `docker-007-mcq-2` = tmpfs for ephemeral secrets; this = bind→named for portability, with tmpfs as a wrong-tool distractor. Distractors: read-only-fixes / tmpfs-for-portability / relative-bind-portable.
- **`git-003-mcq-1`** — KEY: a fork is a server-side copy under your own account you CAN push to (→ pull request). **Strike-test:** remove *"An engineer without write access… clone… push… rejected"* → *"What did they skip, and why does it fix it?"* → **COLLAPSES ✓**. **CROSS-TIER DISTINCTNESS (reported):** committed sibling `git-003-mcq-2` (T2.1) tests the `upstream`-remote **sync** workflow; this reauthor tests **fork-as-writeable-copy-enabling-PRs** — a distinct facet. The upstream-remote idea is deliberately used as the WRONG distractor (d1), cleanly separating the two facets. Distractors: upstream-grants-push / SSH-vs-HTTPS-write / force-push-bypasses.

## B. Multi-flag A+D (4) — both flags fixed

- **`tf-005-mcq-1`** — KEY: workspaces share one config/backend (differ only by state), so structurally-different envs can't be modelled cleanly. **D:** actor-marker scenario stem. **A:** fabricated "deprecated/removed in 1.0" replaced (→ vars-can't-differ misconception). Distinct from sibling (recommended separate-state model).
- **`tf-009-mcq-1`** — KEY: plan-on-PR + apply-on-merge. **D:** goal-scenario stem. Distractors: apply-before-review / plan-blocks-devs / state-on-laptops. Distinct from sibling (concurrent-apply state lock).
- **`docker-002-mcq-2`** — KEY: non-root `USER`. **D:** scenario stem (currently runs as root). Distractors: host-MAC-replaces-nonroot / `:latest`-auto-patches / secret-in-image. Distinct from sibling (layer caching).
- **`docker-009-mcq-2`** — KEY: immutability keeps the tag→digest mapping stable under lifecycle expiry. **D:** actor-marker scenario stem. **A:** fabricated billing-tier + tag-rotation replaced (→ exempt-from-expiry / lifecycle-needs-immutability / auto-promote-`:latest` misconceptions). Distinct from sibling (ECR auth).

## C. Plain structural (4)

- **`tf-004-mcq-1`** (was D_match_style + B_scrambles) — order-of-precedence → concrete-values scenario; KEY `t3.large` (CLI > files > env > default). Distractors: env-wins / tfvars-authoritative / errors-on-conflict.
- **`tf-010-mcq-1`** (was D_match_style) — tool-match → golden-image scenario; KEY Packer builds the AMI, Terraform deploys it. Distractors: swapped-roles / Packer-does-both / user_data-replaces-Packer.
- **`docker-003-mcq-2`** (was C_never_correct) — question flipped to *"is it recoverable?"* so correct reframes "No"→**"Yes, it's recoverable"**; KEY layers are inspectable, use BuildKit `--secret` / discarded multi-stage. Distractors: ARG-stripped / ARG-encrypted / non-final-purged.
- **`linux-003-mcq-1`** (was D_match_style) — unit-match → scheduled-task scenario; KEY `.timer` + `.service` pairing. Distractors: timer-holds-command / service-`OnCalendar=` / target-schedules.

## D. Option-balance (1)

- **`k8s-020-mcq-1`** (B_structural_option_balance) — per your note: **lengthened the one-word correct** ("StatefulSet") to carry its mechanism (stable identity + per-replica PVC) **to parity** — 100 chars, tied with the longest distractor (100), not an outlier. Distractors untouched; stem/explanation unchanged. 0 trip.

## E. Borderlines — 5 suspect FPs (standing rule applied)

Each ran the misconception-vs-fabrication check → real misconception, no named-identifier fabrication → **recorded FP, kept**:

- `git-003-mcq-1/d3` (`specific-flag`: `--force`) — real flag; misconception that force-push bypasses a permission denial.
- `tf-004-mcq-1/d2`, `docker-002-mcq-2/d2`, `docker-003-mcq-2/d1` (`auto-implicit`: "automatically") — tfvars-authoritative / `:latest`-auto-patches / ARG-auto-stripped — all real misconceptions.
- `tf-005-mcq-1/d1` (`constraint-cannot-without`) — "workspaces can't be selected non-interactively," a real false belief.

**Recommendation:** keep all 5; no rework.

## Disposition

**HOLD all commits for your ruling.** On approval: update `tracking.json` (T3.2 COMPLETE, 0 dropouts, 5 suspect FPs, B2 distractor-lengthening applied); commit scope = `batch-08-tier3-part2.json` + this checkpoint + `tracking.json` + the 3 bank files; delete the scratch builder; exclude derived artifacts (`draft-audit.json`, gitignored `suspect-distractors.json`). **T3.2 completes Tier 3** → next is Tier-3 close (bank-wide correct-is-longest check per B2; reconcile any residual queue items).
