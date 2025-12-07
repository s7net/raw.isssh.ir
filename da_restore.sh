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

# ============================================================================
# Functions
# ============================================================================

show_banner() {
  cat <<'EOF'
    _      __________ __  __       _____           _       __      
   (_)____/ ___/ ___// / / /      / ___/__________(_)___  / /______
  / / ___/\__ \\__ \/ /_/ /       \__ \/ ___/ ___/ / __ \/ __/ ___/
 / (__  )___/ /__/ / __  /       ___/ / /__/ /  / / /_/ / /_(__  ) 
/_/____//____/____/_/ /_/       /____/\___/_/  /_/ .___/\__/____/  
                                                /_/               
EOF
  echo
}

log() {
  echo "[$(date +'%F %T')] $*"
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
  
  if command -v wget >/dev/null 2>&1; then
    wget -O "${dest}" "${url}" >> "${RAW_LOG}" 2>&1
  elif command -v curl >/dev/null 2>&1; then
    curl -L -o "${dest}" "${url}" >> "${RAW_LOG}" 2>&1
  else
    log "ERROR: Neither wget nor curl is available. Please install one of them."
    exit 1
  fi
}

get_file_size() {
  local file="$1"
  if stat -c%s "${file}" 2>/dev/null; then
    :
  else
    wc -c < "${file}"
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
    [[ -n "${url}" ]] && echo "${url}"
  fi
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
  
  log "Backup size:      $(human_size "${backup_size}")"
  log "Free disk space:  $(human_size "${avail_bytes}") on filesystem of $(dirname "${backup_path}")"
  log "Recommended free: $(human_size "${recommended_bytes}") (2x backup size)"
  
  if (( avail_bytes < recommended_bytes )); then
    log "WARNING: Free disk space is less than 2x backup size."
    log "         Restore may fail due to insufficient space."
  else
    log "Disk space check: OK (>= 2x backup size)."
  fi
}

setup_restore_workdir() {
  local username="$1"
  local owner="$2"
  local workdir="/home/admin/${username}"
  
  if [[ ! -d "${workdir}" ]]; then
    log "Creating restore working directory: ${workdir}"
    mkdir -p "${workdir}"
  fi
  
  if id "${owner}" >/dev/null 2>&1; then
    log "Setting ownership of ${workdir} to ${owner}:${owner}"
    chown -R "${owner}:${owner}" "${workdir}"
  else
    log "WARNING: System user '${owner}' not found. Skipping chown for ${workdir}."
  fi
}

