#!/usr/bin/env bash
set -uo pipefail

# ── Error handler ───────────────────────────────────────────────────────────
trap 'error "Command failed at line $LINENO: $BASH_COMMAND"; exit 1' ERR

# ============================================================================
# setup.sh - Project template scaffold & dev Docker management
# ============================================================================
# Usage:
#   ./setup.sh --init client       Scaffold Next.js client (first-time setup)
#   ./setup.sh --dev docker up       Start dev Docker environment
#   ./setup.sh --dev docker down     Stop dev Docker environment (keeps volumes)
#   ./setup.sh --dev docker cleanup  Remove containers and volumes
#   ./setup.sh --generate-admin-key  Generate Convex admin key & save to file
#   ./setup.sh --help                Show this help message
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMIN_KEY_FILE="${SCRIPT_DIR}/.convex_admin_key"
CLIENT_DIR="${SCRIPT_DIR}/client"
ENV_LOCAL="${CLIENT_DIR}/.env.local"

# ── Colors & helpers ────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERR]${NC}   $*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}--- $* ---${NC}\n"; }

# ── Prerequisite checks ────────────────────────────────────────────────────
check_prerequisites() {
  local missing=0
  for cmd in node npm docker; do
    if ! command -v "$cmd" &>/dev/null; then
      error "$cmd is not installed."
      missing=1
    fi
  done
  if ! docker compose version &>/dev/null 2>&1; then
    error "docker compose plugin is not available."
    missing=1
  fi
  [[ $missing -eq 1 ]] && exit 1
}

# ── Scaffold command ────────────────────────────────────────────────────────
cmd_scaffold() {
  header "Project Template Setup"
  check_prerequisites

  if [[ -f "${CLIENT_DIR}/package.json" ]]; then
    warn "client/ already has a package.json - skipping Next.js scaffolding"
  else
    info "Creating Next.js app in client/ ..."
    npx -y create-next-app@latest "${CLIENT_DIR}" \
      --ts --eslint --tailwind --src-dir --app \
      --import-alias "@/*" --use-npm --no-git --yes
    success "Next.js app created"
  fi

  # Copy template files into client/
  info "Copying template files into client/ ..."
  cp "${SCRIPT_DIR}/docker/client.env.local" "${CLIENT_DIR}/.env.local"
  cp "${SCRIPT_DIR}/docker/client.Dockerfile" "${CLIENT_DIR}/Dockerfile.dev"
  success "Template files copied"

  info "Installing convex@latest in client/ ..."
  (cd "${CLIENT_DIR}" && npm install convex@latest)
  success "Convex SDK installed"

  if [[ ! -d "${CLIENT_DIR}/convex" ]]; then
    info "Initializing Convex project ..."
    (cd "${CLIENT_DIR}" && npx -y convex dev --once --configure=new)
    success "Convex project initialized"
  fi

  header "Setup Complete"
  echo -e "  ${BOLD}1.${NC} Start dev:        ${CYAN}./setup.sh --dev docker up${NC}"
  echo -e "  ${BOLD}2.${NC} Generate key:      ${CYAN}./setup.sh --generate-admin-key${NC}"
  echo -e "  ${BOLD}3.${NC} Dashboard:         ${CYAN}http://localhost:6791${NC}"
  echo -e "  ${BOLD}4.${NC} Client:            ${CYAN}http://localhost:3000${NC}"
  echo -e "  ${BOLD}5.${NC} Stop dev:          ${CYAN}./setup.sh --dev docker down${NC}"
}

# -- Reset client -------------------------------------------------------------
cmd_reset_client() {
  header "Reset Client"
  if [[ ! -d "${CLIENT_DIR}" ]]; then
    warn "client/ does not exist. Nothing to reset."
    return
  fi
  warn "This will ${BOLD}permanently delete${NC}${YELLOW} everything in client/ and re-scaffold from scratch.${NC}"
  read -rp "Are you sure? [y/N] " confirm
  if [[ "${confirm,,}" != "y" ]]; then
    info "Cancelled."
    return
  fi
  info "Removing client/ ..."
  rm -rf "${CLIENT_DIR}"
  success "client/ removed"
  cmd_scaffold
}

# -- Remove client ------------------------------------------------------------
cmd_remove_client() {
  header "Remove Client"
  if [[ ! -d "${CLIENT_DIR}" ]]; then
    warn "client/ does not exist. Nothing to remove."
    return
  fi
  warn "This will ${BOLD}permanently delete${NC}${YELLOW} everything in client/.${NC}"
  read -rp "Are you sure? [y/N] " confirm
  if [[ "${confirm,,}" != "y" ]]; then
    info "Cancelled."
    return
  fi
  info "Removing client/ ..."
  rm -rf "${CLIENT_DIR}"
  success "client/ removed"
}

# ── Docker dev commands ─────────────────────────────────────────────────────
cmd_dev_docker_up() {
  header "Starting Dev Docker Environment"
  check_prerequisites

  if [[ ! -f "${CLIENT_DIR}/package.json" ]]; then
    error "client/package.json not found. Run ${CYAN}./setup.sh${NC} first to scaffold the project."
    exit 1
  fi

  info "Building and starting core containers ..."
  if ! docker compose -f "${SCRIPT_DIR}/docker/docker-compose.yml" up -d --build backend dashboard client 2>&1; then
    error "Docker Compose failed. Check the output above for details."
    exit 1
  fi
  success "Core containers started"
  echo -e ""
  info "Backend    - http://localhost:3210"
  info "Actions    - http://localhost:3211"
  info "Dashboard  - http://localhost:6791"
  info "Client     - http://localhost:3000"
  echo -e ""

  # Wait for backend to be healthy, then auto-generate admin key
  info "Waiting for backend to be ready ..."
  until curl -sf http://localhost:3210/version > /dev/null 2>&1; do
    sleep 1
  done
  success "Backend is up"

  cmd_generate_admin_key

  # Start convex-push with the admin key
  local admin_key
  admin_key=$(cat "${ADMIN_KEY_FILE}")
  info "Deploying Convex functions ..."
  if ! CONVEX_ADMIN_KEY="${admin_key}" docker compose -f "${SCRIPT_DIR}/docker/docker-compose.yml" up -d --build convex-push 2>&1; then
    error "Failed to start convex-push container."
    exit 1
  fi
  success "Convex functions deployed"
}

