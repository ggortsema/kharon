# StyxCD Migration Context (Working Notes)

## Purpose

Capture current architecture intent and migration direction so work can resume later with ADRs and source-code review inputs.

## Current Direction

- Move away from bash-script-centric orchestration as the long-term model.
- Move from Jenkins-based execution toward Kubernetes-native execution agents.
- Keep Flux, Helm, and Terraform as specialist tools, but place them behind StyxCD adapters.
- Prefer reducing direct dependency on GitHub Actions.
- If GitHub Actions is required, use a thin trigger/integration layer only.

## Existing StyxCD Concepts To Preserve

- YAML-defined workflows mapped into an execution plan (DAG/planned stage graph).
- Separate execution agent model from workflow planning/control plane.
- Jenkins used as execution agent only (not as workflow engine).
- Event/status callback mechanism from stage execution back to orchestrator.
- End-to-end observability across stages and workflows (Splunk/Datadog/Grafana).
- Next.js UI for workflow visualization and operations.
- PostgreSQL for state, history, and audit lineage.
- RabbitMQ for parallel stage dispatch and coordination.

## Historical Routing Module Pattern (Important)

StyxCD included a routing module that:

- Accepted external trigger sources such as:
  - Bitbucket webhooks
  - GitHub webhooks
  - XLR triggers
- Used YAML routing configuration to define:
  - Event types to react to
  - Include/exclude path filters
  - Workflow mapping to trigger

This pattern should be retained as a first-class Router + Trigger Policy Engine in the rewrite.

## Proposed Target Architecture (Python + Kubernetes)

### 1) Control Plane (StyxCD API/Planner)

- Ingest and validate workflow/routing YAML.
- Build deterministic execution plans.
- Enforce orchestration policy (retry, pause/resume, approvals, cancel).
- Persist run state and audit trail to PostgreSQL.

### 2) Event Router and Trigger Policy Engine

- Normalize incoming trigger payloads from GitHub/Bitbucket/XLR/manual API.
- Match route rules by event, repo, branch/tag, path filters, actor, etc.
- Produce workflow trigger requests with idempotency keys.
- Record match/non-match decisions for auditing.

### 3) Execution Plane (Kubernetes Native)

- Prefer Kubernetes Jobs/worker pods as execution agents.
- Dispatch runnable stages through RabbitMQ (or equivalent queue abstraction).
- Workers report stage lifecycle events back to control plane.

### 4) Adapter Layer

- Terraform adapter
- Helm adapter
- Flux adapter
- Optional thin GitHub Actions adapter

Goal: keep tooling implementation-specific concerns behind stable StyxCD stage contracts.

### 5) Observability Contract

- Standard workflow/stage event envelope.
- Emission hooks for lifecycle events and status changes.
- Integrations for logs/metrics/traces into Splunk/Datadog/Grafana stacks.

## Routing and Trigger Semantics To Define Explicitly

- Rule evaluation order and precedence.
- Include/exclude path conflict behavior (recommended: exclude wins).
- Rule priority and stop-on-match vs continue-on-match behavior.
- Idempotency key strategy to avoid duplicate runs from webhook retries.
- Replay semantics and dedupe windows.

## Migration Strategy (Incremental)

1. Keep existing execution path available while introducing Kubernetes executor adapter.
2. Route selected workflows to Kubernetes workers first.
3. Validate parity for retries, callbacks, and telemetry.
4. Migrate additional workflows in waves.
5. Decommission Jenkins executor path when confidence is high.
6. Keep GitHub Actions only as a thin trigger bridge where needed.

## Open Items For Next Session

- ADR review and alignment against this target model.
- Existing code walkthrough to identify:
  - Reusable components
  - Required translation to Python
  - Contract boundaries and anti-corruption layers
- Draft v1 schema/contracts:
  - Workflow schema
  - Routing schema
  - Stage execution contract
  - Event envelope
- Decide whether workflow-run state should be represented as DB-only, CRD-backed, or hybrid.

