#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="$ROOT_DIR/infra/live/dev"

AWS_PROFILE_DEFAULT="kharon-local-dev"
AWS_REGION_DEFAULT="us-east-1"
ECR_REPOSITORY_DEFAULT="kharon-dev"
EKS_CLUSTER_NAME_DEFAULT="kharon-dev-eks"
APP_URL_DEFAULT="http://kharon.dev.mycroftai.org/"
WAIT_TIMEOUT_DEFAULT="1800"
WAIT_INTERVAL_DEFAULT="10"

AWS_PROFILE="${AWS_PROFILE:-$AWS_PROFILE_DEFAULT}"
AWS_REGION="${AWS_REGION:-$AWS_REGION_DEFAULT}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
ECR_REPOSITORY="${ECR_REPOSITORY:-$ECR_REPOSITORY_DEFAULT}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-$EKS_CLUSTER_NAME_DEFAULT}"
APP_URL="${APP_URL:-$APP_URL_DEFAULT}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-$WAIT_TIMEOUT_DEFAULT}"
WAIT_INTERVAL="${WAIT_INTERVAL:-$WAIT_INTERVAL_DEFAULT}"

PURGE_ECR="false"
ASSUME_YES="false"
ENABLE_WAITS="true"
STATUS_JSON="false"
REQUIRE_HEALTHY="false"
HEALTHY="true"
HEALTH_FAILURES=()
VERIFY_DESTROY="true"

usage() {
  cat <<'EOF'
Usage:
  scripts/infra-cycle.sh status
  scripts/infra-cycle.sh destroy [--purge-ecr] [--yes] [--no-wait] [--no-verify-destroy] [--wait-timeout <seconds>]
  scripts/infra-cycle.sh recreate [--yes] [--no-wait] [--wait-timeout <seconds>]
  scripts/infra-cycle.sh full-cycle [--purge-ecr] [--yes] [--no-wait] [--no-verify-destroy] [--wait-timeout <seconds>]

Description:
  status     Shows what would run/skip for each stack and readiness checks.
  destroy    Destroys stack in safe reverse order: flux -> iam -> eks -> vpc -> ecr
  recreate   Recreates stack in dependency order: ecr -> vpc -> eks -> iam -> flux
  full-cycle Runs destroy then recreate

Options:
  --json       For status only: emits machine-readable JSON output.
  --require-healthy  For status only: exit non-zero if runtime is not healthy.
  --no-verify-destroy  Skip post-destroy verification checks.
  --purge-ecr  Deletes all images in ECR repository before ECR destroy.
  --yes        Skips interactive confirmation prompt.
  --no-wait    Skip post-step readiness waits.
  --wait-timeout <seconds>  Timeout for readiness waits (default: 1800).

Environment variables (optional):
  AWS_PROFILE   (default: kharon-local-dev)
  AWS_REGION    (default: us-east-1)
  GITHUB_TOKEN  required for flux module apply/destroy
  ECR_REPOSITORY (default: kharon-dev)
  EKS_CLUSTER_NAME (default: kharon-dev-eks)
  APP_URL (default: http://kharon.dev.mycroftai.org/)
  WAIT_TIMEOUT (default: 1800)
  WAIT_INTERVAL (default: 10)
EOF
}

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

confirm() {
  local prompt="$1"
  if [[ "$ASSUME_YES" == "true" ]]; then
    return 0
  fi

  read -r -p "$prompt [y/N]: " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

check_prereqs() {
  command -v terragrunt >/dev/null 2>&1 || { echo "terragrunt not found"; exit 1; }
  command -v aws >/dev/null 2>&1 || { echo "aws cli not found"; exit 1; }
  command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found"; exit 1; }

  if [[ "$ACTION" != "status" && -z "$GITHUB_TOKEN" ]]; then
    echo "GITHUB_TOKEN is required (e.g., export GITHUB_TOKEN=\"$(gh auth token)\")"
    exit 1
  fi

  export AWS_PROFILE AWS_REGION GITHUB_TOKEN
}

run_tg() {
  local dir="$1"
  local action="$2"

  log "terragrunt $action in $dir"
  (
    cd "$INFRA_DIR/$dir"
    terragrunt "$action" --non-interactive -- -auto-approve -input=false
  )
}

tg_has_state_resources() {
  local dir="$1"
  local count

  count="$(
    cd "$INFRA_DIR/$dir"
    terragrunt state list --non-interactive 2>/dev/null | wc -l | tr -d ' '
  )"

  [[ "$count" != "0" ]]
}

tg_plan_exit_code() {
  local dir="$1"
  local exit_code

  (
    cd "$INFRA_DIR/$dir"
    set +e
    terragrunt plan -detailed-exitcode --non-interactive -- -input=false >/dev/null 2>&1
    exit_code=$?
    set -e
    echo "$exit_code"
  )
}

tg_apply_if_needed() {
  local dir="$1"
  local plan_exit

  plan_exit="$(tg_plan_exit_code "$dir")"

  case "$plan_exit" in
    0)
      log "Skipping $dir apply (already converged)"
      ;;
    2)
      run_tg "$dir" apply
      ;;
    *)
      log "Plan check failed for $dir (exit=$plan_exit), running apply to recover"
      run_tg "$dir" apply
      ;;
  esac
}

