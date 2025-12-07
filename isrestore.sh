#!/bin/bash
#
# DirectAdmin auto restore script
# - Uses reseller derived from hostname (e.g. lh615 -> islh615)
# - Does NOT move/rename backup file
# - Detects username from backup filename (user.<creator>.<username>.*)
# - If user already exists: asks for confirmation to continue (overwrite)
# - Fixes permissions for /home/admin/<username> for the chosen owner
# - Shows only new DirectAdmin log lines for this run
# - Auto-unsuspends user if suspended in backup
# - Resets user password after successful restore (generates secure random password)
# - Generates DirectAdmin one-time login URL (if possible)
# - Prints Evolution skin "backups in-progress" URLs using hostname -f and server IP

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

DA_BIN="/usr/local/directadmin/directadmin"
DA_CONF="/usr/local/directadmin/conf/directadmin.conf"
DEFAULT_DOWNLOAD_DIR="/home/admin"
SYSTEM_LOG="/var/log/directadmin/system.log"
ERROR_LOG="/var/log/directadmin/errortaskq.log"
RAW_LOG="/tmp/da_restore_last.log"
RESTORE_LOG_DIR=""
RESTORE_LOG=""
SAVED_PASSWORD_HASH=""
USERNAME=""

# ============================================================================
# Functions
# ============================================================================

show_banner() {
  local GREEN='\033[0;32m'
  local BRIGHT_GREEN='\033[1;32m'
  local RESET='\033[0m'
  
  echo -e "${BRIGHT_GREEN}"
  cat <<'EOF'
    _         ____            __                 /\//\//
   (_)____   / __ \___  _____/ /_____  ________ //\//\/ 
  / / ___/  / /_/ / _ \/ ___/ __/ __ \/ ___/ _ \        
 / (__  )  / _, _/  __(__  ) /_/ /_/ / /  /  __/        
/_/____/  /_/ |_|\___/____/\__/\____/_/   \___/         
                                                        
EOF
  echo -e "${RESET}"
  echo
}

log() {
  local msg="[$(date +'%F %T')] $*"
  echo "${msg}" >&2
  [[ -n "${RESTORE_LOG}" ]] && echo "${msg}" >> "${RESTORE_LOG}" 2>/dev/null || true
}

log_verbose() {
  local msg="[$(date +'%F %T')] $*"
  [[ -n "${RESTORE_LOG}" ]] && echo "${msg}" >> "${RESTORE_LOG}" 2>/dev/null || true
}

log_warning() {
  local YELLOW='\033[1;33m'
  local RESET='\033[0m'
  echo -e "${YELLOW}[$(date +'%F %T')] $*${RESET}" >&2
}

log_error() {
  local RED='\033[1;31m'
  local RESET='\033[0m'
  echo -e "${RED}[$(date +'%F %T')] $*${RESET}" >&2
  [[ -n "${RESTORE_LOG}" ]] && echo "[$(date +'%F %T')] $*" >> "${RESTORE_LOG}" 2>/dev/null || true
}

usage() {
  cat <<EOF
Usage: $0 [-h owner] <backup_file_path_or_url>

  -h owner   DirectAdmin owner/reseller to use for restore.
             If omitted, owner is derived from hostname, e.g.:
               hostname -s = lh615  -> owner = islh615

If no backup_file_path_or_url is given, you'll be interactively prompted.
EOF
  exit 1
}

is_url() {
  case "$1" in
    http://*|https://*) return 0 ;;
    *) return 1 ;;
  esac
}

detect_server_ip() {
  ip route get 1.1.1.1 2>/dev/null \
    | awk '{for (i=1; i<=NF; i++) { if ($i == "src") { print $(i+1); exit } }}'
}

detect_da_port() {
  # Try to read port from DirectAdmin configuration file
  if [[ -f "${DA_CONF}" ]]; then
    local port
    port=$(grep -E '^port=' "${DA_CONF}" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | head -n1)
    if [[ -n "${port}" ]] && [[ "${port}" =~ ^[0-9]+$ ]]; then
      echo "${port}"
      return 0
    fi
  fi
  
  # Fallback to default port
  echo "2222"
}

human_size() {
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "$1"
  else
    echo "${1}B"
  fi
}

generate_password() {
  # Generate a secure random password (20 characters: alphanumeric)
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 15 | tr -d "=+/" | cut -c1-20
  elif [[ -r /dev/urandom ]]; then
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20
  else
    date +%s | sha256sum | base64 | tr -d "=+/" | head -c 20
  fi
}

download_backup() {
  local url="$1"
  local dest="$2"

  log "Downloading: ${url}"

  if command -v wget >/dev/null 2>&1; then
    wget --progress=bar:force -O "${dest}" "${url}" 2>&1 \
      | tee -a "${RAW_LOG}"
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
      log "✓ Download completed"
    else
      log "ERROR: Download failed"
      exit 1
    fi

  elif command -v curl >/dev/null 2>&1; then
    curl -L --progress-bar -o "${dest}" "${url}" 2>&1 \
      | tee -a "${RAW_LOG}"
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
      log "✓ Download completed"
    else
      log "ERROR: Download failed"
      exit 1
    fi

  else
    log "ERROR: Neither wget nor curl is available. Please install one of them."
    exit 1
  fi
}

