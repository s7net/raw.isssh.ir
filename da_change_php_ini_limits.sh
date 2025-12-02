#!/bin/bash

PHP_LIST=""

while getopts "p:" opt; do
    case "$opt" in
        p) PHP_LIST="$OPTARG" ;;
    esac
done
shift $((OPTIND-1))

LEVEL="${1:-0}"

ask_value() {
    local text="$1"
    local default="$2"
    read -p "$text ($default): " val
    echo "${val:-$default}"
}

if [[ "$LEVEL" = "0" ]]; then
    memory_limit=$(ask_value "memory_limit" "1024M")
    max_input_vars=$(ask_value "max_input_vars" "10000")
    post_max_size=$(ask_value "post_max_size" "128M")
    upload_max_filesize=$(ask_value "upload_max_filesize" "128M")
    max_execution_time=$(ask_value "max_execution_time" "180")
    max_input_time=$(ask_value "max_input_time" "180")
else
    case "$LEVEL" in
        1)
            memory_limit="256M"
            max_input_vars="3000"
            post_max_size="32M"
            upload_max_filesize="32M"
            max_execution_time="60"
            max_input_time="60"
            ;;
        2)
            memory_limit="512M"
            max_input_vars="6000"
            post_max_size="64M"
            upload_max_filesize="64M"
            max_execution_time="120"
            max_input_time="120"
            ;;
        3)
            memory_limit="1024M"
            max_input_vars="10000"
            post_max_size="128M"
            upload_max_filesize="128M"
            max_execution_time="180"
            max_input_time="180"
            ;;
        4)
            memory_limit="1536M"
            max_input_vars="20000"
            post_max_size="256M"
            upload_max_filesize="256M"
            max_execution_time="240"
            max_input_time="240"
            ;;
        5)
            memory_limit="2048M"
            max_input_vars="30000"
            post_max_size="512M"
            upload_max_filesize="512M"
            max_execution_time="300"
            max_input_time="300"
            ;;
        *)
            echo "Invalid level. Only 0 to 5 are allowed."
            exit 1
            ;;
    esac
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
    echo "No valid php.ini files found."
    exit 1
fi

echo "Selected configuration:"
echo "memory_limit = ${memory_limit}"
echo "max_input_vars = ${max_input_vars}"
echo "post_max_size = ${post_max_size}"
echo "upload_max_filesize = ${upload_max_filesize}"
echo "max_execution_time = ${max_execution_time}"
echo "max_input_time = ${max_input_time}"

printf '=%.0s' {1..60}
echo

for ini in "${inis[@]}"; do
    ver="$(basename "$(dirname "$(dirname "$ini")")")"

    cp "$ini" "${ini}.bak-$(date +%F-%H%M%S)"

    sed -i -E '/^(memory_limit|max_input_vars|post_max_size|upload_max_filesize|max_execution_time|max_input_time)[[:space:]]*=/d' "$ini"

    printf '%s\n' \
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
        echo "${ver}: Settings applied successfully"
    else
        echo "${ver}: Error applying settings"
    fi
done

printf '=%.0s' {1..60}
echo

da build rewrite_confs

echo "PHP settings update completed."
