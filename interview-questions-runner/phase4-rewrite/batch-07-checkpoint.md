# Batch T3.1 — checkpoint (COMPLETE — rulings B1/B2/B3 applied)

**Tier 3, batch T3.1 — 15 full from-scratch reauthors.** Calibration batch; bar confirmed by Stephen 2026-06-03. T3.2 onward runs on summaries + borderlines-only.

## Gate results

| Check | Result |
|---|---|
| Pilot-dupe pre-flight (15 ids) | 0 matches |
| `validate_mcqs.py` (banks 1/2/3) | OK / OK / OK (0 errors) |
| `check_drift.py` T3.1 | **PASS** — 15/15 touched cleared, 0 regressions |
| `audit_suspect.py` on touched ids | 3 entries, all `auto-implicit` — reviewed false positives (see below) |
| Explanation length | all ≤130 words (range 90–107) |
| Length-tell | 0/15 trip the giveaway threshold; 12/15 correct-is-longest (see note) |

## Cluster order authored
compare-pair (1) → superlatives (2) → multi-flag A+D (4) → plain structural (8).

## Per-cluster transformation targets — confirmed
Each item's `_italic_` line states how its specific flag combination was transformed (not a generic reauthor). **No dropouts** — all 15 sources decomposed into rubric-compliant MCQs.

---
## A. Cluster items — full text + per-option self-check

### cicd-001-mcq-1

_**compare-pair → load-bearing scenario.** Strike *"Leadership now wants every commit that passes tests to reach production automatically, with no human in the loop"* and the stem ("what single change?") has no referent — it collapses. Options are concrete actions, not definition-pairs. Distinct from sibling cicd-001-mcq-2 (classifies a gated pipeline as Continuous Delivery); this tests the Delivery→Deployment transition._

**Q.** Your team's pipeline runs build → test → deploy-to-staging, then stops at a manual 'Promote to prod' gate a release manager clicks during business hours. Leadership now wants every commit that passes tests to reach production automatically, with no human in the loop. What single change accomplishes that?

- **✔ correct:** Remove the manual promotion gate so each passing build deploys to prod on its own — that gate is the only thing separating their current Continuous Delivery from the Continuous Deployment leadership is describing
- distractor_1: Add another pre-prod environment after staging; what makes a pipeline Continuous Deployment is deploying through a chain of staged environments, not whether a human approves the final step
- distractor_2: Rebuild the pipeline to ship container images instead of its current build artifacts; Continuous Deployment is defined by the artifact type, and the approval gate is a separate concern
- distractor_3: Schedule the prod deploy to fire automatically each night at a fixed time without the release manager; a scheduled, hands-off release is what Continuous Deployment means

**Explanation.** Continuous Delivery automates everything up to a deploy-ready artifact and stops at a human gate; Continuous Deployment removes that gate so every passing commit ships itself. Deleting the manual promotion step is the whole difference. Distractor 1 invents an environments-count definition — staging chains are orthogonal to the gate. Distractor 2 ties the term to artifact type, but auto-vs-manual is the real axis. Distractor 3 conflates 'scheduled at 2am' with Continuous Deployment, which triggers on each commit, not a clock — and the scenario's automatic-at-night wording is the bait.

**6-month self-check (per option):**
- correct — PASS — removing the human gate is the textbook Delivery→Deployment boundary; factually dominant.
- distractor_1 — PASS — junior conflates 'more staged environments' with 'more continuous'; no fabricated identifier.
- distractor_2 — PASS — plausible mis-association (containers ≡ modern CD); conceptual, no fabrication.
- distractor_3 — PASS — common conflation of 'automatic at a fixed time' with CD. **suspect-FP (auto-implicit keyword 'automatically'); a real misconception, not a fabrication.**

### aws-021-mcq-1