download_backup_parallel() {
  local urls=("$@")
  local pids=()
  local dests=()

  log "Downloading ${#urls[@]} file(s) in parallel..."

  for url in "${urls[@]}"; do
    local dest="${DEFAULT_DOWNLOAD_DIR}/$(basename "${url}")"
    dests+=("${dest}")

    if command -v wget >/dev/null 2>&1; then
      wget --progress=bar:force -O "${dest}" "${url}" >> "${RAW_LOG}" 2>&1 &
    elif command -v curl >/dev/null 2>&1; then
      curl -L --progress-bar -o "${dest}" "${url}" >> "${RAW_LOG}" 2>&1 &
    fi

    pids+=($!)
  done

  for i in "${!pids[@]}"; do
    if wait "${pids[$i]}"; then
      log "✓ Downloaded: $(basename "${dests[$i]}")"
    else
      log "ERROR: Failed to download: $(basename "${dests[$i]}")"
    fi
  done
}

get_file_size() {
  local file="$1"
  if stat -c%s "${file}" 2>/dev/null; then
    :
  else
    wc -c < "${file}"
  fi
}

get_directory_size() {
  local dir="$1"
  if [[ ! -d "${dir}" ]]; then
    echo "0"
    return 1
  fi
  
  if command -v du >/dev/null 2>&1; then
    du -sb "${dir}" 2>/dev/null | awk '{print $1}'
  else
    find "${dir}" -type f -exec stat -c%s {} \; 2>/dev/null | awk '{sum+=$1} END {print sum+0}'
  fi
}

save_password_hash() {
  local username="$1"
  local shadow_file="/etc/shadow"
  local hash=""
  
  if [[ ! -r "${shadow_file}" ]]; then
    log_verbose "WARNING: Cannot read ${shadow_file} to save password hash for user ${username}"
    return 1
  fi
  
  if hash=$(grep "^${username}:" "${shadow_file}" 2>/dev/null | cut -d':' -f2); then
    if [[ -n "${hash}" ]] && [[ "${hash}" != "*" ]] && [[ "${hash}" != "!" ]] && [[ "${hash}" != "!!" ]]; then
      echo "${hash}"
      return 0
    fi
  fi
  
  return 1
}

restore_password_hash() {
  local username="$1"
  local hash="$2"
  
  if [[ -z "${username}" ]] || [[ -z "${hash}" ]]; then
    log "WARNING: Cannot restore password hash: missing username or hash"
    return 1
  fi
  
  log "Restoring original password for user ${username}..."
  
  if echo "${username}:${hash}" | chpasswd -e 2>/dev/null; then
    log "✓ Original password restored for user ${username}"
    return 0
  elif usermod -p "${hash}" "${username}" 2>/dev/null; then
    log "✓ Original password restored for user ${username}"
    return 0
  else
    log "WARNING: Failed to restore original password for user ${username}"
    return 1
  fi
}

parse_username_from_filename() {
  local filename="$1"
  if [[ "${filename}" == user.* ]]; then
    local tmp="${filename#user.}"
    local creator="${tmp%%.*}"
    local rest="${tmp#${creator}.}"
    echo "${rest%%.*}"
  fi
}

get_login_url() {
  local owner="$1"
  local url=""
  
  # Try new-style 'login-url' command (DirectAdmin 1.7+)
  if url="$(${DA_BIN} login-url 2>/dev/null | grep -Eo 'https?://[^ ]+' | head -n1)"; then
    [[ -n "${url}" ]] && echo "${url}" && return 0
  fi
  
  # Fallback to older --create-login-url syntax
  if url="$(${DA_BIN} --create-login-url "user=${owner}" 2>/dev/null | grep -Eo 'https?://[^ ]+' | head -n1)"; then
    [[ -n "${url}" ]] && echo "${url}" && return 0
  fi

  return 1
}

check_disk_space() {
  local backup_path="$1"
  local backup_size
  local avail_kb
  local avail_bytes
  local recommended_bytes
  
  backup_size=$(get_file_size "${backup_path}")
  avail_kb=$(df -Pk "$(dirname "${backup_path}")" | awk 'NR==2 {print $4}')
  avail_bytes=$((avail_kb * 1024))
  recommended_bytes=$((backup_size * 2))
  
  log_verbose "Backup size:      $(human_size "${backup_size}")"
  log_verbose "Free disk space:  $(human_size "${avail_bytes}") on filesystem of $(dirname "${backup_path}")"
  log_verbose "Recommended free: $(human_size "${recommended_bytes}") (2x backup size)"
  
  if (( avail_bytes < recommended_bytes )); then
    log "WARNING: Free disk space is less than 2x backup size. Restore may fail."
  else
    log_verbose "Disk space check: OK (>= 2x backup size)."
  fi
}