tg_destroy_if_needed() {
  local dir="$1"

  if tg_has_state_resources "$dir"; then
    run_tg "$dir" destroy
  else
    log "Skipping $dir destroy (no resources in state)"
  fi
}

print_stack_status() {
  local dir="$1"
  local has_state="no"
  local plan_exit
  local recreate_action
  local destroy_action

  if tg_has_state_resources "$dir"; then
    has_state="yes"
    destroy_action="run destroy"
  else
    destroy_action="skip destroy (no state)"
  fi

  plan_exit="$(tg_plan_exit_code "$dir")"
  case "$plan_exit" in
    0)
      recreate_action="skip apply (converged)"
      ;;
    2)
      recreate_action="run apply (changes detected)"
      ;;
    *)
      recreate_action="run apply (plan check exit=$plan_exit)"
      ;;
  esac

  printf "  - %-4s state=%-3s | recreate: %-36s | destroy: %s\n" "$dir" "$has_state" "$recreate_action" "$destroy_action"
}

print_eks_runtime_status() {
  local cluster_status
  local nodegroups

  if ! cluster_status="$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" --query 'cluster.status' --output text --no-cli-pager 2>/dev/null)"; then
    echo "  - cluster: not found"
    return 0
  fi

  echo "  - cluster: $cluster_status"

  nodegroups="$(aws eks list-nodegroups --cluster-name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" --query 'nodegroups' --output text --no-cli-pager 2>/dev/null || true)"
  if [[ -z "$nodegroups" || "$nodegroups" == "None" ]]; then
    echo "  - nodegroups: none"
    return 0
  fi

  for ng in $nodegroups; do
    local ng_status
    ng_status="$(aws eks describe-nodegroup --cluster-name "$EKS_CLUSTER_NAME" --nodegroup-name "$ng" --region "$AWS_REGION" --profile "$AWS_PROFILE" --query 'nodegroup.status' --output text --no-cli-pager 2>/dev/null || echo unknown)"
    echo "  - nodegroup/$ng: $ng_status"
  done
}