_**superlative → positive best-fit, made factual via a tightened constraint (B3 version B, applied 2026-06-03).** The stem adds *"100% Spot, no on-demand fallback, zero user-visible impact on reclaim"* so exactly one architecture qualifies — single-select, no dropped co-valid option. The stateless-web tier is *retained* as a constraint-ruled-out distractor (it needs the forbidden on-demand baseline and a reclaim drops user-facing requests); single-node Postgres dropped (lowest discrimination). Distinct from sibling aws-021-mcq-2 (Savings Plans). No WORST/NOT stem._

**Q.** Your team wants to cut compute cost by moving exactly one of these workloads onto 100% Spot with no on-demand fallback, and a node reclaim (two-minute warning) must cause zero user-visible impact. Which workload is the BEST fit?

- **✔ correct:** A nightly Spark batch job that checkpoints its progress and restarts from the last checkpoint after an interruption — it runs asynchronously, so a reclaim delays no user-facing request
- distractor_1: A stateless web tier behind an ALB with autoscaling and at least a 50% on-demand baseline, leaning on that baseline to keep serving users whenever Spot capacity is reclaimed
- distractor_2: A synchronous payment API where each in-flight request must finish, so a reclaimed node fails the customer's transaction mid-flight
- distractor_3: A 12-hour ML training run that holds all state in memory and writes no checkpoints, losing everything if the node is reclaimed near the end

**Explanation.** With a 100%-Spot, no-fallback, zero-user-impact constraint, only an asynchronous job that resumes cleanly after reclamation qualifies — the checkpointing batch fits exactly. Distractor 1 (stateless web tier) is ruled out twice: it depends on the on-demand baseline the constraint forbids, and a reclaim drops in-flight user requests, which is user-visible. Distractor 2 (synchronous payment API) is the most user-visible failure — a reclaimed node fails a live customer transaction. Distractor 3 (un-checkpointed ML run) tolerates no interruption: a reclaim near hour 11 discards the whole run. Interruption tolerance plus no user-facing path is what Spot needs here; only the batch job has both.

**6-month self-check (per option):**
- correct — PASS — the async checkpointing job is the only one satisfying 100%-Spot + zero-user-impact; uniquely best under the constraint.
- distractor_1 — PASS — constraint-ruled-out twice (needs the forbidden on-demand baseline; a reclaim drops user-facing requests). Lengthened per B2 to carry its own mechanism.
- distractor_2 — PASS — synchronous API is the most user-visible failure on reclaim; plausible.
- distractor_3 — PASS — un-checkpointed 12h run loses everything on a late reclaim; plausible trap.

### aws-022-mcq-1

_**superlative → positive best-fit, factual.** Discriminator is Lambda's 15-min cap; Fargate uniquely keyed. Distinct from sibling aws-022-mcq-2 (ECS-vs-EKS ops overhead) by anchoring correctness on the runtime-limit facet rather than ops overhead._

**Q.** Your team runs a video transcoding service whose individual jobs take 20-90 minutes and run constantly throughout the day. Considering Lambda, ECS Fargate, and EKS, which platform is the BEST fit?

- **✔ correct:** ECS Fargate — it runs the containerised jobs with no platform execution-time limit and no nodes or control plane to operate, matching steady 20-90-minute work
- distractor_1: Lambda — its event-driven model and per-millisecond billing make it the cheapest choice for jobs of any duration
- distractor_2: EKS — only Kubernetes can run a job past Lambda's and Fargate's shared 15-minute execution ceiling, so the job length forces EKS
- distractor_3: Any of the three works equally; for constantly-running jobs the decision is purely cost, not execution-time limits

**Explanation.** The discriminator is Lambda's hard 15-minute timeout, which kills a 20-90-minute job mid-work; Fargate runs containers with no such cap and the least operational overhead, so it's the best fit. Distractor 1 over-applies Lambda — cheap billing is irrelevant once the job can't finish in 15 minutes. Distractor 2 invents a 15-minute ceiling on Fargate (Fargate tasks run as long as the container does), so its premise for forcing EKS is false. Distractor 3 ignores the runtime constraint entirely, which is the one thing that rules a platform in or out here.

