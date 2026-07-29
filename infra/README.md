# Infra (Terragrunt + Terraform)

This folder contains a minimal dev stack for AWS:
- ECR repository for application images
- VPC
- EKS cluster
- EKS managed node group with 3 workers
- Flux bootstrap (Terraform-managed deploy key + bootstrap)

Note: EKS control plane is AWS-managed, so you do not set a "control node count" directly.

## Prereqs

- AWS credentials configured locally (`aws configure` or SSO)
- `terraform` installed
- `terragrunt` installed

## Layout

- `infra/live/root.hcl` shared settings
- `infra/live/dev/ecr/terragrunt.hcl` ECR module
- `infra/live/dev/vpc/terragrunt.hcl` VPC module
- `infra/live/dev/eks/terragrunt.hcl` EKS module
- `infra/live/dev/iam/terragrunt.hcl` IAM roles (GitHub OIDC + IRSA roles)
- `infra/live/dev/flux/terragrunt.hcl` Flux bootstrap stack

## GitHub Token Requirement

The Flux bootstrap stack uses the GitHub provider to create and manage a deploy key.

- Local runs: export `GITHUB_TOKEN` before `terragrunt run --all plan/apply`
- GitHub Actions: set repository secret `GH_PAT` (used by `.github/workflows/infra.yml`)

The token needs permissions to manage deploy keys on the repository.

## Image Delivery

- ECR repository is managed by `infra/live/dev/ecr/terragrunt.hcl`
- CI builds and pushes images to ECR on `main`
- Flux image automation tracks ECR tags and updates `flux/apps/kharon/helmrelease.yaml`

## Run

From repo root:

```bash
cd infra/live/dev
terragrunt run --all init --non-interactive
terragrunt run --all plan --non-interactive
```

Apply when plan looks good (non-interactive Terragrunt + Terraform flags forwarded after `--`):

```bash
GITHUB_TOKEN="$(gh auth token)" \
AWS_PROFILE=kharon-local-dev AWS_REGION=us-east-1 \
terragrunt run --all apply --non-interactive -- -auto-approve -input=false
```

Destroy when done practicing:

```bash
terragrunt run --all destroy --non-interactive
```
