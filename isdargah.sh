#!/usr/bin/env bash

clear

printf "%-20s | %-25s | %-8s | %-12s\n" "Name" "Domain" "Ping" "HTTP Code"
printf "%0.s-" {1..75}
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

for item in "${gateways[@]}"; do
  name=$(awk '{print $1}' <<< "$item")
  domain=$(awk '{print $2}' <<< "$item")

  # Ping check
  if ping -c 2 -W 1 "$domain" > /dev/null 2>&1; then
    ping_status="✅"
  else
    ping_status="❌"
  fi

  http_code=$(curl -o /dev/null -s -w "%{http_code}" \
    --connect-timeout 3 --max-time 5 \
    "https://$domain")

  if [[ "$http_code" == "000" ]]; then
    http_code="❌"
  fi

  printf "%-20s | %-25s | %-8s | %-12s\n" \
    "$name" "$domain" "$ping_status" "$http_code"
done