**6-month self-check (per option):**
- correct — PASS — no execution cap + least overhead makes Fargate the factual best of the three.
- distractor_1 — PASS — over-applies Lambda; the 15-min cap is the factual blocker, not cost.
- distractor_2 — PASS — natural mis-extension of Lambda's 15-min limit onto Fargate (invented behaviour of a real feature); plausible.
- distractor_3 — PASS — 'cost only' ignores the runtime constraint; plausible.

### k8s-001-mcq-2

_**multi-flag C+D+A, both/all fixed.** D: stem reframed to actor-marker scenario ("An engineer proposes…") → classifies `scenario`. C: correct no longer opens with "Essentially never". A: all three fabrications (min-2-replicas rule, standalone-RS rollback immunity, runtime-compat difference) replaced with real misconceptions, each unambiguously wrong against the new "what do you give up" stem._

**Q.** An engineer proposes creating a bare ReplicaSet directly, not a Deployment, to run a long-lived stateless service, arguing it's one less layer. What does the service give up by skipping the Deployment?

- **✔ correct:** Rolling updates, rollback to previous revisions, and revision history — the Deployment controller adds exactly those on top of a ReplicaSet, so a bare RS is strictly less capable for a long-lived service
- distractor_1: Nothing important — a ReplicaSet already performs rolling updates by gradually replacing its pods whenever you edit its pod template, so a Deployment is mostly a convenience alias
- distractor_2: Self-healing — a bare ReplicaSet won't recreate a pod that crashes, so the service loses the automatic restart guarantee a Deployment provides
- distractor_3: Horizontal autoscaling — an HPA can only attach to a Deployment, so a bare ReplicaSet loses the ability to scale on CPU or memory

**Explanation.** A Deployment manages ReplicaSets to deliver rolling updates, rollback, and revision tracking; a bare RS only holds a pod count steady. Distractor 1 is the core misconception — editing an RS template does not roll existing pods (only new pods use it), so an RS gives no rolling update. Distractor 2 inverts the RS's whole job: maintaining replica count means it does recreate crashed pods. Distractor 3 invents an HPA-needs-a-Deployment rule — an HPA can target a ReplicaSet through its scale subresource, so autoscaling doesn't require one. The honest answer: almost always use a Deployment.

**6-month self-check (per option):**
- correct — PASS — accurately names what a Deployment layers on; positive phrasing (clears C).
- distractor_1 — PASS — editing an RS template doesn't roll existing pods; common 'RS does rolling updates' confusion.
- distractor_2 — PASS — inverts the RS's core job; plausible for an unsure junior. **suspect-FP (auto-implicit 'automatic restart'); real misconception.**
- distractor_3 — PASS — HPA can target a ReplicaSet via its scale subresource, so 'HPA needs a Deployment' is false; widely held.

### k8s-011-mcq-1

_**multi-flag C+A, both fixed.** C: correct reworded off the leading "No". A: fabricated `ingress-enabled=true` label and the invented "built-in EKS Ingress provider (30-60 min)" replaced with three real controller misconceptions (attach-to-LB-Service, namespace-scoped reconcile, waits-for-healthy-endpoints). Each is wrong against the actual cause (no controller installed)._

**Q.** You deploy an Ingress resource on EKS, but external traffic never reaches your services and the Ingress shows no Address even after several minutes. What's the most likely cause?

- **✔ correct:** The cluster has no Ingress controller running — an Ingress is only a routing spec, and without a controller (AWS Load Balancer Controller, NGINX, etc.) nothing provisions a load balancer or populates the Address
- distractor_1: The Ingress has no companion LoadBalancer Service in its namespace to attach to; an Ingress forwards to a LoadBalancer Service, which is what actually receives the external address
- distractor_2: The Ingress controller is running in a different namespace from the Ingress, and a controller only reconciles Ingress objects that live in its own namespace
- distractor_3: The backend Service has no healthy pod endpoints yet; the ALB and its Address are only created once at least one target is passing health checks