extract_domain_from_backup() {
  local backup_path="$1"
  local backup_filename="$(basename "${backup_path}")"
  local username=""
  local random_str="$(openssl rand -hex 8 2>/dev/null || date +%s | sha256sum | cut -c1-16)"
  local temp_dir=""
  local user_conf=""
  local domain=""
  
  username="$(parse_username_from_filename "${backup_filename}")"
  if [[ -z "${username}" ]]; then
    username="unknown"
  fi
  
  temp_dir="/tmp/${username}_${random_str}"
  user_conf="${temp_dir}/backup/user.conf"
  
  log "Extracting domain from backup (reading backup/user.conf)..."
  log "  Temporary directory: ${temp_dir}"
  mkdir -p "${temp_dir}"
  
  if [[ "${backup_path}" == *.zst ]]; then
    if ! command -v zstd >/dev/null 2>&1; then
      log "WARNING: zstd not found. Cannot extract domain from .zst backup."
      rm -rf "${temp_dir}" 2>/dev/null
      return 1
    fi
    if tar -I zstd -xf "${backup_path}" backup/user.conf -C "${temp_dir}" >> "${RAW_LOG}" 2>&1; then
      if [[ -f "${user_conf}" ]]; then
        log "Checking user.conf file: ${user_conf}"
        domain=$(grep -E '^domain=' "${user_conf}" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | head -n1)
        log "Successfully extracted and read user.conf from backup"
      else
        log "WARNING: backup/user.conf not found in archive"
      fi
    else
      log "WARNING: Failed to extract backup/user.conf from .zst archive"
    fi
  elif [[ "${backup_path}" == *.tar.gz ]] || [[ "${backup_path}" == *.tgz ]]; then
    if tar -xzf "${backup_path}" backup/user.conf -C "${temp_dir}" >> "${RAW_LOG}" 2>&1; then
      if [[ -f "${user_conf}" ]]; then
        log "Checking user.conf file: ${user_conf}"
        domain=$(grep -E '^domain=' "${user_conf}" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | head -n1)
        log "Successfully extracted and read user.conf from backup"
      else
        log "WARNING: backup/user.conf not found in archive"
      fi
    else
      log "WARNING: Failed to extract backup/user.conf from .tar.gz archive"
    fi
  elif [[ "${backup_path}" == *.tar ]]; then
    if tar -xf "${backup_path}" backup/user.conf -C "${temp_dir}" >> "${RAW_LOG}" 2>&1; then
      if [[ -f "${user_conf}" ]]; then
        log "Checking user.conf file: ${user_conf}"
        domain=$(grep -E '^domain=' "${user_conf}" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | head -n1)
        log "Successfully extracted and read user.conf from backup"
      else
        log "WARNING: backup/user.conf not found in archive"
      fi
    else
      log "WARNING: Failed to extract backup/user.conf from .tar archive"
    fi
  else
    log "WARNING: Unknown backup format. Cannot extract domain."
  fi
  
  rm -rf "${temp_dir}" 2>/dev/null
  
  if [[ -n "${domain}" ]]; then
    echo "${domain}"
    return 0
  else
    return 1
  fi
}

check_domain_exists() {
  local domain="$1"
  local domainowners="/etc/virtual/domainowners"
  
  if [[ ! -f "${domainowners}" ]]; then
    return 1
  fi
  
  if grep -q "^${domain}:" "${domainowners}" 2>/dev/null; then
    grep "^${domain}:" "${domainowners}" | cut -d':' -f2 | tr -d ' '
    return 0
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
      return 1
    fi
  fi
  
  echo "${backup_path}"
}

