#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BRIGHT_GREEN='\033[1;32m'
NC='\033[0m'

show_banner() {
  echo -e "${BRIGHT_GREEN}"
  cat <<'EOF'
    _          _       __      __       __       
   (_)____   _| |     / /___ _/ /______/ /_      
  / / ___/  (_) | /| / / __ `/ __/ ___/ __ \     
 / (__  )  _  | |/ |/ / /_/ / /_/ /__/ / / /     
/_/____/  (_) |__/|__/\__,_/\__/\___/_/ /_/      
EOF
  echo -e "${NC}\n"
}

log() { echo -e "${GREEN}[$(date +'%F %T')]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[$(date +'%F %T')] $*${NC}"; }
log_error() { echo -e "${RED}[$(date +'%F %T')] $*${NC}"; }

DOMAIN_REGEX='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+'


extract_domain() {
  local s="$1"
  s="${s#http://}"
  s="${s#https://}"
  s="${s%%/*}"
  s="${s%%:*}"
  s="${s#.}"
  echo "$s"
}

clear
show_banner

while true; do
  read -erp "Enter domain or URL (e.g., https://isssh.ir): " INPUT
  [[ -z "$INPUT" ]] && { log_error "Input cannot be empty."; continue; }

  DOMAIN="$(extract_domain "$INPUT")"
  if [[ -z "$DOMAIN" ]] || [[ ! "$DOMAIN" =~ $DOMAIN_REGEX ]]; then
    log_error "Invalid domain or URL."
    continue
  fi
  break
done

SEARCH_DIRS=("/www/wwwlogs" "/var/log/httpd/domains")
LOGFILE=""
USED_DIR=""

for dir in "${SEARCH_DIRS[@]}"; do
  for f in \
    "$dir/${DOMAIN}-error_log" \
    "$dir/${DOMAIN}.error.log" \
    "$dir/${DOMAIN}_ols.error_log" \
    "$dir/${DOMAIN}.log"; do
    if [ -f "$f" ]; then
      LOGFILE="$f"
      USED_DIR="$dir"
      break
    fi
  done
  [ -n "$LOGFILE" ] && break
done

if [ -z "$LOGFILE" ]; then
  log_error "No log file found for domain: $DOMAIN"
  log_warning "Checked in: ${SEARCH_DIRS[*]}"
  exit 1
fi

log "Monitoring: $LOGFILE"
echo -e "${BLUE}--------------------------------------------------${NC}"

trap "log_warning 'Stopped monitoring.'; exit" SIGINT


highlight() {
  local line="$1"
  line=$(echo "$line" \
    | sed -e "s/error/${RED}ERROR${NC}/Ig" \
          -e "s/warning/${YELLOW}WARNING${NC}/Ig" \
          -e "s/critical/${RED}CRITICAL${NC}/Ig")
  echo -e "$line"
}


parse_modsec() {
  local line="$1"

  RULE_ID=$(echo "$line" | grep -oP '\[id "\K[0-9]+')
  MSG=$(echo "$line" | grep -oP '\[msg "\K[^"]+')
  SEVERITY=$(echo "$line" | grep -oP '\[severity "\K[^"]+')
  TARGET=$(echo "$line" | grep -oP 'at \K[^ ]+')
  URI=$(echo "$line" | grep -oP '\[uri "\K[^"]+')
  FILE=$(echo "$line" | grep -oP '\[file "\K[^"]+' | awk -F/ '{print $NF}')
  LINE_NO=$(echo "$line" | grep -oP '\[line "\K[0-9]+')

  echo -e "${RED}[MODSECURITY DETECTED]${NC}"
  echo -e "${CYAN}Rule ID     :${NC} ${RULE_ID:-N/A}"
  echo -e "${CYAN}Target      :${NC} ${TARGET:-N/A}"
  echo -e "${CYAN}URI         :${NC} ${URI:-N/A}"
  echo -e "${CYAN}Message     :${NC} ${MSG:-N/A}"
  echo -e "${CYAN}Severity    :${NC} ${SEVERITY:-N/A}"
  echo -e "${CYAN}Rule File   :${NC} ${FILE:-N/A}:${LINE_NO:-?}"
}


tail -n 0 -f "$LOGFILE" | while read -r LINE; do
  TS=$(date +"%Y-%m-%d %H:%M:%S")
  echo -e "${GREEN}[$TS]${NC}"

  if echo "$LINE" | grep -qi "ModSecurity"; then
    parse_modsec "$LINE"
  else
    highlight "$LINE"
  fi

  echo -e "${BLUE}-------------------------------${NC}"
done
