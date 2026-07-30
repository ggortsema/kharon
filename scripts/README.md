# Infra Cycle Script

This directory contains `infra-cycle.sh`, a single-entry script to safely destroy, recreate, and preflight the dev infrastructure with idempotent checks and readiness waits.

## What The Script Does

- Runs Terragrunt stacks in dependency-safe order.
- Skips steps that are already complete when possible.
- Waits for EKS, Flux, and app endpoint readiness (unless disabled).
- Auto-builds and pushes the app image tag if ECR is empty after rebuild.
- Auto-patches ALB controller `vpcId` at runtime to match the current EKS VPC.
- Cleans up lingering Route53 app alias records during destroy.
- Cleans up orphan ALBs still tagged to the EKS cluster before VPC destroy.
- Supports a status preflight mode for both humans and automation.
- Preserves a bootstrap GitHub Actions IAM role so a post-teardown push can still self-rebuild.

## Prerequisites

Install and configure:

- AWS CLI
- kubectl
- terragrunt
- Valid AWS credentials/profile for the target account
- GitHub token for Flux module apply/destroy actions
- Docker (required only when app image is missing and must be auto-built)

Export token for mutating actions:

```bash
export GITHUB_TOKEN="$(gh auth token)"
```

## Defaults

The script uses these defaults unless overridden by environment variables:

- AWS_PROFILE: kharon-local-dev
- AWS_REGION: us-east-1
- ECR_REPOSITORY: kharon-dev
- EKS_CLUSTER_NAME: kharon-dev-eks
- APP_URL: http://kharon.dev.mycroftai.org/
- WAIT_TIMEOUT: 1800
- WAIT_INTERVAL: 10
- AUTO_BUILD_AND_PUSH_IMAGE: true
- AUTO_PATCH_ALB_VPC: true
- CORP_CA_CERT_PATH: certs/zscaler-root-ca.crt

## Actions

### status

Shows an idempotency preview and runtime readiness.

- Per stack (ecr, vpc, eks, iam, flux):
- Per stack (bootstrap-iam, ecr, vpc, eks, iam, flux):
  - state presence
  - recreate decision (skip/apply)
  - destroy decision (skip/destroy)
- Runtime checks:
  - EKS cluster and nodegroups
  - Flux root Kustomization and app HelmRelease
  - application endpoint reachability

Examples:

```bash
scripts/infra-cycle.sh status
scripts/infra-cycle.sh status --json
scripts/infra-cycle.sh status --require-healthy
scripts/infra-cycle.sh status --json --require-healthy
```

### destroy

Destroys in reverse dependency order:

- flux -> iam -> eks -> vpc -> ecr

`bootstrap-iam` is intentionally not destroyed. It holds the GitHub OIDC role used by CI/Infra workflows and must remain so a single push can recreate everything else.

Examples:

```bash
scripts/infra-cycle.sh destroy
scripts/infra-cycle.sh destroy --yes
scripts/infra-cycle.sh destroy --purge-ecr --yes
scripts/infra-cycle.sh destroy --no-wait --yes
```

### recreate

Creates in dependency order:

- bootstrap-iam -> ecr -> vpc -> eks -> iam -> flux

Examples:

```bash
scripts/infra-cycle.sh recreate
scripts/infra-cycle.sh recreate --yes
scripts/infra-cycle.sh recreate --wait-timeout 3600 --yes
scripts/infra-cycle.sh recreate --no-wait --yes
```

### full-cycle

Runs destroy, then recreate.

Examples:

```bash
scripts/infra-cycle.sh full-cycle --yes
scripts/infra-cycle.sh full-cycle --purge-ecr --yes
scripts/infra-cycle.sh full-cycle --wait-timeout 3600 --yes
```

## Options

Global/script options:

- --yes: skip confirmation prompts
- --no-wait: skip readiness waits
- --wait-timeout <seconds>: max wait time per readiness gate
- --no-verify-destroy: skip post-destroy verification checks
- --no-auto-image-build: disable automatic app image build/push when missing
- --no-auto-alb-vpc-patch: disable automatic ALB controller VPC runtime patch

Status-only options:

- --json: output machine-readable JSON
- --require-healthy: fail with non-zero exit if runtime health checks fail

Destroy-only option:

- --purge-ecr: delete images in ECR repository before destroying ECR stack

## Exit Codes

- 0: success
- 1: usage error or command failure
- 2: health gate failed when using --require-healthy
- 3: post-destroy verification failed

## JSON Output Shape

`status --json` returns a single JSON object with:

- generatedAt
- stacks[]:
  - name
  - hasState
  - planExit
  - recreateAction
  - destroyAction
- runtime:
  - eks
  - flux
  - endpoint
  - health:
    - healthy
    - failures[]

Example automation gate:

```bash
if scripts/infra-cycle.sh status --json --require-healthy > /tmp/infra-status.json; then
  echo "Healthy"
else
  echo "Unhealthy"
  cat /tmp/infra-status.json
  exit 1
fi
```

## Typical Workflows

Preflight before changes:

```bash
scripts/infra-cycle.sh status
```

CI/CD health gate:

```bash
scripts/infra-cycle.sh status --json --require-healthy
```

Recover after interrupted recreate:

```bash
scripts/infra-cycle.sh recreate --yes
```

Clean rebuild from scratch:

```bash
scripts/infra-cycle.sh full-cycle --purge-ecr --yes
```

## Post-Destroy Verification

By default, `destroy` runs post-destroy checks and fails if leftovers are detected.

Checks include:

- EKS cluster no longer exists
- Managed Terragrunt stack states are empty (`flux`, `iam`, `eks`, `vpc`, `ecr`)
- No ALB resources remain tagged with the EKS cluster tag
- No Route53 records remain for the app host derived from `APP_URL`
- ECR repository no longer exists

The `bootstrap-iam` stack is excluded from destroy verification by design.

Disable only when troubleshooting:

```bash
scripts/infra-cycle.sh destroy --yes --no-verify-destroy
```

## Notes

- Idempotent behavior is best-effort based on Terragrunt state and plan exit codes.
- planExit = 0 means converged; 2 means changes detected; 1 usually indicates plan/lock/error and apply may still be attempted during recreate.
- `--require-healthy` is intentionally restricted to the `status` action so it can be used as a pure gate in automation.
- During recreate, the script checks the Flux app image tag and builds a linux/amd64 image if ECR does not contain that tag yet.
- During recreate, the script patches the ALB controller HelmRelease `spec.values.vpcId` to the live cluster VPC and waits for controller readiness.
