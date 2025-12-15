alias s="sudo ssh2"

if [ -n "$SSH_CONNECTION" ]; then
  clear
  cd ~

  USERNAME=$(whoami)
  HOSTNAME=$(hostname)

  # Gregorian date
  g_y=$(date +%Y)
  g_m=$(date +%m)
  g_d=$(date +%d)

  # Convert Gregorian to Jalali
  g_days_in_month=(0 31 28 31 30 31 30 31 31 30 31 30 31)
  if (( (g_y % 4 == 0 && g_y % 100 != 0) || (g_y % 400 == 0) )); then
    g_days_in_month[2]=29
  fi

  gy=$((g_y - 1600))
  gm=$((10#$g_m - 1))
  gd=$((10#$g_d - 1))

  g_day_no=$((365*gy + (gy+3)/4 - (gy+99)/100 + (gy+399)/400))
  for ((i=0; i<gm; i++)); do
    g_day_no=$((g_day_no + g_days_in_month[i+1]))
  done
  g_day_no=$((g_day_no + gd))

  j_day_no=$((g_day_no - 79))
  j_np=$((j_day_no / 12053))
  j_day_no=$((j_day_no % 12053))
  jy=$((979 + 33*j_np + 4*(j_day_no/1461)))
  j_day_no=$((j_day_no % 1461))
  if (( j_day_no >= 366 )); then
    jy=$((jy + (j_day_no - 1)/365))
    j_day_no=$(((j_day_no - 1)%365))
  fi

  j_days_in_month=(31 31 31 31 31 31 30 30 30 30 30 29)
  for ((i=0; i<12; i++)); do
    if ((j_day_no < j_days_in_month[i])); then
      jm=$((i + 1))
      jd=$((j_day_no + 1))
      break
    fi
    j_day_no=$((j_day_no - j_days_in_month[i]))
  done

  j_days_left_in_month=$((j_days_in_month[jm-1] - jd))
  j_week_of_month=$(( (jd + 6) / 7 ))

  # Salary day (1st of Jalali month)
  if (( jd == 1 )); then
    SALARY_MSG="💰 It's payday today! 😍"
  else
    SALARY_MSG="💵 $((j_days_in_month[jm-1] - jd + 1)) days left until payday"
  fi

  # System info
  UPTIME=$(uptime -p)
  LOAD=$(uptime | awk -F'load average:' '{print $2}')
  MEM=$(free -h | awk '/Mem:/ {print $3 "/" $2}')
  DISK=$(df -h / | awk 'NR==2 {print $3 "/" $2}')

  echo -e "\e[1;36m╔════════════════════════════════════════════════╗\e[0m"
  echo -e "\e[1;36m║  Welcome back, \e[1;33m$USERNAME\e[1;36m  on  \e[1;35m$HOSTNAME\e[1;36m  ║\e[0m"
  echo -e "\e[1;36m╚════════════════════════════════════════════════╝\e[0m"
  echo
  echo -e "📅  Jalali Date: \e[1;32m$jy/$jm/$jd\e[0m"
  echo -e "📆  Day $jd of ${j_days_in_month[jm-1]}  |  Week $j_week_of_month of this month"
  echo -e "⏳  $j_days_left_in_month days left in this month"
  echo -e "$SALARY_MSG"
  echo
  echo -e "💾  Memory: \e[1;34m$MEM\e[0m  |  Disk: \e[1;34m$DISK\e[0m"
  echo -e "🕐  Uptime: \e[1;32m$UPTIME\e[0m  |  Load:$LOAD"
  echo
  echo -e "\e[1;30m────────────────────────────────────────────────\e[0m"
  echo -e "🚀 Keep learning, keep growing, $USERNAME!"
  echo -e "\e[1;30m────────────────────────────────────────────────\e[0m"
  echo
fi

command_not_found_handle() {
    local cmd="$1"

    case "$cmd" in
        # lhNUM
        lh[0-9]*)
            num="${cmd#lh}"
            echo "→ connecting to lh${num}..."
            sudo ssh2 "lh${num}"
            ;;

        # bNUM → backupNUM
        b[0-9]*)
            num="${cmd#b}"
            echo "→ connecting to backup${num}..."
            sudo ssh2 "backup${num}"
            ;;

        # backupNUM
        backup[0-9]*)
            num="${cmd#backup}"
            echo "→ connecting to backup${num}..."
            sudo ssh2 "backup${num}"
            ;;

        # mNUM → mailserviceNUM
        m[0-9]*)
            num="${cmd#m}"
            echo "→ connecting to mailservice${num}..."
            sudo ssh2 "mailservice${num}"
            ;;

        # mailserviceNUM
        mailservice[0-9]*)
            num="${cmd#mailservice}"
            echo "→ connecting to mailservice${num}..."
            sudo ssh2 "mailservice${num}"
            ;;

        # sNUM → sonicNUM
        s[0-9]*)
            num="${cmd#s}"
            echo "→ connecting to sonic${num}..."
            sudo ssh2 "sonic${num}"
            ;;

        # sonicNUM
        sonic[0-9]*)
            num="${cmd#sonic}"
            echo "→ connecting to sonic${num}..."
            sudo ssh2 "sonic${num}"
            ;;

        # fallback
        *)
            echo "bash: $cmd: command not found"
            return 127
            ;;
    esac
}

isbashrc_update() {
  local url="https://raw.isssh.ir/.isbashrc"
  local tmp="${TMPDIR:-/tmp}/isbashrc.$$.$RANDOM"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$tmp"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp" "$url"
  else
    echo "ERROR: curl or wget not found"
    return 1
  fi
  local current_hash=""
  local new_hash=""
  if command -v sha256sum >/dev/null 2>&1; then
    current_hash="$(sha256sum ~/.isbashrc 2>/dev/null | awk '{print $1}')"
    new_hash="$(sha256sum "$tmp" 2>/dev/null | awk '{print $1}')"
  else
    current_hash="$(md5sum ~/.isbashrc 2>/dev/null | awk '{print $1}')"
    new_hash="$(md5sum "$tmp" 2>/dev/null | awk '{print $1}')"
  fi
  if [ -n "$current_hash" ] && [ -n "$new_hash" ] && [ "$current_hash" = "$new_hash" ]; then
    echo "Already up to date"
    rm -f "$tmp"
  else
    cp "$tmp" ~/.isbashrc
    rm -f "$tmp"
    echo "Updated ~/.isbashrc"
  fi
  local line='[ -f ~/.isbashrc ] && source ~/.isbashrc'
  if ! grep -Fq "$line" ~/.bashrc 2>/dev/null; then
    printf "\n%s\n" "$line" >> ~/.bashrc
    echo "Appended source line to ~/.bashrc"
  fi
}
alias isbashrc-update=isbashrc_update