## Inputs To Bring Next Time

- ADR documents (architecture decisions and constraints).
- Existing StyxCD code pointers (routing, planner, execution agent, telemetry).
- Any current pain points or non-negotiable requirements for migration.

## Suggested Restart Prompt

When resuming, use a prompt like:

"Use docs/styxcd-migration-context.md as baseline. I am now providing ADRs and code references. Please map ADR decisions to a phased migration plan and propose the v1 Python architecture with contracts."

## Stakeholder Justification For StyxCD

### Executive Summary

The current toolchain works, but operational reliability depends on manual coordination across multiple systems. StyxCD addresses this by acting as an orchestration control plane over existing tools (Terraform, Flux, Helm, CI triggers), converting fragile glue logic into reusable, policy-driven workflow blocks.

### Evidence From The Kharon Validation

The Kharon environment provided a realistic proof case:

- A simple application required significant integration effort across IAM/OIDC, CI, GitOps, DNS, ECR, and Terraform state management.
- Multiple failures were not application bugs; they were cross-tool orchestration failures (state locks, race conditions, dependency cleanup, stale infrastructure artifacts).
- Successful teardown/rebuild required sequencing, retries, readiness gates, cancellation of conflicting runs, and post-condition verification.

Conclusion: complexity is dominated by orchestration, not application logic.

### Why Existing Tools Alone Are Insufficient

Existing tools are strong within their own domain, but each has limited scope:

- Terraform/Terragrunt: desired-state infrastructure for one stack/state at a time.
- Flux/Helm: cluster and app reconciliation, not global workflow planning.
- GitHub Actions/Jenkins: execution runners, not durable cross-system workflow control planes.

Operational gaps that remain without StyxCD:

- Cross-tool sequencing and dependency orchestration.
- Idempotent recovery from partial failures.
- Unified retry/backoff/timeout policy.
- Global run state and lineage across systems.
- Consistent pre/post-condition validation.

### Value Proposition

StyxCD provides reusable orchestration blocks and policy controls:

- Trigger block: event routing (GitHub/Bitbucket/XLR/manual) with include/exclude path semantics.
- Infra block: Terraform/Terragrunt with lock handling and retry policy.
- GitOps block: Flux/Helm readiness and reconciliation checks.
- Artifact block: build/publish metadata handoff.
- Verify block: endpoint and runtime health gates.
- Rollback/compensation block: standardized remediation paths.
- Observability block: common event schema and telemetry forwarding.

Result:

- Less bespoke YAML/scripting.
- Deterministic execution plans.
- Faster onboarding of new services.
- Better MTTR through consistent failure handling.
- Stronger auditability and operational confidence.

### Strategic Benefits

- Reduces dependency on any single CI vendor as workflow engine.
- Allows Kubernetes-native execution agents and optional thin CI bridges.
- Preserves investment in existing best-of-breed tools via adapters.
- Creates a platform capability reusable across products/teams.

### Cost of Not Building StyxCD

- Continued repeated effort per service for similar orchestration glue.
- Higher incident probability from race conditions and partial-state failures.
- Slower delivery due to environment-specific automation drift.
- Ongoing operational burden concentrated in senior engineers.

### Recommended Approval Scope

Phase 1 (MVP):

- Python control plane, workflow planner, event router.
- Kubernetes-native execution agent.
- Terraform/Flux/Helm adapters.
- PostgreSQL state model and RabbitMQ dispatch.
- Minimum UI run visibility and stage-level status.

Phase 2 (Scale):

- Expanded policy engine (approvals, advanced retries, compensation).
- Rich observability integrations and run analytics.
- Additional adapters and standardized workflow catalog.

### Suggested Stakeholder Message

"StyxCD is not replacing Terraform, Flux, or Helm. It is the orchestration layer that makes those tools reliable together at scale, reduces repeated engineering effort, and improves deployment safety with deterministic, observable workflows."
