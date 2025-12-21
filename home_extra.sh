#!/usr/bin/env bash

# Detect the control panel
if [ -d /var/cpanel ]; then
    CONTROL_PANEL="cpanel"
    USERS_DIR="/var/cpanel/users"
elif [ -d /usr/local/directadmin ]; then
    CONTROL_PANEL="directadmin"
    USERS_DIR="/usr/local/directadmin/data/users"
else
    echo "Neither cPanel nor DirectAdmin is detected."
    exit 1
fi

# Prepare lists
find /home -maxdepth 1 -type d -printf "%f\n" | sort > /tmp/home_dirs.txt
ls -1 $USERS_DIR | sort > /tmp/control_panel_users.txt

# Print header
printf "%-20s %-30s %10s %10s\n" "NAME" "PATH" "SIZE" "TYPE"

# Find and print extra directories
comm -23 /tmp/home_dirs.txt /tmp/control_panel_users.txt | while read user; do
    size=$(du -sh "/home/$user" 2>/dev/null | cut -f1)
    printf "%-20s %-30s %10s %10s\n" "$user" "/home/$user" "$size" "directory"
done

# Find and print all files in /home
find /home -maxdepth 1 -type f -printf "%f\n" | sort | while read file; do
    size=$(du -sh "/home/$file" 2>/dev/null | cut -f1)
    printf "%-20s %-30s %10s %10s\n" "$file" "/home/$file" "$size" "file"
done

# Print total active users
echo "Total active users: $(wc -l < /tmp/control_panel_users.txt)"

# Clean up temporary files
rm /tmp/{home_dirs.txt,control_panel_users.txt}