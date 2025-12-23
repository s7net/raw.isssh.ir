#!/bin/bash

set -uo pipefail

BACKUP_BASE="/home/*/weekly*"
SCRIPT_URL="https://raw.isssh.ir/isbackup.sh"
SERVER_FILTER=""
USERNAME=""

usage() {
  cat <<EOF
Usage: $0 [-s server] [-u username] [username]

  -s server    Filter backups by server name (e.g., lh620)
  -u username  Username to search for
  username     Username to search for (positional argument)

If no username is provided, you'll be interactively prompted.
By default, searches in all servers.
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s)
      shift
      [[ $# -eq 0 ]] && { echo "ERROR: -s requires a server name." >&2; usage; }
      SERVER_FILTER="$1"
      shift
      ;;
    -u)
      shift
      [[ $# -eq 0 ]] && { echo "ERROR: -u requires a username." >&2; usage; }
      USERNAME="$1"
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "ERROR: Unknown option: $1" >&2
      usage
      ;;
    *)
      if [[ -z "${USERNAME}" ]]; then
        USERNAME="$1"
        shift
      else
        echo "ERROR: Unexpected extra argument: $1" >&2
        usage
      fi
      ;;
  esac
done

show_banner() {
  local CYAN='\033[0;36m'
  local BRIGHT_CYAN='\033[1;36m'
  local BLUE='\033[0;34m'
  local RESET='\033[0m'
  
  echo -e "${BRIGHT_CYAN}"
  cat <<'EOF'
    _         __               __             ___ 
   (_)____   ╱ ╱_  ____ ______╱ ╱____  ______╱__ ╲
  ╱ ╱ ___╱  ╱ __ ╲╱ __ `╱ ___╱ ╱╱_╱ ╱ ╱ ╱ __ ╲╱ _╱
 ╱ (__  )  ╱ ╱_╱ ╱ ╱_╱ ╱ ╱__╱ ,< ╱ ╱_╱ ╱ ╱_╱ ╱_╱  
╱_╱____╱  ╱_.___╱╲__,_╱╲___╱_╱│_│╲__,_╱ .___(_)   
                                     ╱_╱          
EOF
  echo -e "${RESET}"
  echo
}

clear
show_banner

if [[ -z "${USERNAME}" ]]; then
  read -erp "please input username or ( domain only for wh*** hosts ) : " USERNAME
  if [[ -z "${USERNAME}" ]]; then
    echo "ERROR: Username cannot be empty."
    exit 1
  fi
fi

clear
show_banner

if [[ -n "${SERVER_FILTER}" ]]; then
  echo "Searching for backups matching: /home/${SERVER_FILTER}/weekly*/*${USERNAME}*"
  SEARCH_PATTERN="/home/${SERVER_FILTER}/weekly*"
else
  echo "Searching for backups matching: ${BACKUP_BASE}/*${USERNAME}*"
  SEARCH_PATTERN="/home/*/weekly*"
fi
SEARCH_START=$(date +%s%N)

declare -A SERVER_SET
shopt -s nullglob extglob
mapfile -t BACKUP_FILES < <(
  for weekly_dir in ${SEARCH_PATTERN}; do
    [[ -d "${weekly_dir}" ]] || continue
    find "${weekly_dir}" -maxdepth 1 -type f -name "*${USERNAME}*" -printf '%T@\t%p\n' 2>/dev/null
  done | sort -rn | cut -f2-
)
shopt -u nullglob extglob

SEARCH_END=$(date +%s%N)
SEARCH_TIME_NS=$((SEARCH_END - SEARCH_START))
SEARCH_TIME_SEC=$(awk "BEGIN {printf \"%.3f\", ${SEARCH_TIME_NS} / 1000000000}")
echo "Search completed in ${SEARCH_TIME_SEC}s"
echo

if [[ ${#BACKUP_FILES[@]} -eq 0 ]]; then
  echo "No backups found for username: ${USERNAME}"
  exit 1
fi

for file in "${BACKUP_FILES[@]}"; do
  if [[ "${file}" =~ /home/([^/]+)/weekly ]]; then
    SERVER_SET["${BASH_REMATCH[1]}"]=1
  fi
done

SERVER_COUNT=${#SERVER_SET[@]}
CURRENT_HOST=$(hostname -s)

echo "Private note usage for '${USERNAME}':"
echo "====================================="
for server in $(printf '%s\n' "${!SERVER_SET[@]}" | sort); do
  echo "  [${CURRENT_HOST} - ${server}]"
  echo "  bash <(curl -Ls ${SCRIPT_URL}) -u ${USERNAME} -s ${server}"
  echo
done
echo

echo "Available backups (newest first):"
echo "================================="
echo " 0) Latest backup (most recent)"
for i in "${!BACKUP_FILES[@]}"; do
  file="${BACKUP_FILES[$i]}"
  server_name=""
  if [[ "${file}" =~ /home/([^/]+)/weekly ]]; then
    server_name="${BASH_REMATCH[1]}"
  fi
  file_info=$(ls -lh "${file}" 2>/dev/null | awk '{print $5, $6, $7, $8}')
  if [[ -n "${server_name}" ]] && [[ ${SERVER_COUNT} -gt 1 ]]; then
    printf "%2d) [%s] %s\n" $((i + 1)) "${server_name}" "${file_info}"
  else
    printf "%2d) %s\n" $((i + 1)) "${file_info}"
  fi
done
echo

read -erp "Select backup file (enter number, 0 for latest): " SELECTION
if [[ ! "${SELECTION}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: Invalid selection. Please enter a number."
  exit 1
fi

if [[ "${SELECTION}" == "0" ]]; then
  SELECTED_INDEX=0
elif (( SELECTION >= 1 && SELECTION <= ${#BACKUP_FILES[@]} )); then
  SELECTED_INDEX=$((SELECTION - 1))
else
  echo "ERROR: Selection out of range. Please select 0 (latest) or a number between 1 and ${#BACKUP_FILES[@]}."
  exit 1
fi

SELECTED_PATH="${BACKUP_FILES[$SELECTED_INDEX]}"

SRC="$(readlink -f -- "${SELECTED_PATH}" 2>/dev/null || printf "%s\n" "${SELECTED_PATH}")"
DST="/var/www/html"

echo
echo "Selected backup path: ${SRC}"
echo

if [[ ! -e "${SRC}" ]]; then
  echo "ERROR: Source file not found: ${SRC}"
  exit 1
fi

if [[ ! -d "${DST}" ]]; then
  echo "ERROR: Destination directory not found: ${DST}"
  exit 2
fi

HOST="$(hostname -f)"
BASE="$(basename -- "${SRC}")"

echo "Copying file to web directory..."
FILE_SIZE=$(stat -c%s "${SRC}" 2>/dev/null || stat -f%z "${SRC}" 2>/dev/null || echo 0)

ifif command -v rsync >/dev/null 2>&1; then
  if sudo rsync -aW --inplace --no-compress --info=progress2 \
    "${SRC}" "${DST}/${BASE}"; then
    COPY_SUCCESS=1
  else
    COPY_SUCCESS=0
  fi
elif command -v rsync >/dev/null 2>&1; then
  if sudo rsync --whole-file --inplace --no-compress --info=progress2 "${SRC}" "${DST}/${BASE}"; then
    COPY_SUCCESS=1
  else
    COPY_SUCCESS=0
  fi
else
  if sudo cp -a -- "${SRC}" "${DST}/${BASE}"; then
    COPY_SUCCESS=1
  else
    COPY_SUCCESS=0
  fi
fi

if [[ ${COPY_SUCCESS} -eq 1 ]]; then
  sudo chown root:root -- "${DST}/${BASE}" && \
  sudo chmod 644 -- "${DST}/${BASE}" && \
  echo
  echo "✓ Done: ${DST}/${BASE} (owner root:root, mode 644)"
  echo
  echo "📥 Download URL: http://${HOST}/${BASE}"
else
  echo "ERROR: Failed to copy file to ${DST}/${BASE}"
  exit 3
fi