setup_restore_workdir() {
  local username="$1"
  local owner="$2"
  local workdir="/home/admin/${username}"
  
  if [[ ! -d "${workdir}" ]]; then
    log_verbose "Creating restore working directory: ${workdir}"
    mkdir -p "${workdir}"
  fi
  
  if id "${owner}" >/dev/null 2>&1; then
    log_verbose "Setting ownership of ${workdir} to ${owner}:${owner}"
    chown -R "${owner}:${owner}" "${workdir}"
  else
    log_verbose "WARNING: System user '${owner}' not found. Skipping chown for ${workdir}."
  fi
}

extract_domain_from_backup() {
  local backup_path="$1"
  local backup_filename
  backup_filename="$(basename "${backup_path}")"
  local backup_abs_path
  backup_abs_path="$(readlink -f "${backup_path}" 2>/dev/null || echo "${backup_path}")"
  local username=""
  local random_str
  random_str="$(openssl rand -hex 8 2>/dev/null || date +%s | sha256sum | cut -c1-16)"
  local temp_dir=""
  local user_conf=""
  local domain=""
  
  username="$(parse_username_from_filename "${backup_filename}")"
  if [[ -z "${username}" ]]; then
    username="unknown"
  fi
  
  temp_dir="/tmp/${username}_${random_str}"
  user_conf="${temp_dir}/backup/user.conf"
  
  log_verbose "Extracting domain from backup (reading backup/user.conf)..."
  log_verbose "  Temporary directory: ${temp_dir}"
  
  if [[ ! -f "${backup_path}" ]]; then
    log "ERROR: Backup file does not exist: ${backup_path}"
    return 1
  fi
  
  if [[ ! -r "${backup_path}" ]]; then
    log "ERROR: Backup file is not readable: ${backup_path}"
    return 1
  fi
  
  if ! mkdir -p "${temp_dir}" 2>/dev/null; then
    log "ERROR: Failed to create temporary directory: ${temp_dir}"
    return 1
  fi
  
  if [[ ! -d "${temp_dir}" ]]; then
    log "ERROR: Temporary directory was not created: ${temp_dir}"
    return 1
  fi
  
  if [[ "${backup_path}" == *.zst ]]; then
    if ! command -v zstd >/dev/null 2>&1; then
      log "WARNING: zstd not found. Cannot extract domain from .zst backup."
      rm -rf "${temp_dir}" 2>/dev/null || true
      return 1
    fi
    cd "${temp_dir}" || { log "ERROR: Failed to change to temp directory ${temp_dir}"; rm -rf "${temp_dir}" 2>/dev/null || true; return 1; }
    EXTRACT_OUTPUT=$(tar -I zstd -xf "${backup_abs_path}" backup/user.conf 2>&1 || true)
    EXTRACT_EXIT=$?
    cd - >/dev/null 2>&1 || true
    echo "${EXTRACT_OUTPUT}" >> "${RAW_LOG}"
    
    if [[ ${EXTRACT_EXIT} -eq 0 ]]; then
      if [[ -f "${user_conf}" ]]; then
        domain=$(grep -E '^domain=' "${user_conf}" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | head -n1)
      else
        log "WARNING: backup/user.conf not found in archive after extraction"
      fi
    else
      log "ERROR: Failed to extract backup/user.conf from .zst archive (exit code: ${EXTRACT_EXIT})"
    fi
  elif [[ "${backup_path}" == *.tar.gz ]] || [[ "${backup_path}" == *.tgz ]]; then
    cd "${temp_dir}" || { log "ERROR: Failed to change to temp directory ${temp_dir}"; rm -rf "${temp_dir}" 2>/dev/null || true; return 1; }
    EXTRACT_OUTPUT=$(tar -xzf "${backup_abs_path}" backup/user.conf 2>&1 || true)
    EXTRACT_EXIT=$?
    cd - >/dev/null 2>&1 || true
    echo "${EXTRACT_OUTPUT}" >> "${RAW_LOG}"
    
    if [[ ${EXTRACT_EXIT} -eq 0 ]]; then
      if [[ -f "${user_conf}" ]]; then
        domain=$(grep -E '^domain=' "${user_conf}" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | head -n1)
      else
        log "WARNING: backup/user.conf not found in archive after extraction"
      fi
    else
      log "ERROR: Failed to extract backup/user.conf from .tar.gz archive (exit code: ${EXTRACT_EXIT})"
    fi
  elif [[ "${backup_path}" == *.tar ]]; then
    cd "${temp_dir}" || { log "ERROR: Failed to change to temp directory ${temp_dir}"; rm -rf "${temp_dir}" 2>/dev/null || true; return 1; }
    EXTRACT_OUTPUT=$(tar -xf "${backup_abs_path}" backup/user.conf 2>&1 || true)
    EXTRACT_EXIT=$?
    cd - >/dev/null 2>&1 || true
    echo "${EXTRACT_OUTPUT}" >> "${RAW_LOG}"
    
    if [[ ${EXTRACT_EXIT} -eq 0 ]]; then
      if [[ -f "${user_conf}" ]]; then
        domain=$(grep -E '^domain=' "${user_conf}" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | head -n1)
      else
        log "WARNING: backup/user.conf not found in archive after extraction"
      fi
    else
      log "ERROR: Failed to extract backup/user.conf from .tar archive (exit code: ${EXTRACT_EXIT})"
    fi
  else
    log "WARNING: Unknown backup format. Cannot extract domain."
  fi
  
  if [[ -n "${domain}" ]]; then
    log_verbose "  Domain extracted successfully: ${domain}"
    log_verbose "  Temporary directory: ${temp_dir}"
    echo "${domain}" >&1
    rm -rf "${temp_dir}" 2>/dev/null || true
    return 0
  else
    log_verbose "  Failed to extract domain. Temporary directory: ${temp_dir}"
    log_verbose "  You can manually check: ${user_conf}"
    rm -rf "${temp_dir}" 2>/dev/null || true
    return 1
  fi
}