cmd_dev_docker_down() {
  header "Stopping Dev Docker Environment"
  if ! docker compose -f "${SCRIPT_DIR}/docker/docker-compose.yml" stop 2>&1; then
    error "Docker Compose failed to stop. Check the output above."
    exit 1
  fi
  success "All containers stopped (volumes preserved)"
}

cmd_dev_docker_cleanup() {
  header "Cleaning Up Dev Docker Environment"
  warn "This will remove all containers AND volumes (including Convex data)."
  read -rp "Are you sure? [y/N] " confirm
  if [[ "${confirm,,}" != "y" ]]; then
    info "Cancelled."
    return
  fi
  if ! docker compose -f "${SCRIPT_DIR}/docker/docker-compose.yml" down -v 2>&1; then
    error "Docker Compose cleanup failed. Check the output above."
    exit 1
  fi
  success "All containers and volumes removed"
}

# ── Generate admin key ──────────────────────────────────────────────────────
cmd_generate_admin_key() {
  header "Generating Convex Admin Key"

  if ! docker compose -f "${SCRIPT_DIR}/docker/docker-compose.yml" ps --status running 2>/dev/null | grep -q "backend"; then
    error "Backend container is not running. Start it with: ./setup.sh --dev docker up"
    exit 1
  fi

  info "Generating admin key from backend container ..."
  local admin_key
  admin_key=$(docker compose -f "${SCRIPT_DIR}/docker/docker-compose.yml" exec -T backend ./generate_admin_key.sh 2>/dev/null | tr -d '[:space:]')

  if [[ -z "$admin_key" ]]; then
    error "Failed to generate admin key. Is the backend fully started?"
    exit 1
  fi

  echo "$admin_key" > "${ADMIN_KEY_FILE}"
  chmod 600 "${ADMIN_KEY_FILE}"
  success "Admin key saved to .convex_admin_key"

  if [[ -f "${ENV_LOCAL}" ]]; then
    if grep -q "CONVEX_SELF_HOSTED_ADMIN_KEY" "${ENV_LOCAL}"; then
      sed -i "s|CONVEX_SELF_HOSTED_ADMIN_KEY=.*|CONVEX_SELF_HOSTED_ADMIN_KEY='${admin_key}'|" "${ENV_LOCAL}"
    else
      echo "CONVEX_SELF_HOSTED_ADMIN_KEY='${admin_key}'" >> "${ENV_LOCAL}"
    fi
    success "Updated client/.env.local with admin key"
  fi

  echo -e ""
  info "Admin Key: ${YELLOW}${admin_key}${NC}"
  info "Use it to log into the dashboard at ${CYAN}http://localhost:6791${NC}"
}

# ── Help ────────────────────────────────────────────────────────────────────
cmd_help() {
  echo -e "${BOLD}${CYAN}setup.sh${NC} - Project template scaffold & dev management"
  echo -e ""
  echo -e "  ./setup.sh --init client          Scaffold Next.js client"
  echo -e "  ./setup.sh --reset client         Remove & re-scaffold client"
  echo -e "  ./setup.sh --remove client        Remove client (no re-scaffold)"
  echo -e "  ./setup.sh --dev docker up         Start dev Docker environment"
  echo -e "  ./setup.sh --dev docker down       Stop containers (keeps volumes)"
  echo -e "  ./setup.sh --dev docker cleanup    Remove containers and volumes"
  echo -e "  ./setup.sh --generate-admin-key    Generate & save Convex admin key"
  echo -e "  ./setup.sh --help                  Show this help"
}

# ── Argument parsing ────────────────────────────────────────────────────────
main() {
  case "${1:-}" in
    ""|--help|-h)         cmd_help ;;
    --generate-admin-key) cmd_generate_admin_key ;;
    --init)
      shift
      [[ "${1:-}" == "client" ]] || { error "Usage: ./setup.sh --init client"; exit 1; }
      cmd_scaffold
      ;;
    --reset)
      shift
      [[ "${1:-}" == "client" ]] || { error "Usage: ./setup.sh --reset client"; exit 1; }
      cmd_reset_client
      ;;
    --remove)
      shift
      [[ "${1:-}" == "client" ]] || { error "Usage: ./setup.sh --remove client"; exit 1; }
      cmd_remove_client
      ;;
    --dev)
      shift
      [[ "${1:-}" == "docker" ]] || { error "Usage: ./setup.sh --dev docker [up|down|cleanup]"; exit 1; }
      shift
      case "${1:-}" in
        up)      cmd_dev_docker_up ;;
        down)    cmd_dev_docker_down ;;
        cleanup) cmd_dev_docker_cleanup ;;
        *)       error "Unknown action: ${1:-} (expected up|down|cleanup)"; exit 1 ;;
      esac
      ;;
    *) error "Unknown command: $1"; cmd_help; exit 1 ;;
  esac
}

main "$@"
