#!/usr/bin/env bash

clear

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
    200) echo "OK" ;;
    201) echo "CREATED" ;;
    204) echo "NO_CONTENT" ;;
    301) echo "MOVED_PERMANENTLY" ;;
    302) echo "FOUND" ;;
    307) echo "TEMP_REDIRECT" ;;
    308) echo "PERM_REDIRECT" ;;
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

  printf "%-20s | %-25s | %-8s | %-10s | %-20s\n" \
    "$name" "$domain" "$ping_status" "$http_code" "$http_status"
done
