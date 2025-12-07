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

run_no_lve_banner() {
  "$@" 2> >(grep -v 'LVE' | grep -v 'cloudlinux.com' >&2)
}

clear
show_banner

read -erp "Please input path to file: " src

src="$(readlink -f -- "${src}" 2>/dev/null || printf "%s\n" "${src}")"
dst="/var/www/html"

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

host="$(hostname -f)"
public_ip="$(curl -s ifconfig.me 2>/dev/null || echo "")"
base="$(basename -- "${src}")"

echo "Copying file to web directory..."

if command -v rsync >/dev/null 2>&1; then
  if run_no_lve_banner sudo rsync --whole-file --inplace --no-compress --info=progress2 "${src}" "${dst}/${base}"; then
    COPY_SUCCESS=1
  else
    COPY_SUCCESS=0
  fi
else
  echo "ERROR: rsync command not found."
  exit 9
fi

if [[ ${COPY_SUCCESS} -eq 1 ]]; then
  sudo chown root:root -- "${dst}/${base}"
  sudo chmod 644 -- "${dst}/${base}"
  echo
  echo "✓ Done: ${dst}/${base} (owner root:root, mode 644)"
  echo
  echo "📥 Download URL (hostname): http://${host}/${base}"
  [[ -n "${public_ip}" ]] && echo "📥 Download URL (public IP): http://${public_ip}/${base}"
else
  echo "ERROR: Failed to copy file to ${dst}/${base}"
  exit 3
fi
