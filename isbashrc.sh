#!/bin/bash
set -euo pipefail

TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
TARGET_HOME="$(eval echo ~"${TARGET_USER}")"
BASHRC="${TARGET_HOME}/.bashrc"
ISBASHRC_URL="https://raw.isssh.ir/.isbashrc"
ISBASHRC_PATH="${TARGET_HOME}/.isbashrc"
SOURCE_LINE='[ -f ~/.isbashrc ] && source ~/.isbashrc'

echo "Installing .isbashrc for user: ${TARGET_USER}"
echo "Target home: ${TARGET_HOME}"

case "${TARGET_USER}" in
  root|jumpserver)
    echo "ERROR: Not allowed to install for user: ${TARGET_USER}"
    exit 1
    ;;
esac

if [[ ! -f "${BASHRC}" ]]; then
  echo "Creating ${BASHRC}"
  touch "${BASHRC}"
fi

BACKUP_SUFFIX="$(date +%s)"
cp -a "${BASHRC}" "${BASHRC}.bak.${BACKUP_SUFFIX}"
echo "Backup created: ${BASHRC}.bak.${BACKUP_SUFFIX}"

if ! grep -Fq "${SOURCE_LINE}" "${BASHRC}"; then
  printf '\n%s\n' "${SOURCE_LINE}" >> "${BASHRC}"
  echo "Appended source line to ${BASHRC}"
else
  echo "Source line already present in ${BASHRC}"
fi

echo "Downloading ${ISBASHRC_URL} -> ${ISBASHRC_PATH}"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "${ISBASHRC_URL}" -o "${ISBASHRC_PATH}"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "${ISBASHRC_PATH}" "${ISBASHRC_URL}"
else
  echo "ERROR: Neither curl nor wget found"
  exit 1
fi

if [[ -n "${SUDO_USER:-}" ]]; then
  chown "${TARGET_USER}:${TARGET_USER}" "${ISBASHRC_PATH}" "${BASHRC}" || true
fi

chmod 644 "${ISBASHRC_PATH}" || true

echo "Done. Reload with: source \"${BASHRC}\""
echo "Reloading in 5 seconds..."
sleep 5
clear
CURRENT_USER="${USER:-$(id -un)}"
if [[ "${CURRENT_USER}" == "${TARGET_USER}" ]]; then
  exec bash --rcfile "${BASHRC}" -i
else
  echo "To reload for ${TARGET_USER}: sudo -u ${TARGET_USER} bash -lc 'exec bash --rcfile ~/.bashrc -i'"
fi