print_flux_status() {
  local root_ready
  local app_ready

  if ! update_kubeconfig 2>/dev/null; then
    echo "  - kubeconfig: unavailable (cluster not ready)"
    return 0
  fi

  if ! kubectl get namespace flux-system >/dev/null 2>&1; then
    echo "  - flux-system namespace: missing"
    return 0
  fi

  root_ready="$(kubectl -n flux-system get kustomization flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  app_ready="$(kubectl -n kharon get helmrelease kharon -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"

  if [[ -z "$root_ready" ]]; then
    root_ready="Unknown"
  fi
  if [[ -z "$app_ready" ]]; then
    app_ready="Unknown"
  fi

  echo "  - flux-system kustomization Ready: $root_ready"
  echo "  - kharon helmrelease Ready: $app_ready"
}

print_endpoint_status() {
  if curl -fsS "$APP_URL" >/dev/null 2>&1; then
    echo "  - endpoint: reachable ($APP_URL)"
  else
    echo "  - endpoint: unreachable ($APP_URL)"
  fi
}

status_collect_health() {
  HEALTHY="true"
  HEALTH_FAILURES=()

  local cluster_status
  local nodegroups
  local ng
  local ng_status
  local root_ready
  local app_ready

  cluster_status="$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" --query 'cluster.status' --output text --no-cli-pager 2>/dev/null || echo not-found)"
  if [[ "$cluster_status" != "ACTIVE" ]]; then
    HEALTHY="false"
    HEALTH_FAILURES+=("EKS cluster status is $cluster_status")
  fi

  nodegroups="$(aws eks list-nodegroups --cluster-name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" --query 'nodegroups' --output text --no-cli-pager 2>/dev/null || true)"
  if [[ -n "$nodegroups" && "$nodegroups" != "None" ]]; then
    for ng in $nodegroups; do
      ng_status="$(aws eks describe-nodegroup --cluster-name "$EKS_CLUSTER_NAME" --nodegroup-name "$ng" --region "$AWS_REGION" --profile "$AWS_PROFILE" --query 'nodegroup.status' --output text --no-cli-pager 2>/dev/null || echo unknown)"
      if [[ "$ng_status" != "ACTIVE" ]]; then
        HEALTHY="false"
        HEALTH_FAILURES+=("EKS nodegroup $ng status is $ng_status")
      fi
    done
  fi

  if ! update_kubeconfig >/dev/null 2>&1; then
    HEALTHY="false"
    HEALTH_FAILURES+=("kubeconfig update failed")
  else
    if ! kubectl get namespace flux-system >/dev/null 2>&1; then
      HEALTHY="false"
      HEALTH_FAILURES+=("flux-system namespace is missing")
    else
      root_ready="$(kubectl -n flux-system get kustomization flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
      app_ready="$(kubectl -n kharon get helmrelease kharon -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"

      if [[ "$root_ready" != "True" ]]; then
        HEALTHY="false"
        HEALTH_FAILURES+=("Flux root kustomization Ready is ${root_ready:-Unknown}")
      fi
      if [[ "$app_ready" != "True" ]]; then
        HEALTHY="false"
        HEALTH_FAILURES+=("kharon HelmRelease Ready is ${app_ready:-Unknown}")
      fi
    fi
  fi

  if ! curl -fsS "$APP_URL" >/dev/null 2>&1; then
    HEALTHY="false"
    HEALTH_FAILURES+=("Application endpoint is unreachable: $APP_URL")
  fi
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

stack_status_json_object() {
  local dir="$1"
  local has_state_bool="false"
  local plan_exit
  local recreate_action
  local destroy_action

  if tg_has_state_resources "$dir"; then
    has_state_bool="true"
    destroy_action="run destroy"
  else
    destroy_action="skip destroy (no state)"
  fi

  plan_exit="$(tg_plan_exit_code "$dir")"
  case "$plan_exit" in
    0)
      recreate_action="skip apply (converged)"
      ;;
    2)
      recreate_action="run apply (changes detected)"
      ;;
    *)
      recreate_action="run apply (plan check exit=$plan_exit)"
      ;;
  esac

  printf '{"name":"%s","hasState":%s,"planExit":%s,"recreateAction":"%s","destroyAction":"%s"}' \
    "$(json_escape "$dir")" \
    "$has_state_bool" \
    "$plan_exit" \
    "$(json_escape "$recreate_action")" \
    "$(json_escape "$destroy_action")"
}

