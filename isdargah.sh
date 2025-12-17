#!/usr/bin/env bash

clear

GREEN="\e[32m"
RESET="\e[0m"

COL_NAME=20
COL_DOMAIN=25
COL_CODE=10
COL_STATUS=22

printf "%-${COL_NAME}s | %-${COL_DOMAIN}s | %-${COL_CODE}s | %-${COL_STATUS}s\n" \
"Name" "Domain" "HTTP Code" "HTTP Status"
printf "%0.s-" {1..90}
echo

gateways=(
  "Asan_Pardakht asan.shaparak.ir"
  "Refah_Bank ref.sayancard.ir"
  "Ghesta api.ghesta.ir"
  "OmidPay say.shaparak.ir"
  "Zarinpal payment.zarinpal.com"
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
    301|302|303|307|308) echo "SUCCESS (REDIRECT)" ;;
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

  http_code=$(curl -o /dev/null -s -w "%{http_code}" \
    --connect-timeout 3 --max-time 5 \
    "https://$domain")

  http_status=$(http_status_text "$http_code")

  printf -v name_plain "%-${COL_NAME}s" "$name"

  if [[ "$http_code" =~ ^2|^3 ]]; then
    name_display="${GREEN}${name_plain}${RESET}"
  else
    name_display="$name_plain"
  fi

  printf "%b | %-${COL_DOMAIN}s | %-${COL_CODE}s | %-${COL_STATUS}s\n" \
    "$name_display" "$domain" "$http_code" "$http_status"
done

echo
echo "Reminder:"
echo "If a payment gateway is not accessible, you can whitelist your server IP using the following page:"
echo "https://dargah.isvip.ir"
echo
echo "After whitelisting, add the contents of the following URL to your /etc/hosts file:"
echo "https://raw.isssh.ir/dargah-hosts.txt"
echo
echo "Note:"
echo "On shared hosting servers, the default sec-check configuration usually adds these entries automatically."
