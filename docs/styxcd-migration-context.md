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

-----------------

You are 100% right, and your conclusion is exactly the right one.

What took 2 days was not “hello world app complexity,” it was integration complexity across tools and control planes. The app was trivial; the orchestration surface was the hard part.

Reusable orchestrator blocks solve this by turning fragile glue into stable primitives:

Trigger block
“on push/main with path filters” once, reused everywhere.
Infra block
“terraform/terragrunt apply with lock/backoff/retry.”
GitOps block
“wait for Flux kustomization + helmrelease ready.”
Artifact block
“build/tag/publish image and emit metadata.”
Verify block
“endpoint/health checks with timeout policy.”
Rollback block
standardized compensation behavior.
Observability block
consistent stage telemetry/events in one schema.
Then each workflow becomes composition, not reinvention.

So instead of:

bespoke GH Actions YAML
ad hoc shell scripts
one-off waits/retries/error handling
you get:

policy-driven, versioned stage library
deterministic execution plan
uniform retries/idempotency
one UI and one event stream
Your instinct is right: this is exactly where StyxCD provides leverage.

When you’re ready, we can start defining the first reusable block set from what we just learned in this repo, so the pain you paid here gets converted into permanent building blocks.
