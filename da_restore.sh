#!/bin/bash
#
# DirectAdmin auto restore script
# - Uses reseller derived from hostname (e.g. lh615 -> islh615)
# - Does NOT move/rename backup file
# - Detects username from backup filename (user.<creator>.<username>.*)
# - If user already exists:
#     * Asks for confirmation to continue (overwrite)
#     * If not confirmed, aborts safely
# - Fixes permissions for /home/admin/<username> for the chosen owner
# - Shows only new DirectAdmin log lines for this run
# - If "User <username> was suspended in the backup" is detected,
#     * it auto-unsuspends that user after restore
# - Additionally:
#     * Generates DirectAdmin one-time login URL (if possible)
#     * Prints Evolution skin "backups in-progress" URLs using hostname -f and server IP
#

set -euo pipefail

DA_BIN="/usr/local/directadmin/directadmin"
DEFAULT_DOWNLOAD_DIR="/home/admin"

SYSTEM_LOG="/var/log/directadmin/system.log"
ERROR_LOG="/var/log/directadmin/errortaskq.log"
RAW_LOG="/tmp/da_restore_last.log"

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

human_size() {
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "$1"
  else
    echo "${1}B"
  fi
}

# --------- parse arguments (owner override + input) ----------

OWNER_OVERRIDE=""
INPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: -h requires an argument (owner name)." >&2
        usage
      fi
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

# If no input was provided, ask interactively
if [[ -z "${INPUT}" ]]; then
  read -rp "Enter backup file path or URL: " INPUT
  if [[ -z "${INPUT}" ]]; then
    echo "No input provided. Exiting."
    exit 1
  fi
fi

log "DirectAdmin auto-restore starting..."

# Prepare raw log file early
: > "${RAW_LOG}"
log "Raw log will be stored in: ${RAW_LOG}"

# --------- determine default owner from hostname ----------

HOST_SHORT="$(hostname -s 2>/dev/null || hostname)"
DEFAULT_OWNER="is${HOST_SHORT}"

OWNER="${DEFAULT_OWNER}"

if [[ -n "${OWNER_OVERRIDE}" ]]; then
  OWNER="${OWNER_OVERRIDE}"
fi

log "Hostname short form: ${HOST_SHORT}"
log "Default owner from hostname: ${DEFAULT_OWNER}"
log "Requested/selected owner: ${OWNER}"

# Validate that owner exists as DA user; fallback to admin if not.
if [[ ! -d "/usr/local/directadmin/data/users/${OWNER}" ]]; then
  log "WARNING: DirectAdmin user '${OWNER}' does not exist. Falling back to 'admin'."
  OWNER="admin"
fi

log "Using DirectAdmin owner for restore: ${OWNER}"

# --------- resolve input (URL vs local path), WITHOUT moving backup ----------

BACKUP_PATH=""

if is_url "${INPUT}"; then
  mkdir -p "${DEFAULT_DOWNLOAD_DIR}"
  FILE_NAME_FROM_URL="$(basename "${INPUT}")"
  DEST="${DEFAULT_DOWNLOAD_DIR}/${FILE_NAME_FROM_URL}"

  log "Detected URL input."
  log "Downloading backup to: ${DEST}"

  if command -v wget >/dev/null 2>&1; then
    wget -O "${DEST}" "${INPUT}" >> "${RAW_LOG}" 2>&1
  elif command -v curl >/dev/null 2>&1; then
    curl -L -o "${DEST}" "${INPUT}" >> "${RAW_LOG}" 2>&1
  else
    log "ERROR: Neither wget nor curl is available. Please install one of them."
    exit 1
  fi

  BACKUP_PATH="${DEST}"
