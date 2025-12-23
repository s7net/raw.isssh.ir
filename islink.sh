#!/bin/bash

set -uo pipefail

show_banner() {
  local ORANGE='\033[38;5;208m'
  local RESET='\033[0m'
  echo -e "${ORANGE}"
  cat <<'EOF'
 __       _______.    __       __  .__   __.  __     ___              
|  |     /       |   |  |     |  | |  \ |  | |  |   /  /              
|  |    |   (----`   |  |     |  | |   \|  | |  |  /  / ______ ______ 
|  |     \   \       |  |     |  | |  . `  | |  | <  < |______|______|
|  | .----)   |      |  `----.|  | |  |\   | |  |  \  \               
|__| |_______/       |_______||__| |__| \__| |  |   \__\              
                                             |__|                       
EOF
  echo -e "${RESET}"
  echo
}

detect_public_ip() {
  local ip=""
  local services=(
    "https://api.isssh.ir/tools/myip.php"
    "https://api.ipify.org"
    "https://ipv4.icanhazip.com"
    "https://checkip.amazonaws.com"
    "https://ipecho.net/plain"
    "https://myexternalip.com/raw"
    "https://wtfismyip.com/text"
    "http://whatismyip.akamai.com"
  )
  
  for service in "${services[@]}"; do
    if command -v curl >/dev/null 2>&1; then
      ip=$(curl -s --connect-timeout 5 --max-time 10 "${service}" 2>/dev/null | grep -oE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | head -n1)
    elif command -v wget >/dev/null 2>&1; then
      ip=$(wget -qO- --timeout=10 "${service}" 2>/dev/null | grep -oE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | head -n1)
    fi
    
    if [[ -n "${ip}" ]] && [[ "${ip}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
      local first_octet="${ip%%.*}"
      local second_octet="${ip#*.}"; second_octet="${second_octet%%.*}"
      
      if [[ "${first_octet}" -eq 10 ]] || \
         [[ "${first_octet}" -eq 172 && "${second_octet}" -ge 16 && "${second_octet}" -le 31 ]] || \
         [[ "${first_octet}" -eq 192 && "${second_octet}" -eq 168 ]] || \
         [[ "${first_octet}" -eq 127 ]]; then
        continue
      fi
      
      echo "${ip}"
      return 0
    fi
  done
  
  return 1
}

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root."
  exit 99
fi

show_banner

read -erp "Please input path to file: " src

src="$(readlink -f -- "${src}" 2>/dev/null || printf "%s\n" "${src}")"

declare -a CANDIDATES=(
  "/var/www/html"        
  "/www/wwwroot/default" 
)

AVAILABLE=()
for path in "${CANDIDATES[@]}"; do
  if [[ -d "${path}" ]]; then
    AVAILABLE+=("${path}")
  fi
done

if [[ ${#AVAILABLE[@]} -eq 0 ]]; then
  echo "WARNING: No known web root directories found."
  read -erp "Please enter destination web root path manually: " dst
else
  if [[ ${#AVAILABLE[@]} -eq 1 ]]; then
    dst="${AVAILABLE[0]}"
    echo "Detected web root: ${dst}"
    if [[ "${dst}" == "/www/wwwroot/default" ]]; then
      echo "(Looks like aaPanel default web root)"
    elif [[ "${dst}" == "/var/www/html" ]]; then
      echo "(Standard /var/www/html web root)"
    fi
  else
    echo "Multiple possible web roots detected:"
    i=1
    for path in "${AVAILABLE[@]}"; do
      echo "  [$i] ${path}"
      ((i++))
    done
    read -erp "Select destination [1-${#AVAILABLE[@]}] (default 1): " choice
    choice="${choice:-1}"
    if ! [[ "${choice}" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#AVAILABLE[@]} )); then
      echo "Invalid choice, defaulting to 1."
      choice=1
    fi
    dst="${AVAILABLE[$((choice-1))]}"
    echo "Using: ${dst}"
  fi
fi

if [[ ! -e "${src}" ]]; then
  echo "ERROR: Source file or directory not found: ${src}"
  exit 1
fi

if [[ ! -d "${dst}" ]]; then
  echo "ERROR: Destination directory not found: ${dst}"
  exit 2
fi

if [[ -d "${src}" ]]; then
  echo
  read -erp "This is a folder. Create zip file and use it as backup? [y/N]: " CREATE_ZIP
  case "${CREATE_ZIP}" in
    [yY]|[yY][eE][sS])
      if ! command -v zip >/dev/null 2>&1; then
        echo "ERROR: 'zip' command not found. Please install zip or provide a file instead of a folder."
        exit 8
      fi
      ZIP_NAME="$(basename -- "${src}").zip"
      ZIP_PATH="/tmp/${ZIP_NAME}"
      echo "Creating zip file: ${ZIP_PATH}"
      if zip -r "${ZIP_PATH}" "${src}" >/dev/null 2>&1; then
        src="${ZIP_PATH}"
        echo "✓ Zip file created: ${ZIP_PATH}"
      else
        echo "ERROR: Failed to create zip file."
        exit 4
      fi
      ;;
    *)
      echo "ERROR: Folder support requires zip file creation. Exiting."
      exit 6
      ;;
  esac
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "ERROR: rsync command not found."
  exit 9
fi

host="$(hostname -f)"
public_ip="$(detect_public_ip || echo "")"
base="$(basename -- "${src}")"

echo "Copying file to web directory..."

if rsync --whole-file --inplace --no-compress --info=progress2 "${src}" "${dst}/${base}"; then
  COPY_SUCCESS=1
else
  COPY_SUCCESS=0
fi

if [[ ${COPY_SUCCESS} -eq 1 ]]; then
  owner_group="$(stat -c '%u:%g' "${dst}" 2>/dev/null || echo "0:0")"
  chown "${owner_group}" -- "${dst}/${base}"
  chmod 644 -- "${dst}/${base}"
  echo
  echo "✓ Done: ${dst}/${base} (owner $(stat -c '%U:%G' "${dst}/${base}" 2>/dev/null), mode 644)"
  echo
  echo "📥 Download URL (hostname): http://${host}/${base}"
  if [[ -n "${public_ip}" ]] && [[ "${public_ip}" != "ERROR" ]]; then
    echo "📥 Download URL (public IP): http://${public_ip}/${base}"
  else
    echo "⚠️  Could not detect public IP (services may be blocked in your region)"
  fi
else
  echo "ERROR: Failed to copy file to ${dst}/${base}"
  exit 3
fi