**Explanation.** An Ingress object is inert until an Ingress controller reads it and provisions real infrastructure — no controller, no Address. Distractor 1 invents a LoadBalancer-Service-as-attachment-target; the controller provisions the load balancer itself from the Ingress spec. Distractor 2 fabricates namespace-scoping — controllers like the AWS LB Controller watch Ingresses cluster-wide, not just their own namespace. Distractor 3 ties Address creation to healthy endpoints, but the controller provisions the ALB and assigns the Address regardless of target health; unhealthy targets just fail to receive traffic. The fix is installing a controller.

**6-month self-check (per option):**
- correct — PASS — no controller installed is the real cause; reworded off leading 'No' (clears C).
- distractor_1 — PASS — wrong-mechanism (controller provisions the LB itself); plausible.
- distractor_2 — PASS — wrong-scope (LB Controller watches cluster-wide); plausible.
- distractor_3 — PASS — wrong-dependency (ALB+Address provision regardless of target health); plausible.

### k8s-021-mcq-2

_**multi-flag D+A, both fixed.** D: stem reframed to actor-marker scenario ("Your team runs a 6-replica Deployment…") → `scenario`. A: fabricated annotation `scheduler.alpha.kubernetes.io/balanced=true` replaced with an over-trust-the-default-scheduler misconception. Distractors are wrong against the even-spread requirement._

**Q.** Your team runs a 6-replica Deployment and needs the replicas spread evenly across all three AZs, so losing any one zone removes at most a third of capacity. Which configuration enforces that even spread?

- **✔ correct:** TopologySpreadConstraints keyed on topology.kubernetes.io/zone with maxSkew: 1, so the scheduler holds per-zone replica counts within one of each other
- distractor_1: Pod anti-affinity with preferredDuringSchedulingIgnoredDuringExecution on the zone label, so the scheduler tries to place each replica in a different zone
- distractor_2: Just set replicas to 6 and rely on the default scheduler, which already balances same-Deployment pods evenly across zones without extra configuration
- distractor_3: A nodeSelector pinning the pods to one AZ, after which the cluster autoscaler redistributes them across the other zones to balance load

**Explanation.** TopologySpreadConstraints with maxSkew is the explicit, enforced way to hold an even spread across zones. Distractor 1 is the near-miss: a preferred anti-affinity is only a soft hint, so under scheduling pressure the scheduler will still pack replicas into one zone. Distractor 2 over-trusts the default scheduler — without a spread constraint, even placement is best-effort, not the maxSkew-1 guarantee the requirement needs. Distractor 3 inverts the goal by pinning to a single AZ, and the cluster autoscaler scales node capacity rather than rebalancing pods across zones. Topology spread is the modern successor to anti-affinity spreading.

**6-month self-check (per option):**
- correct — PASS — TopologySpreadConstraints maxSkew:1 is the modern enforced mechanism.
- distractor_1 — PASS — soft-vs-hard near-miss; the strongest distractor (preferred anti-affinity only hints).
- distractor_2 — PASS — over-trusts default scheduler (best-effort, not maxSkew-1 guarantee); plausible.
- distractor_3 — PASS — inverts the goal (pins one AZ); CA-rebalances-pods is invented behaviour, plausible.

### k8s-041-mcq-2

_**multi-flag D+A, both fixed.** D: definition/compare stem ("What's the practical difference…") reframed to a scenario decision (fresh cluster, no OIDC, least ceremony). A: fabricated 1.27-deprecation, EBS-CSI dependency, and EKS-Anywhere scope replaced with real IRSA-vs-Pod-Identity misconceptions. Distinct from sibling k8s-041-mcq-1 (defines IRSA)._

**Q.** Your team is wiring up pod-level AWS access on a brand-new EKS cluster with no OIDC provider configured yet, and wants the least setup ceremony, accepting a relatively new feature. Between IRSA and EKS Pod Identity, which fits and what's the tradeoff?