else
  if [[ "${INPUT}" = /* ]]; then
    BACKUP_PATH="${INPUT}"
  else
    BACKUP_PATH="$(pwd)/${INPUT}"
  fi
  log "Detected local file input: ${BACKUP_PATH}"
fi

if [[ ! -f "${BACKUP_PATH}" ]]; then
  log "ERROR: Backup file does not exist: ${BACKUP_PATH}"
  exit 1
fi

LOCAL_PATH="$(dirname "${BACKUP_PATH}")"
FILE_NAME="$(basename "${BACKUP_PATH}")"

log "Backup file resolved to:"
log "  Path : ${BACKUP_PATH}"
log "  Dir  : ${LOCAL_PATH}"
log "  Name : ${FILE_NAME}"

# --------- detect server IP ----------

SERVER_IP="${SERVER_IP:-$(detect_server_ip)}"
if [[ -z "${SERVER_IP}" ]]; then
  log "ERROR: Could not detect server IP automatically."
  log "       You can set it manually, e.g.:"
  log "       SERVER_IP=1.2.3.4 $0 ${INPUT}"
  exit 1
fi

log "Using server IP for restore: ${SERVER_IP}"

# --------- pre-check: backup size vs free disk space ----------

if BACKUP_SIZE_BYTES=$(stat -c%s "${BACKUP_PATH}" 2>/dev/null); then
  :
else
  BACKUP_SIZE_BYTES=$(wc -c < "${BACKUP_PATH}")
fi

AVAIL_KB=$(df -Pk "${LOCAL_PATH}" | awk 'NR==2 {print $4}')
AVAIL_BYTES=$((AVAIL_KB * 1024))
RECOMMENDED_MIN_BYTES=$((BACKUP_SIZE_BYTES * 2))

log "Backup size:      $(human_size "${BACKUP_SIZE_BYTES}")"
log "Free disk space:  $(human_size "${AVAIL_BYTES}") on filesystem of ${LOCAL_PATH}"
log "Recommended free: $(human_size "${RECOMMENDED_MIN_BYTES}") (2x backup size)"

if (( AVAIL_BYTES < RECOMMENDED_MIN_BYTES )); then
  log "WARNING: Free disk space is less than 2x backup size."
  log "         Restore may fail due to insufficient space."
else
  log "Disk space check: OK (>= 2x backup size)."
fi

# --------- detect DA username from filename ----------

USERNAME=""
if [[ "${FILE_NAME}" == user.* ]]; then
  TMP="${FILE_NAME#user.}"        # remove leading 'user.'
  CREATOR="${TMP%%.*}"            # first part (original creator)
  REST="${TMP#${CREATOR}.}"       # rest without creator
  USERNAME="${REST%%.*}"          # first part of rest is username
fi

if [[ -n "${USERNAME}" ]]; then
  USER_DIR="/usr/local/directadmin/data/users/${USERNAME}"
  if [[ -d "${USER_DIR}" ]]; then
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
  else
    log "Detected username from backup filename: ${USERNAME} (does NOT exist yet)"
  fi

  # Ensure /home/admin/<username> exists and is writable by OWNER.
  RESTORE_WORKDIR="/home/admin/${USERNAME}"
  if [[ ! -d "${RESTORE_WORKDIR}" ]]; then
    log "Creating restore working directory: ${RESTORE_WORKDIR}"
    mkdir -p "${RESTORE_WORKDIR}"
  fi
  if id "${OWNER}" >/dev/null 2>&1; then
    log "Setting ownership of ${RESTORE_WORKDIR} to ${OWNER}:${OWNER}"
    chown -R "${OWNER}:${OWNER}" "${RESTORE_WORKDIR}"
  else
    log "WARNING: System user '${OWNER}' not found. Skipping chown for ${RESTORE_WORKDIR}."
  fi
else
  log "WARNING: Could not parse username from filename. Skipping user-specific working dir."
fi

# --------- snapshot log sizes so we only show NEW lines ----------

SYS_LINES_BEFORE=0
ERR_LINES_BEFORE=0
SUSPENDED_IN_BACKUP=0

if [[ -f "${SYSTEM_LOG}" ]]; then
  SYS_LINES_BEFORE=$(wc -l < "${SYSTEM_LOG}" 2>/dev/null || echo 0)
fi
if [[ -f "${ERROR_LOG}" ]]; then
  ERR_LINES_BEFORE=$(wc -l < "${ERROR_LOG}" 2>/dev/null || echo 0)
fi

# --------- print GUI URLs: login-url + in-progress pages ----------

FQDN_HOST="$(hostname -f 2>/dev/null || echo "${HOST_SHORT}")"
DA_PORT="2222"

LOGIN_URL=""

# Try new-style 'login-url' command (DirectAdmin 1.7+)
if LOGIN_URL_RAW="$(${DA_BIN} login-url 2>/dev/null | grep -Eo 'https?://[^ ]+' | head -n1)"; then
  if [[ -n "${LOGIN_URL_RAW}" ]]; then
    LOGIN_URL="${LOGIN_URL_RAW}"
  fi
fi

# Fallback to older --create-login-url syntax for specific owner
if [[ -z "${LOGIN_URL}" ]]; then
  if LOGIN_URL_RAW="$(${DA_BIN} --create-login-url "user=${OWNER}" 2>/dev/null | grep -Eo 'https?://[^ ]+' | head -n1)"; then
    if [[ -n "${LOGIN_URL_RAW}" ]]; then
      LOGIN_URL="${LOGIN_URL_RAW}"
    fi
  fi
fi

log "Web access / monitoring info:"
if [[ -n "${LOGIN_URL}" ]]; then
  log "  One-time DirectAdmin login URL (auto-login as main admin/owner):"
  log "    ${LOGIN_URL}"
else
  log "  Could not auto-generate one-time login URL via DirectAdmin binary."
fi

PROGRESS_FQDN="https://${FQDN_HOST}:${DA_PORT}/evo/admin/backups/in-progress"
PROGRESS_IP="https://${SERVER_IP}:${DA_PORT}/evo/admin/backups/in-progress"

log "  Evo backups in-progress (hostname):"
log "    ${PROGRESS_FQDN}"
log "  Evo backups in-progress (server IP):"
log "    ${PROGRESS_IP}"

# --------- run DirectAdmin restore ----------

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

echo
echo "================ Restore summary (system.log) ================"

NEW_SYS_LINES=""
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

    if [[ -n "${USERNAME}" ]] && echo "${NEW_SYS_LINES}" | grep -q "User ${USERNAME} was suspended in the backup"; then
      SUSPENDED_IN_BACKUP=1
    fi
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

# --------- auto unsuspend restored user (if needed) ----------

if [[ -n "${USERNAME}" ]]; then
  if (( SUSPENDED_IN_BACKUP == 1 )); then
    log "User ${USERNAME} WAS suspended in the backup. Trying to UNSUSPEND now..."
    if "${DA_BIN}" --unsuspend-user "user=${USERNAME}" >> "${RAW_LOG}" 2>&1; then
      log "User ${USERNAME} has been UNSUSPENDED by this script."
    else
      log "WARNING: Failed to unsuspend user ${USERNAME}. Check ${RAW_LOG} for details."
    fi
  else
    log "User ${USERNAME} was not reported as suspended in this backup run."
  fi
fi

log "Done. Full raw output is available in: ${RAW_LOG}"
if [[ ${RESTORE_EXIT} -ne 0 ]]; then
  log "NOTE: Restore command exit code was ${RESTORE_EXIT}. Please double-check the logs above and ${RAW_LOG}."
fi