check_domain_exists() {
  local domain="$1"
  local domainowners="/etc/virtual/domainowners"
  local existing_user=""
  
  if [[ ! -f "${domainowners}" ]]; then
    log "WARNING: /etc/virtual/domainowners file not found"
    return 1
  fi
  
  if existing_user=$(grep "^${domain}:" "${domainowners}" 2>/dev/null | cut -d':' -f2 | tr -d ' ' | head -n1); then
    if [[ -n "${existing_user}" ]]; then
      echo "${existing_user}"
      return 0
    fi
  fi
  
  return 1
}

rename_backup_for_existing_user() {
  local backup_path="$1"
  local source_user="$2"
  local existing_user="$3"
  local backup_dir
  local backup_name
  local new_backup_path
  local new_backup_name
  
  backup_dir="$(dirname "${backup_path}")"
  backup_name="$(basename "${backup_path}")"
  
  new_backup_name="${backup_name/${source_user}/${existing_user}}"
  new_backup_path="${backup_dir}/${new_backup_name}"
  
  if [[ "${backup_path}" != "${new_backup_path}" ]]; then
    log "Renaming backup file from ${backup_name} to ${new_backup_name}"
    if mv "${backup_path}" "${new_backup_path}" 2>/dev/null; then
      echo "${new_backup_path}"
      return 0
    else
      log "WARNING: Failed to rename backup file. Continuing with original name."
      echo "${backup_path}"
      return 0
    fi
  fi
  
  echo "${backup_path}"
  return 0
}

replace_old_username_references() {
  local existing_user="$1"
  local old_username="$2"
  local user_home="/home/${existing_user}"
  local files_updated=0
  
  if [[ ! -d "${user_home}" ]]; then
    log "WARNING: User home directory ${user_home} not found. Skipping username reference replacement."
    return 1
  fi
  
  log "Replacing old username in file contents (${old_username} -> ${existing_user})..."
  
  # Replace old username in file contents only
  while IFS= read -r file; do
    if [[ -f "${file}" ]] && [[ -r "${file}" ]] && [[ -w "${file}" ]]; then
      if grep -q "${old_username}" "${file}" 2>/dev/null; then
        if sed -i "s/${old_username}/${existing_user}/g" "${file}" 2>/dev/null; then
          log_verbose "  Updated file contents: ${file}"
          ((files_updated++))
        fi
      fi
    fi
  done < <(find "${user_home}" -type f ! -name "*.log" ! -name "*.log.*" ! -path "*/tmp/*" ! -path "*/cache/*" ! -path "*/backup/*" 2>/dev/null)
  
  # Verify replacement - check if any old username references still exist in file contents
  REMAINING_REFS=$(find "${user_home}" -type f ! -name "*.log" ! -name "*.log.*" ! -path "*/tmp/*" ! -path "*/cache/*" ! -path "*/backup/*" 2>/dev/null | xargs grep -l "${old_username}" 2>/dev/null | wc -l || echo "0")
  
  log "✓ Username replacement in file contents completed."
  log "  Files updated: ${files_updated}"
  
  if [[ ${REMAINING_REFS} -gt 0 ]]; then
    log "⚠️  WARNING: ${REMAINING_REFS} file(s) still contain references to '${old_username}' in their contents."
  else
    log "✓ Verification: No remaining references to '${old_username}' found in file contents."
  fi
}

# ============================================================================
# Main Script
# ============================================================================

# Parse arguments
OWNER_OVERRIDE=""
INPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h)
      shift
      [[ $# -eq 0 ]] && { echo "ERROR: -h requires an argument (owner name)." >&2; usage; }
      OWNER_OVERRIDE="$1"
      shift
      ;;
    -*)
      echo "ERROR: Unknown option: $1" >&2
      usage
      ;;
    *)
      if [[ -z "${INPUT}" ]]; then
        INPUT="$1"
        shift
      else
        echo "ERROR: Unexpected extra argument: $1" >&2
        usage
      fi
      ;;
  esac
done

# Clear screen and display banner
clear
show_banner

