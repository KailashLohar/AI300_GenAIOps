#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}ℹ️  $*${NC}"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠️  $*${NC}"; }
error()   { echo -e "${RED}❌ $*${NC}"; exit 1; }

APP_NAME="github-actions-foundry-eval"
SUBSCRIPTION_ID=""; RESOURCE_GROUP=""; FOUNDRY_RESOURCE=""
ALL_PASS=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --app-name)         APP_NAME="$2";         shift 2 ;;
        --subscription)     SUBSCRIPTION_ID="$2";  shift 2 ;;
        --resource-group)   RESOURCE_GROUP="$2";   shift 2 ;;
        --foundry-resource) FOUNDRY_RESOURCE="$2"; shift 2 ;;
        *) error "Unknown argument: $1" ;;
    esac
done

info "Checking App Registration..."
APP_ID=$(az ad app list --display-name "${APP_NAME}" --query "[0].appId" -o tsv 2>/dev/null || true)
[[ -z "${APP_ID}" ]] && error "App '${APP_NAME}' not found. Run setup_federated_auth.sh first."
success "App Registration found: ${APP_ID}"

info "Checking Service Principal..."
SP_ID=$(az ad sp list --filter "appId eq '${APP_ID}'" --query "[0].id" -o tsv 2>/dev/null || true)
[[ -z "${SP_ID}" ]] && { warn "No Service Principal found"; ALL_PASS=false; } || success "Service Principal found: ${SP_ID}"

info "Checking Federated Credentials..."
FED_CREDS=$(az ad app federated-credential list --id "${APP_ID}" --query "[].name" -o tsv 2>/dev/null || true)
for cred in "github-pr" "github-main"; do
    echo "${FED_CREDS}" | grep -q "${cred}" \
        && success "  Federated credential found: ${cred}" \
        || { warn "  Missing: ${cred}"; ALL_PASS=false; }
done

info "Checking Role Assignment..."
SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/${FOUNDRY_RESOURCE}"
ROLE=$(az role assignment list --assignee "${APP_ID}" --role "Cognitive Services User" \
    --scope "${SCOPE}" --query "[0].roleDefinitionName" -o tsv 2>/dev/null || true)
[[ -n "${ROLE}" ]] && success "Role 'Cognitive Services User' assigned" || { warn "Role not found"; ALL_PASS=false; }

echo ""
${ALL_PASS} && success "All checks passed! GitHub Actions workflow is ready." \
             || warn "Some checks failed. Re-run setup_federated_auth.sh."