- **✔ correct:** EKS Pod Identity — it relies on a per-node agent and needs no OIDC provider or trust-policy wiring, so setup is minimal; the tradeoff is that it's newer, so some IAM and tooling templates still assume IRSA
- distractor_1: IRSA — it's the only one of the two that issues short-lived credentials; Pod Identity hands the pod a long-lived IAM access key from the node agent, which the no-long-lived-keys goal rules out
- distractor_2: IRSA actually needs less setup here — Pod Identity requires installing and operating a separate controller and CRDs, whereas IRSA is built into the control plane with nothing to add
- distractor_3: Pod Identity, but only because its credentials are configured per-pod in the manifest rather than per-service-account, so they don't survive a reschedule onto another node

**Explanation.** Pod Identity authenticates pods via the eks-pod-identity-agent on each node, skipping the OIDC-provider and trust-policy setup IRSA requires — so it's the lower-ceremony fit on a fresh cluster. Distractor 1 is false on mechanism: both issue temporary credentials; neither plants a static key. Distractor 2 inverts the setup cost — IRSA's OIDC ceremony is the heavier one, and Pod Identity installs as a single managed add-on. Distractor 3 misdescribes Pod Identity as per-pod; associations are per-service-account and survive rescheduling, just like IRSA. New clusters increasingly default to Pod Identity.

**6-month self-check (per option):**
- correct — PASS — accurate tradeoff (lower ceremony, newer/less ubiquitous tooling).
- distractor_1 — PASS — wrong-mechanism ('long-lived node key'); both issue temporary creds; plausible junior assumption.
- distractor_2 — PASS — inverts setup cost; tempting because IRSA reads as the 'built-in' older option.
- distractor_3 — PASS — wrong-granularity (associations are per-service-account, survive reschedule); plausible.

---
## B. Plain-structural samples (3 of 8) — full text + per-option self-check

### cicd-010-mcq-1

_**plain structural: D_match_style + B_scrambles → scenario.** "What's the hierarchy of workflow/job/step/action" with scrambled-permutation options → a scenario where runner/filesystem sharing makes the hierarchy load-bearing. B_scrambles eliminated (no permutation options remain)._

**Q.** An engineer needs two shell commands to run on the same fresh runner VM sharing one working directory, while a third command runs on a different operating system. How should they structure this GitHub Actions workflow?

- **✔ correct:** Put the two commands as two steps in one job (steps in a job share the same runner and filesystem), and put the third command in a separate job that targets the other OS
- distractor_1: Put the two commands in one job and the third in a second workflow file, since a different operating system requires its own workflow rather than another job
- distractor_2: Put all three commands as separate jobs in one workflow; jobs in a workflow share a runner and working directory, so the first two still see each other's files
- distractor_3: Put the two commands as two actions inside a single step, and the third as another step, since actions are how you pin work to one runner

**Explanation.** The hierarchy is workflow → job → step: steps within a job share one runner and its filesystem, while each job gets a fresh runner (and can target its own OS). So two co-located commands belong as steps in one job; the differently-OS'd command needs its own job. Distractor 1 invents a one-workflow-per-OS rule — a job already selects its runner OS. Distractor 2 has it backwards: separate jobs do not share a runner or filesystem, so the first two commands would lose their shared directory. Distractor 3 misuses 'action' as a runner-pinning unit; actions are reusable step bodies, not a placement mechanism.

**6-month self-check (per option):**
- correct — PASS — accurate runner/filesystem model (steps share runner; jobs get fresh runners).
- distractor_1 — PASS — invents a one-workflow-per-OS rule; plausible.
- distractor_2 — PASS — the key inversion (jobs do NOT share a runner/filesystem); common confusion.
- distractor_3 — PASS — misuses 'action' as a runner-pinning unit; plausible.

### k8s-023-mcq-1

