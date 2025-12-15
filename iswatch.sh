#!/bin/bash

clear

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DOMAIN_REGEX='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$'

while true; do
    read -p "Enter domain (example: isssh.ir): " DOMAIN

    if [ -z "$DOMAIN" ]; then
        echo -e "${RED}Domain cannot be empty. Please try again.${NC}"
        continue
    fi

    if [[ ! "$DOMAIN" =~ $DOMAIN_REGEX ]]; then
        echo -e "${RED}Invalid domain format. Example of valid format: example.com${NC}"
        continue
    fi

    break
done

SEARCH_DIRS=(
    "/www/wwwlogs"
    "/var/log/httpd/domains"
)

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
    echo -e "${RED}No log file found for domain:${NC} $DOMAIN"
    echo -e "${YELLOW}Checked in:${NC} ${SEARCH_DIRS[*]}"
    echo -e "${YELLOW}You can run this to see available logs:${NC}"
    for d in "${SEARCH_DIRS[@]}"; do
        echo "  ls -l $d"
    done
    exit 1
fi

echo -e "${GREEN}Monitoring:${NC} $LOGFILE"
echo -e "${BLUE}--------------------------------------------------${NC}"

trap "echo -e '\n${YELLOW}Stopped monitoring.${NC}'; exit" SIGINT

highlight() {
    local line="$1"
    line=$(echo "$line" \
        | sed -e "s/error/${RED}ERROR${NC}/Ig" \
              -e "s/warning/${YELLOW}WARNING${NC}/Ig" \
              -e "s/critical/${RED}CRITICAL${NC}/Ig")
    echo -e "$line"
}

tail -n 0 -f "$LOGFILE" | while read LINE; do
    TS=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "${GREEN}[$TS]${NC}"
    highlight "$LINE"
    echo -e "${BLUE}-------------------------------${NC}"
done
