#!/usr/bin/env bash

clear

GREEN="\e[32m"
RESET="\e[0m"

printf "%-20s | %-25s | %-8s | %-10s | %-20s\n" \
"Name" "Domain" "Ping" "HTTP Code" "HTTP Status"
printf "%0.s-" {1..95}
echo

gateways=(
  "Asan_Pardakht asan.shaparak.ir"
  "Refah_Bank ref.sayancard.ir"
  "Ghesta api.ghesta.ir"
  "OmidPay say.shaparak.ir"
  "Zarinpal www.zarinpal.com"
  "IranKish ikc.shaparak.ir"
  "BehPardakht bpm.shaparak.ir"
  "Parsian pec.shaparak.ir"
  "Saderat sepehr.shaparak.ir"
  "Sadad sadad.shaparak.ir"
  "Pasargad pep.shaparak.ir"
  "SamanKish sep.shaparak.ir"
  "Novin pna.shaparak.ir"
)

http_status_text() {
  case "$1" in
    2*) echo "SUCCESS" ;;
    301|302|307|308) echo "REDIRECT" ;;
    400) echo "BAD_REQUEST" ;;
    401) echo "UNAUTHORIZED" ;;
    403) echo "FORBIDDEN" ;;
    404) echo "NOT_FOUND" ;;
    408) echo "REQUEST_TIMEOUT" ;;
    429) echo "TOO_MANY_REQUESTS" ;;
    500) echo "INTERNAL_SERVER_ERROR" ;;
    502) echo "BAD_GATEWAY" ;;
    503) echo "SERVICE_UNAVAILABLE" ;;
    504) echo "GATEWAY_TIMEOUT" ;;
    000|"") echo "NO_RESPONSE" ;;
    *) echo "UNKNOWN_STATUS" ;;
  esac
}

for item in "${gateways[@]}"; do
  name=$(awk '{print $1}' <<< "$item")
  domain=$(awk '{print $2}' <<< "$item")

  ping -c 2 -W 1 "$domain" > /dev/null 2>&1 \
    && ping_status="✅" || ping_status="❌"

  http_code=$(curl -o /dev/null -s -w "%{http_code}" \
    --connect-timeout 3 --max-time 5 \
    "https://$domain")

  http_status=$(http_status_text "$http_code")

  if [[ "$http_code" =~ ^2 ]]; then
    name_display="${GREEN}${name}${RESET}"
  else
    name_display="$name"
  fi

  printf "%-20s | %-25s | %-8s | %-10s | %-20s\n" \
    "$name_display" "$domain" "$ping_status" "$http_code" "$http_status"
done