_**plain structural: D_match_style + B_scrambles → scenario.** "Match the autoscaler to what it changes" with scrambled options → a Pending-pods/nodes-full symptom scenario where the HPA/VPA/CA axes are load-bearing. B_scrambles eliminated._

**Q.** Your cluster has several pods stuck in Pending because every existing node is already full, even though the running pods are correctly right-sized. Which autoscaler resolves this?

- **✔ correct:** Cluster Autoscaler — it adds nodes when pods can't be scheduled for lack of capacity, then removes them when they're no longer needed
- distractor_1: Horizontal Pod Autoscaler — it raises the replica count, which schedules more pods so Kubernetes can place the Pending ones
- distractor_2: Vertical Pod Autoscaler — it increases the pods' CPU and memory requests so they fit onto the existing nodes
- distractor_3: Horizontal Pod Autoscaler combined with VPA — together they rebalance pods across the current nodes to free up room for the Pending ones

**Explanation.** Pending pods with all nodes full is a capacity problem, and only the Cluster Autoscaler changes node count to fix it. Distractor 1 picks HPA, but adding replicas creates more pods needing capacity — it worsens Pending, not resolves it. Distractor 2 picks VPA, which changes resource requests; raising requests makes pods harder to fit, and the pods are already right-sized. Distractor 3 imagines HPA+VPA rebalancing across nodes, but neither moves pods to manufacture capacity — that's the Cluster Autoscaler's job. The three operate on orthogonal axes: replicas, pod size, node count.

**6-month self-check (per option):**
- correct — PASS — only Cluster Autoscaler changes node count to clear capacity-bound Pending.
- distractor_1 — PASS — 'autoscale = HPA' reflex; adding replicas worsens Pending. Plausible.
- distractor_2 — PASS — VPA changes requests, won't add capacity; pods already right-sized. Plausible.
- distractor_3 — PASS — neither HPA nor VPA moves pods to manufacture capacity; plausible.

### aws-005-mcq-2

_**plain structural: C_never_correct → positive.** Correct reframed from "No —" to a positive statement ("The reporting load stays on the primary…"), clearing the flag while keeping the diagnose-the-outcome intent._

**Q.** A team hits CPU saturation on their RDS primary every afternoon, driven by heavy read-only reporting queries. They enable Multi-AZ expecting it to spread the read load. What actually happens, and what should they use instead?

- **✔ correct:** The reporting load stays on the primary — the Multi-AZ standby is a passive failover target serving no client reads; read replicas are what offload reads
- distractor_1: Multi-AZ begins load-balancing read traffic across the primary and the standby automatically, once both instances report healthy
- distractor_2: Reporting queries are automatically routed to the standby while transactional reads keep hitting the primary, splitting the load
- distractor_3: Enabling Multi-AZ promotes the synchronous standby into a hot read replica that serves strongly consistent reads alongside the primary

**Explanation.** Multi-AZ is a high-availability feature, not a read-scaling one: the standby receives replication writes but is invisible to applications until a failover promotes it. To shed read load you add read replicas and point reporting at them. Distractor 1 treats Multi-AZ as a read-balancer, which it isn't. Distractor 2 invents an automatic query-routing layer RDS doesn't provide. Distractor 3 misdescribes the standby — a synchronous Multi-AZ standby serves no client traffic at all, hot or otherwise. The trap is assuming the standby and a read replica are interchangeable.

**6-month self-check (per option):**
- correct — PASS — accurate (standby serves no reads; use read replicas); positive phrasing (clears C).
- distractor_1 — PASS — core 'Multi-AZ load-balances reads' misconception.
- distractor_2 — PASS — invents an auto-routing layer. **suspect-FP (auto-implicit 'automatically'); real misconception.**
- distractor_3 — PASS — misdescribes the synchronous standby as a hot read replica; plausible.

---
## C. Remaining plain-structural (5 of 8) — self-check summary