# Create restore log directory
RESTORE_LOG_DIR="/tmp/da_restore_$(date +%s)_$$"
mkdir -p "${RESTORE_LOG_DIR}" 2>/dev/null || RESTORE_LOG_DIR="/tmp"
RESTORE_LOG="${RESTORE_LOG_DIR}/restore.log"
: > "${RESTORE_LOG}"

# Get backup input
if [[ -z "${INPUT}" ]]; then
  read -erp "Enter backup file path or URL: " INPUT
  [[ -z "${INPUT}" ]] && { echo "No input provided. Exiting."; exit 1; }
fi

log "DirectAdmin auto-restore starting..."
: > "${RAW_LOG}"
log_verbose "Full log directory: ${RESTORE_LOG_DIR}"
log_verbose "Full log file: ${RESTORE_LOG}"

# Determine owner
HOST_SHORT="$(hostname -s 2>/dev/null || hostname)"
DEFAULT_OWNER="is${HOST_SHORT}"
OWNER="${OWNER_OVERRIDE:-${DEFAULT_OWNER}}"

log_verbose "Hostname short form: ${HOST_SHORT}"
log_verbose "Default owner from hostname: ${DEFAULT_OWNER}"
log_verbose "Requested/selected owner: ${OWNER}"

# Validate owner exists
if [[ ! -d "/usr/local/directadmin/data/users/${OWNER}" ]]; then
  log "WARNING: DirectAdmin user '${OWNER}' does not exist. Falling back to 'admin'."
  OWNER="admin"
fi
log_verbose "Using DirectAdmin owner for restore: ${OWNER}"

# Resolve backup path (URL or local file)
if is_url "${INPUT}"; then
  mkdir -p "${DEFAULT_DOWNLOAD_DIR}"
  FILE_NAME="$(basename "${INPUT}")"
  BACKUP_PATH="${DEFAULT_DOWNLOAD_DIR}/${FILE_NAME}"
  download_backup "${INPUT}" "${BACKUP_PATH}"
