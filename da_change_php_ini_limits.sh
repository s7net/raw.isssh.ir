#!/bin/bash

declare -A CONFIGS=(
    [1]="256M:3000:32M:32M:60:60"
    [2]="512M:6000:64M:64M:120:120"
    [3]="1024M:10000:128M:128M:180:180"
    [4]="1536M:20000:256M:256M:240:240"
    [5]="2048M:30000:512M:512M:300:300"
)
PHP_LIST=""
LEVEL="0"
DEFAULT_LEVEL_0="1024M:10000:128M:128M:180:180"

print_separator() {
    printf '=%.0s' {1..60}; echo
}

print_status() {
    local status=$1
    local message=$2
    if [[ "$status" == "OK" ]]; then
        echo "  [ OK ] $message"
    else
        echo " [ FAIL ] $message"
    fi
}

ask_value() {
    local text="$1"
    local default="$2"
    read -r -p "  >> $text ($default): " val
    echo "${val:-$default}"
}

while getopts "p:" opt; do
    case "$opt" in
        p) PHP_LIST="$OPTARG" ;;
        \?)
            echo "❌ Error: Invalid option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

if [[ -n "$1" ]]; then
    LEVEL="$1"
fi

print_separator
echo "🚀 PHP Configuration Updater (v1.0)"
print_separator

if [[ "$LEVEL" == "0" ]]; then
    echo "ℹ️  Mode: Interactive (Level 0)"
    echo "Please define your custom settings:"
    
    IFS=':' read -r memory_limit max_input_vars post_max_size upload_max_filesize max_execution_time max_input_time <<< "$DEFAULT_LEVEL_0"

    memory_limit=$(ask_value "memory_limit" "$memory_limit")
    max_input_vars=$(ask_value "max_input_vars" "$max_input_vars")
    post_max_size=$(ask_value "post_max_size" "$post_max_size")
    upload_max_filesize=$(ask_value "upload_max_filesize" "$upload_max_filesize")
    max_execution_time=$(ask_value "max_execution_time" "$max_execution_time")
    max_input_time=$(ask_value "max_input_time" "$max_input_time")

elif [[ -n "${CONFIGS[$LEVEL]}" ]]; then
    echo "ℹ️  Mode: Preset (Level ${LEVEL})"
    IFS=':' read -r memory_limit max_input_vars post_max_size upload_max_filesize max_execution_time max_input_time <<< "${CONFIGS[$LEVEL]}"
else
    echo "❌ Invalid level '${LEVEL}'. Only 0 to 5 are allowed."
    exit 1
fi

inis=()

if [[ -n "$PHP_LIST" ]]; then
    IFS=',' read -r -a versions <<< "$PHP_LIST"
    for v in "${versions[@]}"; do
        ini="/usr/local/${v}/lib/php.ini"
        if [[ -f "$ini" ]]; then
            inis+=("$ini")
        fi
    done
else
    for ini in /usr/local/php*/lib/php.ini; do
        [[ -f "$ini" ]] && inis+=("$ini")
    done
fi

if [[ "${#inis[@]}" -eq 0 ]]; then
    echo "❌ No valid php.ini files found. Exiting."
    exit 1
fi

print_separator
echo "✅ Selected Configuration:"
echo "  memory_limit      = ${memory_limit}"
echo "  max_input_vars    = ${max_input_vars}"
echo "  post_max_size     = ${post_max_size}"
echo "  upload_max_filesize = ${upload_max_filesize}"
echo "  max_execution_time  = ${max_execution_time}"
echo "  max_input_time    = ${max_input_time}"
print_separator

echo "🛠️ Applying settings to ${#inis[@]} file(s)..."

for ini in "${inis[@]}"; do
    ver="$(basename "$(dirname "$(dirname "$ini")")")"

    backup_file="${ini}.bak-$(date +%F-%H%M%S)"
    cp "$ini" "$backup_file"
    echo "  -> Processing ${ver} ($ini)"
    echo "     Backup created: ${backup_file}"

    sed -i -E '/^[[:space:]]*(;)?(memory_limit|max_input_vars|post_max_size|upload_max_filesize|max_execution_time|max_input_time)[[:space:]]*=/d' "$ini"

    printf '\n%s\n' \
    "; --- Added by PHP Configuration Updater ---" \
    "memory_limit = ${memory_limit}" \
    "max_input_vars = ${max_input_vars}" \
    "post_max_size = ${post_max_size}" \
    "upload_max_filesize = ${upload_max_filesize}" \
    "max_execution_time = ${max_execution_time}" \
    "max_input_time = ${max_input_time}" >> "$ini"

    ok=1
    grep -Eq "^[[:space:]]*memory_limit[[:space:]]*=[[:space:]]*${memory_limit}[[:space:]]*$" "$ini" || ok=0
    grep -Eq "^[[:space:]]*max_input_vars[[:space:]]*=[[:space:]]*${max_input_vars}[[:space:]]*$" "$ini" || ok=0
    grep -Eq "^[[:space:]]*post_max_size[[:space:]]*=[[:space:]]*${post_max_size}[[:space:]]*$" "$ini" || ok=0
    grep -Eq "^[[:space:]]*upload_max_filesize[[:space:]]*=[[:space:]]*${upload_max_filesize}[[:space:]]*$" "$ini" || ok=0
    grep -Eq "^[[:space:]]*max_execution_time[[:space:]]*=[[:space:]]*${max_execution_time}[[:space:]]*$" "$ini" || ok=0
    grep -Eq "^[[:space:]]*max_input_time[[:space:]]*=[[:space:]]*${max_input_time}[[:space:]]*$" "$ini" || ok=0

    if [[ "$ok" -eq 1 ]]; then
        print_status "OK" "${ver}: Settings applied successfully."
    else
        print_status "FAIL" "${ver}: Error applying settings. Please check ${ini}."
    fi
done

print_separator

echo "⚙️ Executing build rewrite_confs command..."
da build rewrite_confs
print_status "OK" "Command completed."

print_separator
echo "✨ PHP settings update completed successfully!"
print_separator