print_eks_runtime_status_json() {
  local cluster_status
  local nodegroups
  local first_nodegroup="true"

  if ! cluster_status="$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" --query 'cluster.status' --output text --no-cli-pager 2>/dev/null)"; then
    echo '{"exists":false,"status":"not found","nodegroups":[]}'
    return 0
  fi

  printf '{"exists":true,"status":"%s","nodegroups":[' "$(json_escape "$cluster_status")"
  nodegroups="$(aws eks list-nodegroups --cluster-name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" --query 'nodegroups' --output text --no-cli-pager 2>/dev/null || true)"

  if [[ -n "$nodegroups" && "$nodegroups" != "None" ]]; then
    for ng in $nodegroups; do
      local ng_status
      ng_status="$(aws eks describe-nodegroup --cluster-name "$EKS_CLUSTER_NAME" --nodegroup-name "$ng" --region "$AWS_REGION" --profile "$AWS_PROFILE" --query 'nodegroup.status' --output text --no-cli-pager 2>/dev/null || echo unknown)"
      if [[ "$first_nodegroup" == "false" ]]; then
        printf ','
      fi
      first_nodegroup="false"
      printf '{"name":"%s","status":"%s"}' "$(json_escape "$ng")" "$(json_escape "$ng_status")"
    done
  fi

  printf ']}'
}