else
  if [[ "${INPUT}" = /* ]]; then
    BACKUP_PATH="${INPUT}"
  else
    BACKUP_PATH="$(pwd)/${INPUT}"
  fi
  log_verbose "Detected local file input: ${BACKUP_PATH}"
fi

LOCAL_PATH="$(dirname "${BACKUP_PATH}")"
FILE_NAME="$(basename "${BACKUP_PATH}")"
ORIGINAL_BACKUP_PATH="${BACKUP_PATH}"
ORIGINAL_FILE_NAME="${FILE_NAME}"

if [[ ! -f "${BACKUP_PATH}" ]]; then
  log "WARNING: Backup file not found: ${BACKUP_PATH}"
  log_verbose "Checking for user backup files in directory..."
  
  shopt -s nullglob
  POSSIBLE_FILES=("${LOCAL_PATH}"/user.*.tar.zst "${LOCAL_PATH}"/user.*.tar.gz "${LOCAL_PATH}"/user.*.tar)
  shopt -u nullglob
  
  if [[ ${#POSSIBLE_FILES[@]} -eq 1 ]] && [[ -f "${POSSIBLE_FILES[0]}" ]]; then
    log "Found backup file: $(basename "${POSSIBLE_FILES[0]}")"
    BACKUP_PATH="${POSSIBLE_FILES[0]}"
    FILE_NAME="$(basename "${BACKUP_PATH}")"
    log_verbose "Using backup file: ${BACKUP_PATH}"
  elif [[ ${#POSSIBLE_FILES[@]} -gt 1 ]]; then
    log "ERROR: Multiple backup files found. Please specify the exact filename."
    exit 1
  else
    log "ERROR: Backup file does not exist: ${BACKUP_PATH}"
    exit 1
  fi
fi

log_verbose "Backup file resolved to:"
log_verbose "  Path : ${BACKUP_PATH}"
log_verbose "  Dir  : ${LOCAL_PATH}"
log_verbose "  Name : ${FILE_NAME}"

# Detect server IP
SERVER_IP="${SERVER_IP:-$(detect_server_ip || echo "")}"
[[ -z "${SERVER_IP}" ]] && {
  log "ERROR: Could not detect server IP automatically."
  log "       You can set it manually, e.g.:"
  log "       SERVER_IP=1.2.3.4 $0 ${INPUT}"
  exit 1
}
log_verbose "Using server IP for restore: ${SERVER_IP}"

# Check disk space
check_disk_space "${BACKUP_PATH}"

# Check if domain from backup already exists on server
log "Checking domain from backup..."
BACKUP_DOMAIN="$(extract_domain_from_backup "${BACKUP_PATH}" || echo "")"
ORIGINAL_USERNAME=""
EXISTING_USER=""
USER_EXISTED_BEFORE_RESTORE=0

if [[ -n "${BACKUP_DOMAIN}" ]]; then
  log_verbose "Extracted domain from backup: ${BACKUP_DOMAIN}"
  EXISTING_USER="$(check_domain_exists "${BACKUP_DOMAIN}" || echo "")"
  
  if [[ -n "${EXISTING_USER}" ]]; then
    USER_EXISTED_BEFORE_RESTORE=1
    ORIGINAL_USERNAME="$(parse_username_from_filename "${FILE_NAME}")"
    echo
    log_warning "⚠️  USER ALREADY EXISTS: Domain '${BACKUP_DOMAIN}' belongs to user '${EXISTING_USER}'"
    if [[ -n "${ORIGINAL_USERNAME}" ]] && [[ "${ORIGINAL_USERNAME}" != "${EXISTING_USER}" ]]; then
      log_warning "⚠️  Restore will be performed on existing user '${EXISTING_USER}' (backup is for '${ORIGINAL_USERNAME}')"
    else
      log_warning "⚠️  Restore will be performed on existing user '${EXISTING_USER}'"
    fi
    
    # Save current password hash before restore
    log_verbose "Saving current password hash for user ${EXISTING_USER}..."
    SAVED_PASSWORD_HASH="$(save_password_hash "${EXISTING_USER}" || echo "")"
    if [[ -n "${SAVED_PASSWORD_HASH}" ]]; then
      log_verbose "✓ Password hash saved (will be restored after backup restore)"
    else
      log_verbose "WARNING: Could not save password hash for user ${EXISTING_USER}"
    fi
    
    # Check existing user's directory size
    USER_HOME="/home/${EXISTING_USER}"
    if [[ -d "${USER_HOME}" ]]; then
      DIR_SIZE=$(get_directory_size "${USER_HOME}" || echo 0)
      DIR_SIZE_MB=$((DIR_SIZE / 1024 / 1024))
      SIZE_THRESHOLD_MB=10
      
      if [[ ${DIR_SIZE_MB} -gt ${SIZE_THRESHOLD_MB} ]]; then
        DIR_SIZE_HUMAN=$(human_size "${DIR_SIZE}")
        log_error "⚠️  WARNING: User '${EXISTING_USER}' has existing data (${DIR_SIZE_HUMAN}) in /home/${EXISTING_USER}!"
        log_error "⚠️  Restoring will overwrite this data. Current disk usage: ${DIR_SIZE_HUMAN}"
      fi
    fi
    
    if [[ -n "${ORIGINAL_USERNAME}" ]] && [[ "${ORIGINAL_USERNAME}" != "${EXISTING_USER}" ]]; then
      log_verbose "Backup is for user '${ORIGINAL_USERNAME}' but domain belongs to '${EXISTING_USER}'"
      log_verbose "Renaming backup file to restore to existing user ${EXISTING_USER}..."
      
      BACKUP_PATH="$(rename_backup_for_existing_user "${BACKUP_PATH}" "${ORIGINAL_USERNAME}" "${EXISTING_USER}")"
      FILE_NAME="$(basename "${BACKUP_PATH}")"
      LOCAL_PATH="$(dirname "${BACKUP_PATH}")"
      
      log_verbose "Backup file renamed. New path: ${BACKUP_PATH}"
      USERNAME="${EXISTING_USER}"
    else
      USERNAME="${EXISTING_USER}"
    fi
  else
    log_verbose "Domain ${BACKUP_DOMAIN} does not exist on this server. Proceeding with normal restore."
  fi
else
  log_verbose "Could not extract domain from backup. Proceeding with normal restore."
fi

# Detect username from filename (if not already set from domain check)
if [[ -z "${USERNAME}" ]]; then
  USERNAME="$(parse_username_from_filename "${FILE_NAME}")"
fi

if [[ -n "${USERNAME}" ]]; then
  USER_DIR="/usr/local/directadmin/data/users/${USERNAME}"
  if [[ -d "${USER_DIR}" ]] && [[ ${USER_EXISTED_BEFORE_RESTORE} -eq 0 ]]; then
    USER_EXISTED_BEFORE_RESTORE=1
    
    # Save current password hash before restore
    log_verbose "Saving current password hash for user ${USERNAME}..."
    SAVED_PASSWORD_HASH="$(save_password_hash "${USERNAME}" || echo "")"
    if [[ -n "${SAVED_PASSWORD_HASH}" ]]; then
      log_verbose "✓ Password hash saved (will be restored after backup restore)"
    else
      log_verbose "WARNING: Could not save password hash for user ${USERNAME}"
    fi
    
    # Check existing user's directory size
    USER_HOME="/home/${USERNAME}"
    if [[ -d "${USER_HOME}" ]]; then
      DIR_SIZE=$(get_directory_size "${USER_HOME}" || echo 0)
      DIR_SIZE_MB=$((DIR_SIZE / 1024 / 1024))
      SIZE_THRESHOLD_MB=10
      
      if [[ ${DIR_SIZE_MB} -gt ${SIZE_THRESHOLD_MB} ]]; then
        DIR_SIZE_HUMAN=$(human_size "${DIR_SIZE}")
        log_error "⚠️  WARNING: User '${USERNAME}' has existing data (${DIR_SIZE_HUMAN}) in /home/${USERNAME}!"
        log_error "⚠️  Restoring will overwrite this data. Current disk usage: ${DIR_SIZE_HUMAN}"
      fi
    fi
  fi
  
  if [[ -d "${USER_DIR}" ]]; then
    if [[ -n "${ORIGINAL_USERNAME}" ]] && [[ "${ORIGINAL_USERNAME}" != "${USERNAME}" ]]; then
      log_verbose "Domain ${BACKUP_DOMAIN} from backup belongs to existing user: ${USERNAME}"
      log_verbose "Backup will be restored to existing user ${USERNAME} (original backup was for ${ORIGINAL_USERNAME})"
      echo
      read -erp "Continue and restore backup to existing user ${USERNAME}? [y/N]: " CONFIRM
      case "${CONFIRM}" in
        [yY]|[yY][eE][sS])
          log_verbose "User chose to continue restore to existing user ${USERNAME}."
          ;;
        *)
          log "Restore was NOT confirmed. Aborting restore."
          exit 0
          ;;
      esac
    else
      log_verbose "Detected username from backup filename: ${USERNAME} (EXISTS on this server)"
      echo
      read -erp "User ${USERNAME} already exists. Continue and restore over this existing user from backup? [y/N]: " CONFIRM
      case "${CONFIRM}" in
        [yY]|[yY][eE][sS])
          log_verbose "User chose to continue restore and overwrite existing user ${USERNAME}."
          ;;
        *)
          log "User ${USERNAME} exists and restore was NOT confirmed. Aborting restore."
          exit 0
          ;;
      esac
    fi
  else
    log_verbose "Detected username from backup filename: ${USERNAME} (does NOT exist yet)"
  fi
  setup_restore_workdir "${USERNAME}" "${OWNER}"
else
  log_verbose "WARNING: Could not parse username from filename. Skipping user-specific working dir."
fi

# Snapshot log sizes
SYS_LINES_BEFORE=0
ERR_LINES_BEFORE=0
SUSPENDED_IN_BACKUP=0
SUCCESS_LINE=""

[[ -f "${SYSTEM_LOG}" ]] && SYS_LINES_BEFORE=$(wc -l < "${SYSTEM_LOG}" 2>/dev/null || echo 0)
[[ -f "${ERROR_LOG}" ]] && ERR_LINES_BEFORE=$(wc -l < "${ERROR_LOG}" 2>/dev/null || echo 0)

# Print GUI URLs
FQDN_HOST="$(hostname -f 2>/dev/null || echo "${HOST_SHORT}")"
DA_PORT="$(detect_da_port)"
LOGIN_URL="$(get_login_url "${OWNER}" || echo "")"

if [[ -n "${LOGIN_URL}" ]]; then
  log "Login URL: ${LOGIN_URL}"
fi

log "In-progress URL: https://${FQDN_HOST}:${DA_PORT}/evo/admin/backups/in-progress"
log_verbose "  Also available via IP: https://${SERVER_IP}:${DA_PORT}/evo/admin/backups/in-progress"

# Run DirectAdmin restore
log "Starting restore..."
log_verbose "Full raw output will be appended to: ${RAW_LOG}"

RESTORE_EXIT=0
if ! "${DA_BIN}" taskq \
  --run="action=restore&ip_choice=select&ip=${SERVER_IP}&local_path=${LOCAL_PATH}&owner=${OWNER}&select0=${FILE_NAME}&type=admin&value=multiple&when=now&where=local" \
  >> "${RAW_LOG}" 2>&1; then
  RESTORE_EXIT=$?
  log "WARNING: Restore command exited with non-zero status: ${RESTORE_EXIT}"
fi

log "Restore completed. Checking results..."

# Parse restore logs - save full logs, show concise summary
if [[ -f "${SYSTEM_LOG}" ]]; then
  NEW_SYS_LINES="$(tail -n +$((SYS_LINES_BEFORE + 1)) "${SYSTEM_LOG}" 2>/dev/null || true)"
  echo "${NEW_SYS_LINES}" >> "${RESTORE_LOG}" 2>/dev/null || true

  if [[ -n "${NEW_SYS_LINES}" ]]; then
    if [[ -n "${USERNAME}" ]]; then
      FILTERED_LINES="$(echo "${NEW_SYS_LINES}" | grep -i "${USERNAME}" || true)"
      SUCCESS_LINE="$(echo "${FILTERED_LINES}" | grep -i "has been restored from" | tail -n 1 || true)"

      if [[ -n "${SUCCESS_LINE}" ]]; then
        log "✓ Restore successful: ${SUCCESS_LINE}"
      else
        log "⚠️  No explicit success message found for user ${USERNAME}"
      fi
      
      [[ -n "${USERNAME}" ]] && echo "${NEW_SYS_LINES}" | grep -q "User ${USERNAME} was suspended in the backup" && SUSPENDED_IN_BACKUP=1
    else
      SUCCESS_LINE="$(echo "${NEW_SYS_LINES}" | grep -i "has been restored from" | tail -n 1 || true)"
      if [[ -n "${SUCCESS_LINE}" ]]; then
        log "✓ Restore completed"
      fi
    fi
  fi
fi

if [[ -f "${ERROR_LOG}" ]]; then
  NEW_ERR_LINES="$(tail -n +$((ERR_LINES_BEFORE + 1)) "${ERROR_LOG}" 2>/dev/null || true)"
  echo "${NEW_ERR_LINES}" >> "${RESTORE_LOG}" 2>/dev/null || true
  
  if [[ -n "${NEW_ERR_LINES}" ]]; then
    if [[ -n "${USERNAME}" ]]; then
      FILTERED_ERR_LINES="$(echo "${NEW_ERR_LINES}" | grep -i "${USERNAME}\|${FILE_NAME}" || true)"
      if [[ -n "${FILTERED_ERR_LINES}" ]]; then
        log "⚠️  Errors found. Check full log: ${RESTORE_LOG}"
      fi
    fi
  fi
fi

# Auto unsuspend user (if needed)
if [[ -n "${USERNAME}" ]] && (( SUSPENDED_IN_BACKUP == 1 )); then
  log "Unsuspending user ${USERNAME}..."
  if "${DA_BIN}" --unsuspend-user "user=${USERNAME}" >> "${RAW_LOG}" 2>&1; then
    log "✓ User ${USERNAME} unsuspended"
  else
    log "WARNING: Failed to unsuspend user ${USERNAME}"
  fi
fi

# Reset password after restore (if successful and user didn't exist before)
if [[ -n "${USERNAME}" ]] && [[ -n "${SUCCESS_LINE}" ]] && [[ ${USER_EXISTED_BEFORE_RESTORE} -eq 0 ]]; then
  log "Resetting password for user ${USERNAME}..."
  NEW_PASSWORD="$(generate_password)"
  
  if "${DA_BIN}" --set-password "user=${USERNAME}" "password=${NEW_PASSWORD}" >> "${RAW_LOG}" 2>&1; then
    USER_LOGIN_URL="$(get_login_url "${USERNAME}" || echo "")"
    FQDN_HOST="$(hostname -f 2>/dev/null || echo "${HOST_SHORT}")"
    DA_PORT="$(detect_da_port)"
    
    echo
    log "=========================================="
    log "Login Information:"
    if [[ -n "${USER_LOGIN_URL}" ]]; then
      log "Login URL: ${USER_LOGIN_URL}"
    else
      log "Login URL: https://${FQDN_HOST}:${DA_PORT}"
    fi
    log "Username: ${USERNAME}"
    log "Password: ${NEW_PASSWORD}"
    log "=========================================="
    echo
  else
    log "WARNING: Failed to reset password for user ${USERNAME}"
  fi
elif [[ -n "${USERNAME}" ]] && [[ ${USER_EXISTED_BEFORE_RESTORE} -eq 1 ]] && [[ -n "${SUCCESS_LINE}" ]]; then
  log_verbose "Skipping password reset: User ${USERNAME} existed before restore (password preserved)."
elif [[ -n "${USERNAME}" ]] && [[ -z "${SUCCESS_LINE}" ]]; then
  log_verbose "Skipping password reset: No successful restore detected for user ${USERNAME}."
fi

# Restore original password hash if user existed before restore
if [[ ${USER_EXISTED_BEFORE_RESTORE} -eq 1 ]] && [[ -n "${USERNAME}" ]] && [[ -n "${SUCCESS_LINE}" ]] && [[ -n "${SAVED_PASSWORD_HASH}" ]]; then
  restore_password_hash "${USERNAME}" "${SAVED_PASSWORD_HASH}" || true
fi

# Replace old username references if restored to existing user
if [[ -n "${ORIGINAL_USERNAME}" ]] && [[ -n "${USERNAME}" ]] && [[ "${ORIGINAL_USERNAME}" != "${USERNAME}" ]] && [[ -n "${SUCCESS_LINE}" ]]; then
  log "Restore completed to existing user ${USERNAME} (original backup was for ${ORIGINAL_USERNAME})"
  replace_old_username_references "${USERNAME}" "${ORIGINAL_USERNAME}" || true
fi

# Restore original backup filename if it was renamed
if [[ -n "${ORIGINAL_BACKUP_PATH}" ]] && [[ "${BACKUP_PATH}" != "${ORIGINAL_BACKUP_PATH}" ]] && [[ -f "${BACKUP_PATH}" ]]; then
  log "Restoring original backup filename..."
  if mv "${BACKUP_PATH}" "${ORIGINAL_BACKUP_PATH}" 2>/dev/null; then
    log "✓ Backup file renamed back to: $(basename "${ORIGINAL_BACKUP_PATH}")"
  else
    log "WARNING: Failed to restore original backup filename"
  fi
fi

# Copy raw log to restore log directory
if [[ -f "${RAW_LOG}" ]]; then
  cp "${RAW_LOG}" "${RESTORE_LOG_DIR}/raw.log" 2>/dev/null || true
fi

# Final summary
echo
log "Full restore log saved to: ${RESTORE_LOG}"
log_verbose "Log directory: ${RESTORE_LOG_DIR}"
[[ ${RESTORE_EXIT} -ne 0 ]] && log "⚠️  Restore exit code: ${RESTORE_EXIT}. Check logs for details."
