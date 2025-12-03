#!/usr/bin/env bash

clear

read -e -p "Please input path to file: " src

src="$(readlink -f -- "$src" 2>/dev/null || printf "%s\n" "$src")"
dst="/var/www/html"

if [[ ! -e "$src" ]]; then
    echo "Error: source not found: $src"
    exit 1
fi

if [[ ! -d "$dst" ]]; then
    echo "Error: destination dir not found: $dst"
    exit 2
fi

host="$(hostname -f)"
public_ip="$(curl -s ifconfig.me)"

base="$(basename -- "$src")"

if sudo cp -a -- "$src" "$dst/$base" && \
   sudo chown root:root -- "$dst/$base" && \
   sudo chmod 644 -- "$dst/$base"; then

    echo "✓ Done: $dst/$base (owner root:root, mode 644)"
    echo "→ Download via Hostname:  http://$host/$base"
    echo "→ Download via Public IP: http://$public_ip/$base"
else
    echo "Error: operation failed."
    exit 3
fi