print_flux_status_json() {
  local root_ready="Unknown"
  local app_ready="Unknown"
  local kubeconfig_state="ok"
  local namespace_state="present"

  if ! update_kubeconfig 2>/dev/null; then
    kubeconfig_state="unavailable"
    printf '{"kubeconfig":"%s","namespace":"%s","rootReady":"%s","appReady":"%s"}' \
      "$(json_escape "$kubeconfig_state")" \
      "$(json_escape "$namespace_state")" \
      "$(json_escape "$root_ready")" \
      "$(json_escape "$app_ready")"
    return 0
  fi

  if ! kubectl get namespace flux-system >/dev/null 2>&1; then
    namespace_state="missing"
    printf '{"kubeconfig":"%s","namespace":"%s","rootReady":"%s","appReady":"%s"}' \
      "$(json_escape "$kubeconfig_state")" \
      "$(json_escape "$namespace_state")" \
      "$(json_escape "$root_ready")" \
      "$(json_escape "$app_ready")"
    return 0
  fi

  root_ready="$(kubectl -n flux-system get kustomization flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  app_ready="$(kubectl -n kharon get helmrelease kharon -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"

  if [[ -z "$root_ready" ]]; then
    root_ready="Unknown"
  fi
  if [[ -z "$app_ready" ]]; then
    app_ready="Unknown"
  fi

  printf '{"kubeconfig":"%s","namespace":"%s","rootReady":"%s","appReady":"%s"}' \
    "$(json_escape "$kubeconfig_state")" \
    "$(json_escape "$namespace_state")" \
    "$(json_escape "$root_ready")" \
    "$(json_escape "$app_ready")"
}

print_endpoint_status_json() {
  local reachable="false"
  if curl -fsS "$APP_URL" >/dev/null 2>&1; then
    reachable="true"
  fi

  printf '{"url":"%s","reachable":%s}' "$(json_escape "$APP_URL")" "$reachable"
}

status_summary() {
  log "Stack status (idempotency preview)"
  print_stack_status ecr
  print_stack_status vpc
  print_stack_status eks
  print_stack_status iam
  print_stack_status flux

  log "Runtime readiness"
  echo "EKS:"
  print_eks_runtime_status
  echo "Flux/Kubernetes:"
  print_flux_status
  echo "App endpoint:"
  print_endpoint_status

  if [[ "$REQUIRE_HEALTHY" == "true" ]]; then
    status_collect_health
    if [[ "$HEALTHY" == "true" ]]; then
      log "Health gate passed"
    else
      log "Health gate failed"
      if (( ${#HEALTH_FAILURES[@]} > 0 )); then
        for failure in "${HEALTH_FAILURES[@]}"; do
          echo "  - $failure"
        done
      fi
      exit 2
    fi
  fi
}

status_summary_json() {
  local stacks=(ecr vpc eks iam flux)
  local first_stack="true"
  local first_failure="true"

  status_collect_health

  printf '{'
  printf '"generatedAt":"%s",' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '"stacks":['

  for stack in "${stacks[@]}"; do
    if [[ "$first_stack" == "false" ]]; then
      printf ','
    fi
    first_stack="false"
    stack_status_json_object "$stack"
  done

  printf '],'
  printf '"runtime":{'
  printf '"eks":'
  print_eks_runtime_status_json
  printf ','
  printf '"flux":'
  print_flux_status_json
  printf ','
  printf '"endpoint":'
  print_endpoint_status_json
  printf ','
  printf '"health":{'
  printf '"healthy":%s,' "$([[ "$HEALTHY" == "true" ]] && echo true || echo false)"
  printf '"failures":['
  if (( ${#HEALTH_FAILURES[@]} > 0 )); then
    for failure in "${HEALTH_FAILURES[@]}"; do
      if [[ "$first_failure" == "false" ]]; then
        printf ','
      fi
      first_failure="false"
      printf '"%s"' "$(json_escape "$failure")"
    done
  fi
  printf ']}'
  printf '}'
  printf '}\n'

  if [[ "$REQUIRE_HEALTHY" == "true" && "$HEALTHY" != "true" ]]; then
    exit 2
  fi
}

wait_until() {
  local description="$1"
  shift

  local start_ts now elapsed
  start_ts="$(date +%s)"

  log "Waiting for: $description"
  until "$@"; do
    now="$(date +%s)"
    elapsed="$((now - start_ts))"
    if (( elapsed >= WAIT_TIMEOUT )); then
      echo "Timed out after ${WAIT_TIMEOUT}s while waiting for: $description"
      return 1
    fi
    sleep "$WAIT_INTERVAL"
  done

  log "Ready: $description"
}

update_kubeconfig() {
  aws eks update-kubeconfig \
    --name "$EKS_CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" >/dev/null
}

wait_for_eks_ready() {
  [[ "$ENABLE_WAITS" == "true" ]] || return 0

  wait_until "EKS cluster $EKS_CLUSTER_NAME is ACTIVE" \
    aws eks wait cluster-active --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE"

  local nodegroups
  nodegroups="$(aws eks list-nodegroups --cluster-name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" --query 'nodegroups' --output text --no-cli-pager || true)"
  if [[ -n "$nodegroups" ]]; then
    for ng in $nodegroups; do
      wait_until "EKS nodegroup $ng is ACTIVE" \
        aws eks wait nodegroup-active --cluster-name "$EKS_CLUSTER_NAME" --nodegroup-name "$ng" --region "$AWS_REGION" --profile "$AWS_PROFILE"
    done
  fi
}

wait_for_eks_deleted() {
  [[ "$ENABLE_WAITS" == "true" ]] || return 0

  if aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" --no-cli-pager >/dev/null 2>&1; then
    wait_until "EKS cluster $EKS_CLUSTER_NAME is deleted" \
      aws eks wait cluster-deleted --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE"
  fi
}

wait_for_flux_ready() {
  [[ "$ENABLE_WAITS" == "true" ]] || return 0

  update_kubeconfig

  wait_until "flux-system namespace exists" \
    kubectl get namespace flux-system >/dev/null 2>&1

  wait_until "Flux root kustomization is Ready" \
    bash -c '[[ "$(kubectl -n flux-system get kustomization flux-system -o jsonpath="{.status.conditions[?(@.type==\"Ready\")].status}")" == "True" ]]'

  wait_until "App HelmRelease is Ready" \
    bash -c '[[ "$(kubectl -n kharon get helmrelease kharon -o jsonpath="{.status.conditions[?(@.type==\"Ready\")].status}")" == "True" ]]'
}

wait_for_app_endpoint() {
  [[ "$ENABLE_WAITS" == "true" ]] || return 0

  wait_until "Application endpoint responds" \
    curl -fsS "$APP_URL" >/dev/null
}

purge_ecr_images() {
  log "Purging ECR images from repository $ECR_REPOSITORY"

  if ! aws ecr describe-repositories \
    --repository-names "$ECR_REPOSITORY" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --no-cli-pager >/dev/null 2>&1; then
    log "ECR repository does not exist, nothing to purge"
    return 0
  fi

  local image_ids_json
  local deleted_any="false"

  while true; do
    image_ids_json="$(aws ecr list-images \
      --repository-name "$ECR_REPOSITORY" \
      --region "$AWS_REGION" \
      --profile "$AWS_PROFILE" \
      --max-items 100 \
      --query 'imageIds[*]' \
      --output json \
      --no-cli-pager 2>/dev/null || echo '[]')"

    if [[ "$image_ids_json" == "[]" ]]; then
      break
    fi

    aws ecr batch-delete-image \
      --repository-name "$ECR_REPOSITORY" \
      --region "$AWS_REGION" \
      --profile "$AWS_PROFILE" \
      --image-ids "$image_ids_json" \
      --no-cli-pager >/dev/null

    deleted_any="true"
  done

  if [[ "$deleted_any" == "false" ]]; then
    log "No ECR images to delete"
    return 0
  fi

  log "ECR images deleted"
}

app_host_from_url() {
  local host
  host="${APP_URL#http://}"
  host="${host#https://}"
  host="${host%%/*}"
  host="${host%%:*}"
  printf '%s' "$host"
}

verify_destroy_postconditions() {
  local verify_failures=()
  local managed_stacks=(flux iam eks vpc ecr)
  local stack
  local app_host
  local record_fqdn

  log "Verifying destroy post-conditions"

  if aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" --no-cli-pager >/dev/null 2>&1; then
    verify_failures+=("EKS cluster still exists: $EKS_CLUSTER_NAME")
  fi

  for stack in "${managed_stacks[@]}"; do
    if tg_has_state_resources "$stack"; then
      verify_failures+=("Terragrunt state still has resources in stack: $stack")
    fi
  done

  local alb_count
  alb_count="$(aws resourcegroupstaggingapi get-resources \
    --tag-filters "Key=kubernetes.io/cluster/$EKS_CLUSTER_NAME" \
    --resource-type-filters elasticloadbalancing:loadbalancer \
    --query 'length(ResourceTagMappingList)' \
    --output text \
    --no-cli-pager 2>/dev/null || echo 0)"
  if [[ "$alb_count" != "0" && "$alb_count" != "None" ]]; then
    verify_failures+=("Found $alb_count ALB resource(s) still tagged to cluster $EKS_CLUSTER_NAME")
  fi

  app_host="$(app_host_from_url)"
  if [[ -n "$app_host" ]]; then
    local hosted_zones
    local zone_id
    local zone_count
    local total_records=0

    record_fqdn="${app_host%.}."
    hosted_zones="$(aws route53 list-hosted-zones --query 'HostedZones[].Id' --output text --no-cli-pager 2>/dev/null || true)"

    if [[ -n "$hosted_zones" && "$hosted_zones" != "None" ]]; then
      for zone_id in $hosted_zones; do
        zone_count="$(aws route53 list-resource-record-sets \
          --hosted-zone-id "$zone_id" \
          --query "length(ResourceRecordSets[?Name == '$record_fqdn'])" \
          --output text \
          --no-cli-pager 2>/dev/null || echo 0)"

        if [[ "$zone_count" != "0" && "$zone_count" != "None" ]]; then
          total_records=$((total_records + zone_count))
        fi
      done
    fi

    if (( total_records > 0 )); then
      verify_failures+=("Found $total_records Route53 record set(s) still present for $record_fqdn")
    fi
  fi

  if aws ecr describe-repositories --repository-names "$ECR_REPOSITORY" --region "$AWS_REGION" --profile "$AWS_PROFILE" --no-cli-pager >/dev/null 2>&1; then
    local image_count
    image_count="$(aws ecr list-images \
      --repository-name "$ECR_REPOSITORY" \
      --region "$AWS_REGION" \
      --profile "$AWS_PROFILE" \
      --query 'length(imageIds)' \
      --output text \
      --no-cli-pager 2>/dev/null || echo unknown)"
    verify_failures+=("ECR repository still exists: $ECR_REPOSITORY (imageCount=$image_count)")
  fi

  if (( ${#verify_failures[@]} > 0 )); then
    log "Post-destroy verification failed"
    for failure in "${verify_failures[@]}"; do
      echo "  - $failure"
    done
    exit 3
  fi

  log "Post-destroy verification passed"
}

destroy_stack() {
  if ! confirm "About to DESTROY infrastructure in account profile '$AWS_PROFILE' region '$AWS_REGION'. Continue?"; then
    echo "Aborted"
    exit 1
  fi

  tg_destroy_if_needed flux
  tg_destroy_if_needed iam
  tg_destroy_if_needed eks
  wait_for_eks_deleted
  tg_destroy_if_needed vpc

  if [[ "$PURGE_ECR" == "true" ]]; then
    purge_ecr_images
  fi

  tg_destroy_if_needed ecr

  if [[ "$VERIFY_DESTROY" == "true" ]]; then
    verify_destroy_postconditions
  fi

  log "Destroy complete"
}

recreate_stack() {
  if ! confirm "About to RECREATE infrastructure in account profile '$AWS_PROFILE' region '$AWS_REGION'. Continue?"; then
    echo "Aborted"
    exit 1
  fi

  tg_apply_if_needed ecr
  tg_apply_if_needed vpc
  tg_apply_if_needed eks
  wait_for_eks_ready
  tg_apply_if_needed iam
  tg_apply_if_needed flux
  wait_for_flux_ready
  wait_for_app_endpoint

  log "Recreate complete"
}

parse_args() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
  fi

  ACTION="$1"
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --purge-ecr)
        PURGE_ECR="true"
        shift
        ;;
      --json)
        STATUS_JSON="true"
        shift
        ;;
      --require-healthy)
        REQUIRE_HEALTHY="true"
        shift
        ;;
      --no-verify-destroy)
        VERIFY_DESTROY="false"
        shift
        ;;
      --yes)
        ASSUME_YES="true"
        shift
        ;;
      --no-wait)
        ENABLE_WAITS="false"
        shift
        ;;
      --wait-timeout)
        WAIT_TIMEOUT="${2:-}"
        if [[ -z "$WAIT_TIMEOUT" ]]; then
          echo "--wait-timeout requires a value in seconds"
          exit 1
        fi
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done

  case "$ACTION" in
    status|destroy|recreate|full-cycle) ;;
    *)
      echo "Unknown action: $ACTION"
      usage
      exit 1
      ;;
  esac

  if [[ "$STATUS_JSON" == "true" && "$ACTION" != "status" ]]; then
    echo "--json is only supported with the status action"
    exit 1
  fi

  if [[ "$REQUIRE_HEALTHY" == "true" && "$ACTION" != "status" ]]; then
    echo "--require-healthy is only supported with the status action"
    exit 1
  fi
}

main() {
  parse_args "$@"
  check_prereqs

  case "$ACTION" in
    status)
      if [[ "$STATUS_JSON" == "true" ]]; then
        status_summary_json
      else
        status_summary
      fi
      ;;
    destroy)
      destroy_stack
      ;;
    recreate)
      recreate_stack
      ;;
    full-cycle)
      destroy_stack
      recreate_stack
      ;;
  esac
}

main "$@"
