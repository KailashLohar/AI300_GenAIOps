#!/usr/bin/env bash
# =============================================================================
# setup_federated_auth.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}ℹ️  $*${NC}"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠️  $*${NC}"; }
error()   { echo -e "${RED}❌ $*${NC}"; exit 1; }

GITHUB_ORG=""; GITHUB_REPO=""; SUBSCRIPTION_ID=""
RESOURCE_GROUP=""; FOUNDRY_RESOURCE=""; FOUNDRY_ENDPOINT=""
MODEL_DEPLOYMENT="gpt-4.1-mini"; APP_NAME="github-actions-foundry-eval"

while [[ $# -gt 0 ]]; do
    case $1 in
        --github-org)        GITHUB_ORG="$2";       shift 2 ;;
        --github-repo)       GITHUB_REPO="$2";      shift 2 ;;
        --subscription)      SUBSCRIPTION_ID="$2";  shift 2 ;;
        --resource-group)    RESOURCE_GROUP="$2";   shift 2 ;;
        --foundry-resource)  FOUNDRY_RESOURCE="$2"; shift 2 ;;
        --foundry-endpoint)  FOUNDRY_ENDPOINT="$2"; shift 2 ;;
        --model-deployment)  MODEL_DEPLOYMENT="$2"; shift 2 ;;
        --app-name)          APP_NAME="$2";         shift 2 ;;
        *) error "Unknown argument: $1" ;;
    esac
done

for var in GITHUB_ORG GITHUB_REPO SUBSCRIPTION_ID RESOURCE_GROUP FOUNDRY_RESOURCE FOUNDRY_ENDPOINT; do
    [[ -z "${!var}" ]] && error "--$(echo $var | tr '_' '-' | tr '[:upper:]' '[:lower:]') is required"
done

info "Checking Azure CLI login..."
az account show --subscription "${SUBSCRIPTION_ID}" > /dev/null 2>&1 \
    || error "Not logged in. Run: az login"
az account set --subscription "${SUBSCRIPTION_ID}"
success "Azure CLI authenticated"

info "Step 1/5 — Creating App Registration: ${APP_NAME}"
EXISTING_APP_ID=$(az ad app list --display-name "${APP_NAME}" --query "[0].appId" -o tsv 2>/dev/null || true)
if [[ -n "${EXISTING_APP_ID}" ]]; then
    warn "App already exists (ID: ${EXISTING_APP_ID}). Reusing."
    APP_ID="${EXISTING_APP_ID}"
else
    APP_ID=$(az ad app create --display-name "${APP_NAME}" --query "appId" -o tsv)
    success "App Registration created: ${APP_ID}"
fi

info "Step 2/5 — Ensuring Service Principal exists..."
SP_OBJ_ID=$(az ad sp list --filter "appId eq '${APP_ID}'" --query "[0].id" -o tsv 2>/dev/null || true)
if [[ -z "${SP_OBJ_ID}" ]]; then
    SP_OBJ_ID=$(az ad sp create --id "${APP_ID}" --query "id" -o tsv)
    success "Service Principal created: ${SP_OBJ_ID}"
else
    warn "Service Principal already exists. Skipping."
fi

info "Step 3/5 — Configuring federated credentials..."
create_fedcred() {
    local name="$1" subject="$2"
    EXISTING=$(az ad app federated-credential list --id "${APP_ID}" \
                   --query "[?name=='${name}'].name" -o tsv 2>/dev/null || true)
    if [[ -n "${EXISTING}" ]]; then
        warn "Federated credential '${name}' already exists. Skipping."
        return
    fi
    az ad app federated-credential create --id "${APP_ID}" --parameters "{
      \"name\": \"${name}\",
      \"issuer\": \"https://token.actions.githubusercontent.com\",
      \"subject\": \"${subject}\",
      \"audiences\": [\"api://AzureADTokenExchange\"]
    }"
    success "  Created federated credential: ${name}"
}
create_fedcred "github-pr"   "repo:${GITHUB_ORG}/${GITHUB_REPO}:pull_request"
create_fedcred "github-main" "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main"

info "Step 4/5 — Granting 'Cognitive Services User' role..."
SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/${FOUNDRY_RESOURCE}"
EXISTING_ROLE=$(az role assignment list --assignee "${APP_ID}" --role "Cognitive Services User" \
    --scope "${SCOPE}" --query "[0].id" -o tsv 2>/dev/null || true)
if [[ -n "${EXISTING_ROLE}" ]]; then
    warn "Role assignment already exists. Skipping."
else
    az role assignment create --assignee "${APP_ID}" --role "Cognitive Services User" --scope "${SCOPE}" > /dev/null
    success "Role assigned"
fi

info "Step 5/5 — Fetching tenant ID..."
TENANT_ID=$(az account show --query "tenantId" -o tsv)

echo ""
echo "========================================================"
echo "  📋 GitHub Repository Variables (Settings → Variables)"
echo "========================================================"
printf "  %-30s = %s\n" "AZURE_CLIENT_ID"         "${APP_ID}"
printf "  %-30s = %s\n" "AZURE_TENANT_ID"          "${TENANT_ID}"
printf "  %-30s = %s\n" "AZURE_SUBSCRIPTION_ID"    "${SUBSCRIPTION_ID}"
printf "  %-30s = %s\n" "FOUNDRY_PROJECT_ENDPOINT" "${FOUNDRY_ENDPOINT}"
printf "  %-30s = %s\n" "MODEL_DEPLOYMENT"         "${MODEL_DEPLOYMENT}"
echo "========================================================"

OUTPUT_FILE="./scripts/github_variables.env"
cat > "${OUTPUT_FILE}" <<EOF
AZURE_CLIENT_ID=${APP_ID}
AZURE_TENANT_ID=${TENANT_ID}
AZURE_SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
FOUNDRY_PROJECT_ENDPOINT=${FOUNDRY_ENDPOINT}
MODEL_DEPLOYMENT=${MODEL_DEPLOYMENT}
EOF
success "Variables saved to: ${OUTPUT_FILE}"
warn "Next: Add variables to GitHub → Settings → Secrets and variables → Actions → Variables tab"