replace_old_username_references() {
  local existing_user="$1"
  local old_username="$2"
  local user_home="/home/${existing_user}"
  
  if [[ ! -d "${user_home}" ]]; then
    log "WARNING: User home directory ${user_home} not found. Skipping username reference replacement."
    return 1
  fi
  
  log "Replacing old username references (${old_username}) in ${user_home}..."
  
  find "${user_home}" -type f -name "*${old_username}*" 2>/dev/null | while IFS= read -r old_file; do
    new_file="${old_file//${old_username}/${existing_user}}"
    if [[ "${old_file}" != "${new_file}" ]] && [[ ! -e "${new_file}" ]]; then
      log "  Renaming: $(basename "${old_file}") -> $(basename "${new_file}")"
      mv "${old_file}" "${new_file}" 2>/dev/null
    fi
  done
  
  find "${user_home}" -type d -name "*${old_username}*" 2>/dev/null | sort -r | while IFS= read -r old_dir; do
    new_dir="${old_dir//${old_username}/${existing_user}}"
    if [[ "${old_dir}" != "${new_dir}" ]] && [[ ! -e "${new_dir}" ]]; then
      log "  Renaming directory: $(basename "${old_dir}") -> $(basename "${new_dir}")"
      mv "${old_dir}" "${new_dir}" 2>/dev/null
    fi
  done
  
  log "Username reference replacement completed."
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

# Display banner
show_banner

# Get backup input
if [[ -z "${INPUT}" ]]; then
  read -rp "Enter backup file path or URL: " INPUT
  [[ -z "${INPUT}" ]] && { echo "No input provided. Exiting."; exit 1; }
fi

log "DirectAdmin auto-restore starting..."
: > "${RAW_LOG}"
log "Raw log will be stored in: ${RAW_LOG}"

# Determine owner
HOST_SHORT="$(hostname -s 2>/dev/null || hostname)"
DEFAULT_OWNER="is${HOST_SHORT}"
OWNER="${OWNER_OVERRIDE:-${DEFAULT_OWNER}}"

log "Hostname short form: ${HOST_SHORT}"
log "Default owner from hostname: ${DEFAULT_OWNER}"
log "Requested/selected owner: ${OWNER}"

# Validate owner exists
if [[ ! -d "/usr/local/directadmin/data/users/${OWNER}" ]]; then
  log "WARNING: DirectAdmin user '${OWNER}' does not exist. Falling back to 'admin'."
  OWNER="admin"
fi
log "Using DirectAdmin owner for restore: ${OWNER}"

# Resolve backup path (URL or local file)
if is_url "${INPUT}"; then
  mkdir -p "${DEFAULT_DOWNLOAD_DIR}"
  FILE_NAME="$(basename "${INPUT}")"
  BACKUP_PATH="${DEFAULT_DOWNLOAD_DIR}/${FILE_NAME}"
  log "Detected URL input. Downloading backup to: ${BACKUP_PATH}"
  download_backup "${INPUT}" "${BACKUP_PATH}"
else
  if [[ "${INPUT}" = /* ]]; then
    BACKUP_PATH="${INPUT}"
  else
    BACKUP_PATH="$(pwd)/${INPUT}"
  fi
  log "Detected local file input: ${BACKUP_PATH}"
fi

[[ ! -f "${BACKUP_PATH}" ]] && { log "ERROR: Backup file does not exist: ${BACKUP_PATH}"; exit 1; }

LOCAL_PATH="$(dirname "${BACKUP_PATH}")"
FILE_NAME="$(basename "${BACKUP_PATH}")"

log "Backup file resolved to:"
log "  Path : ${BACKUP_PATH}"
log "  Dir  : ${LOCAL_PATH}"
log "  Name : ${FILE_NAME}"

# Detect server IP
SERVER_IP="${SERVER_IP:-$(detect_server_ip)}"
[[ -z "${SERVER_IP}" ]] && {
  log "ERROR: Could not detect server IP automatically."
  log "       You can set it manually, e.g.:"
  log "       SERVER_IP=1.2.3.4 $0 ${INPUT}"
  exit 1
}
log "Using server IP for restore: ${SERVER_IP}"

# Check disk space
check_disk_space "${BACKUP_PATH}"

# Check if domain from backup already exists on server
# We extract backup/user.conf to get the domain name, which tells us if we should
# restore to an existing user (if domain already exists) or create a new user
log "Checking if domain from backup already exists on server..."
log "  (Extracting backup/user.conf to read domain name...)"
BACKUP_DOMAIN="$(extract_domain_from_backup "${BACKUP_PATH}")"
ORIGINAL_USERNAME=""
EXISTING_USER=""

if [[ -n "${BACKUP_DOMAIN}" ]]; then
  log "Extracted domain from backup: ${BACKUP_DOMAIN}"
  EXISTING_USER="$(check_domain_exists "${BACKUP_DOMAIN}")"
  
  if [[ -n "${EXISTING_USER}" ]]; then
    echo
    log "=========================================="
    log "DOMAIN ALREADY EXISTS ON SERVER:"
    log "  Domain: ${BACKUP_DOMAIN}"
    log "  Existing User: ${EXISTING_USER}"
    log "=========================================="
    echo
    ORIGINAL_USERNAME="$(parse_username_from_filename "${FILE_NAME}")"
    
    if [[ -n "${ORIGINAL_USERNAME}" ]] && [[ "${ORIGINAL_USERNAME}" != "${EXISTING_USER}" ]]; then
      log "Backup is for user '${ORIGINAL_USERNAME}' but domain belongs to '${EXISTING_USER}'"
      log "Renaming backup file to restore to existing user ${EXISTING_USER}..."
      
      BACKUP_PATH="$(rename_backup_for_existing_user "${BACKUP_PATH}" "${ORIGINAL_USERNAME}" "${EXISTING_USER}")"
      FILE_NAME="$(basename "${BACKUP_PATH}")"
      LOCAL_PATH="$(dirname "${BACKUP_PATH}")"
      
      log "Backup file renamed. New path: ${BACKUP_PATH}"
      USERNAME="${EXISTING_USER}"
    else
      USERNAME="${EXISTING_USER}"
    fi
  else
    log "Domain ${BACKUP_DOMAIN} does not exist on this server. Proceeding with normal restore."
  fi
else
  log "Could not extract domain from backup. Proceeding with normal restore."
fi

# Detect username from filename (if not already set from domain check)
if [[ -z "${USERNAME}" ]]; then
  USERNAME="$(parse_username_from_filename "${FILE_NAME}")"
fi

if [[ -n "${USERNAME}" ]]; then
  USER_DIR="/usr/local/directadmin/data/users/${USERNAME}"
  if [[ -d "${USER_DIR}" ]]; then
    if [[ -n "${ORIGINAL_USERNAME}" ]] && [[ "${ORIGINAL_USERNAME}" != "${USERNAME}" ]]; then
      log "Domain ${BACKUP_DOMAIN} from backup belongs to existing user: ${USERNAME}"
      log "Backup will be restored to existing user ${USERNAME} (original backup was for ${ORIGINAL_USERNAME})"
      echo
      read -rp "Continue and restore backup to existing user ${USERNAME}? [y/N]: " CONFIRM
      case "${CONFIRM}" in
        [yY]|[yY][eE][sS])
          log "User chose to continue restore to existing user ${USERNAME}."
          ;;
        *)
          log "Restore was NOT confirmed. Aborting restore."
          exit 0
          ;;
      esac
    else
      log "Detected username from backup filename: ${USERNAME} (EXISTS on this server)"
      echo
      read -rp "User ${USERNAME} already exists. Continue and restore over this existing user from backup? [y/N]: " CONFIRM
      case "${CONFIRM}" in
        [yY]|[yY][eE][sS])
          log "User chose to continue restore and overwrite existing user ${USERNAME}."
          ;;
        *)
          log "User ${USERNAME} exists and restore was NOT confirmed. Aborting restore."
          exit 0
          ;;
      esac
    fi
  else
    log "Detected username from backup filename: ${USERNAME} (does NOT exist yet)"
  fi
  setup_restore_workdir "${USERNAME}" "${OWNER}"
else
  log "WARNING: Could not parse username from filename. Skipping user-specific working dir."
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
LOGIN_URL="$(get_login_url "${OWNER}")"

log "Web access / monitoring info:"
log "  Detected DirectAdmin port: ${DA_PORT}"
if [[ -n "${LOGIN_URL}" ]]; then
  log "  One-time DirectAdmin login URL (auto-login as main admin/owner):"
  log "    ${LOGIN_URL}"
else
  log "  Could not auto-generate one-time login URL via DirectAdmin binary."
fi

log "  Evo backups in-progress (hostname):"
log "    https://${FQDN_HOST}:${DA_PORT}/evo/admin/backups/in-progress"
log "  Evo backups in-progress (server IP):"
log "    https://${SERVER_IP}:${DA_PORT}/evo/admin/backups/in-progress"

# Run DirectAdmin restore
log "Running DirectAdmin restore task..."
log "Full raw output will be appended to: ${RAW_LOG}"

RESTORE_EXIT=0
if ! "${DA_BIN}" taskq \
  --run="action=restore&ip_choice=select&ip=${SERVER_IP}&local_path=${LOCAL_PATH}&owner=${OWNER}&select0=${FILE_NAME}&type=admin&value=multiple&when=now&where=local" \
  >> "${RAW_LOG}" 2>&1; then
  RESTORE_EXIT=$?
  log "WARNING: DirectAdmin restore command exited with non-zero status: ${RESTORE_EXIT}"
fi

log "Restore command finished. Collecting log summary..."

# Parse restore logs
echo
echo "================ Restore summary (system.log) ================"

if [[ -f "${SYSTEM_LOG}" ]]; then
  NEW_SYS_LINES="$(tail -n +$((SYS_LINES_BEFORE + 1)) "${SYSTEM_LOG}" 2>/dev/null || true)"
  
  if [[ -n "${NEW_SYS_LINES}" ]]; then
    echo "${NEW_SYS_LINES}" | tail -n 80
    
    SUCCESS_LINE="$(echo "${NEW_SYS_LINES}" | grep -i 'has been restored from' | tail -n 1 || true)"
    if [[ -n "${SUCCESS_LINE}" ]]; then
      echo
      log "Detected successful restore line:"
      echo "  ${SUCCESS_LINE}"
    else
      echo
      log "No explicit \"has been restored\" line detected for this run."
    fi
    
    [[ -n "${USERNAME}" ]] && echo "${NEW_SYS_LINES}" | grep -q "User ${USERNAME} was suspended in the backup" && SUSPENDED_IN_BACKUP=1
  else
    log "No new lines in system.log for this run."
  fi
else
  log "system.log not found at: ${SYSTEM_LOG}"
fi

echo
echo "================ Error summary (errortaskq.log) ================"

if [[ -f "${ERROR_LOG}" ]]; then
  NEW_ERR_LINES="$(tail -n +$((ERR_LINES_BEFORE + 1)) "${ERROR_LOG}" 2>/dev/null || true)"
  if [[ -n "${NEW_ERR_LINES}" ]]; then
    echo "${NEW_ERR_LINES}" | tail -n 80
  else
    echo "(no new errors for this run)"
  fi
else
  log "errortaskq.log not found at: ${ERROR_LOG}"
fi

echo

# Auto unsuspend user (if needed)
if [[ -n "${USERNAME}" ]] && (( SUSPENDED_IN_BACKUP == 1 )); then
  log "User ${USERNAME} WAS suspended in the backup. Trying to UNSUSPEND now..."
  if "${DA_BIN}" --unsuspend-user "user=${USERNAME}" >> "${RAW_LOG}" 2>&1; then
    log "User ${USERNAME} has been UNSUSPENDED by this script."
  else
    log "WARNING: Failed to unsuspend user ${USERNAME}. Check ${RAW_LOG} for details."
  fi
elif [[ -n "${USERNAME}" ]]; then
  log "User ${USERNAME} was not reported as suspended in this backup run."
fi

# Reset password after restore (if successful)
if [[ -n "${USERNAME}" ]] && [[ -n "${SUCCESS_LINE}" ]]; then
  log "Resetting password for user ${USERNAME}..."
  NEW_PASSWORD="$(generate_password)"
  
  if "${DA_BIN}" --set-password "user=${USERNAME}" "password=${NEW_PASSWORD}" >> "${RAW_LOG}" 2>&1; then
    log "Password has been reset for user ${USERNAME}."
    echo
    log "=========================================="
    log "NEW PASSWORD for user ${USERNAME}:"
    log "  ${NEW_PASSWORD}"
    log "=========================================="
    echo
    log "IMPORTANT: Save this password securely. It will not be shown again."
  else
    log "WARNING: Failed to reset password for user ${USERNAME}. Check ${RAW_LOG} for details."
  fi
elif [[ -n "${USERNAME}" ]] && [[ -z "${SUCCESS_LINE}" ]]; then
  log "Skipping password reset: No successful restore detected for user ${USERNAME}."
fi

# Replace old username references if restored to existing user
if [[ -n "${ORIGINAL_USERNAME}" ]] && [[ -n "${USERNAME}" ]] && [[ "${ORIGINAL_USERNAME}" != "${USERNAME}" ]] && [[ -n "${SUCCESS_LINE}" ]]; then
  log "Restore completed to existing user ${USERNAME} (original backup was for ${ORIGINAL_USERNAME})"
  replace_old_username_references "${USERNAME}" "${ORIGINAL_USERNAME}"
fi

# Final summary
log "Done. Full raw output is available in: ${RAW_LOG}"
[[ ${RESTORE_EXIT} -ne 0 ]] && log "NOTE: Restore command exit code was ${RESTORE_EXIT}. Please double-check the logs above and ${RAW_LOG}."