- **aws-007-mcq-1** — C/A clean (was D_match_style). "Match the DR strategy…" → scenario (payments, seconds RTO, zero RPO, cost no object) → **multi-site active/active** uniquely keyed. Distractors = the three cheaper strategies, each failing the seconds-RTO bar for a distinct reason. Distinct from sibling (cheapest-meeting-15min/1min → warm standby). 6-month: all 4 PASS, no fabrication.
- **aws-010-mcq-2** — Was C_never_correct. Correct reframed off "No —" to "The request is denied — …both sides required." Distractors: single-account model, object-ownership exemption, permissions-boundary red herring (right verdict/wrong reason). Distinct from sibling (Block Public Access + named principal). 6-month: all 4 PASS.
- **aws-027-mcq-2** — Was C_never_correct. Correct reframed to "They cannot — SCP is the ceiling." Distractors: identity-overrides-SCP, SCP-only-affects-root, Console-vs-API bypass. Distinct from sibling (customer-managed policy reuse). 6-month: all 4 PASS, no fabrication.
- **cicd-040-mcq-1** — Was D_match_style + B_scrambles. "Match the scan type…" → need-scenario (catch vulnerable deps from the manifest pre-build) → **SCA** keyed. Distractors = SAST/DAST/container-scan described accurately but wrong for *this* need (container-scan is an honest near-miss). Distinct from sibling (where DAST runs). 6-month: all 4 PASS.
- **cicd-050-mcq-2** — Was C_not_reversal + D_definition. NOT-stem removed; "which is NOT a source of flakiness" → diagnose-the-flake scenario (different test each run, only under --parallel) → **shared-resource race** keyed. Distractors: pure-function logic bug, compiler nondeterminism, OOM-kill — each ruled out by the symptoms. Distinct from sibling (why retry:3 is a bad first move). 6-month: all 4 PASS.

---
## D. Borderlines — rulings applied

1. **B1 — suspect-heuristic FPs (3).** `audit_suspect.py` flagged `cicd-001-mcq-1/d3`, `k8s-001-mcq-2/d2`, `aws-005-mcq-2/d2`, all on the `auto-implicit` pattern (the word *"automatically/automatic"*). **Ruled (Stephen 2026-06-03): all three are real junior misconceptions, not fabrications — KEPT, recorded as FPs, no reword.** Standing rule continues: any distractor with "automatically" gets the misconception-vs-fabrication check; pass → record FP, move on.
2. **B2 — length-tell.** 0/15 trip the validator's giveaway threshold; correct-is-longest 12/15 (inherent to load-bearing-correct). **Ruled: accept T3.1 as-is. From T3.2, lengthen distractors to carry their own wrong mechanism (do not shorten correct). Bank-wide correct-is-longest check at Tier-3 close.** (The B3 rebuild of aws-021 re-tripped the threshold and was cleared by lengthening distractor_1 per this method.)
3. **B3 — aws-021 uniqueness.** **Ruled: apply version B.** Constraint added to the stem (*100% Spot, no on-demand fallback, zero user-visible impact on reclaim*); single-node Postgres dropped (lowest discrimination); the stateless-web tier restored as a constraint-ruled-out distractor; payment-API + un-checkpointed-ML kept; single-select. Re-ran validate (OK) + drift (PASS). Full rebuilt item in §A above.

---
## Disposition
- `tracking.json` updated (Task 9 Step 7): T3.1 COMPLETE, 0 dropouts, suspect-FP dispositions, B1/B2/B3 rulings, before-integrity note.
- Commit scope: `batch-07-tier3-part1.json`, `batch-07-checkpoint.md`, `tracking.json`, the 3 bank files. (`draft-audit.json` / `suspect-distractors.json` stay unstaged — derived; `suspect-distractors.json` is gitignored. Scratch builders deleted.)
- Batch text 13→15 per Stephen's instruction (the locked reslice supersedes the PLAN's pre-reslice 13). Next: T3.2 (13) on borderlines-only.
