#!/usr/bin/env bash
# Restore DA backups to cPanel. by sh.rahimpour; V2 Jul 2025
# NOTE: Recommended for simple WordPress websites. Does not restore subdomains, parked domains, SSL certs, or FTP accounts.

GREEN='\033[0;32m'
RED='\033[0;31m'
CLEAR='\033[0m'

# Function to make space in terminal for better output 
space() {
    echo -e "\n==================================\n"
    sleep 1
}

# Function to display a message and exit
error_exit() {
    echo -e "${RED}$1${CLEAR}"
    exit 1
}

# Function to handle backup source
handle_backup_source() {
    echo -e "${GREEN}Processing backup source...${CLEAR}"

    # check if BACKUP_SOURCE is a local file inside user's home
    if [[ -f "/home/${USERNAME}/${BACKUP_SOURCE}" ]]; then
        BACKUP_NAME="$BACKUP_SOURCE"
        echo -e "${GREEN}Using local backup file: ${BACKUP_NAME}${CLEAR}"
    # check if BACKUP_SOURCE is a URL (http or https)
    elif [[ "$BACKUP_SOURCE" =~ ^https?:// ]]; then
        echo -e "${GREEN}Downloading backup from URL...${CLEAR}"
        wget --timeout=10 --tries=2 --no-check-certificate -O "/home/${USERNAME}/${BACKUP_NAME}" "${BACKUP_SOURCE}" || error_exit "Couldn't download ${BACKUP_NAME}. Aborting."
        echo -e "${GREEN}Backup downloaded successfully.${CLEAR}"
    else
        error_exit "Local backup file /home/${USERNAME}/${BACKUP_SOURCE} does not exist, and source is not a valid URL."
    fi
}


# Function to extract the backup
extract_backup() {
    echo -e "${GREEN}Extracting backup...${CLEAR}"

    # Detect file extension
    if [[ "$BACKUP_NAME" == *.tar.zst ]]; then
        tar -I zstd -xf "/home/${USERNAME}/${BACKUP_NAME}" -C "/home/${USERNAME}/" || error_exit "Couldn't extract ${BACKUP_NAME}. Aborting."
    elif [[ "$BACKUP_NAME" == *.tar.gz ]]; then
        tar -xf "/home/${USERNAME}/${BACKUP_NAME}" -C "/home/${USERNAME}/" || error_exit "Couldn't extract ${BACKUP_NAME}. Aborting."
    else
        error_exit "Unsupported backup format: $BACKUP_NAME"
    fi

    echo -e "${GREEN}Backup extracted successfully.${CLEAR}"
    space
}

# Function to move and restore public_html
restore_public_html() {
    echo -e "${GREEN}Restoring public_html...${CLEAR}"
    if [[ -d "/home/${USERNAME}/public_html" && "$(ls -A /home/${USERNAME}/public_html)" ]]; then
        echo -e "Cleaning public_html directory..."
        rm -rvf "/home/${USERNAME}/public_html/" || error_exit "Failed to clean public_html directory. Aborting."
    fi
    cp -a "/home/${USERNAME}/domains/${DOMAIN}/public_html/" "/home/${USERNAME}/public_html/" || error_exit "Failed to copy public_html files."
    chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/public_html/" || error_exit "Failed to set ownership for public_html."
    echo -e "${GREEN}public_html restored successfully.${CLEAR}"
    space
}

# Function to restore databases
restore_databases() {
    echo -e "${GREEN}Restoring databases...${CLEAR}"
    SQL_BACKUP_PATH="/home/${USERNAME}/backup"
    MAIN_WP_CONFIG_PATH=$(find /home/${USERNAME}/public_html -type f -name "wp-config.php" -print -quit)
    [[ -z "$MAIN_WP_CONFIG_PATH" ]] && error_exit "wp-config.php not found."

    # Extract main database details from wp-config.php
    MAIN_DB_NAME=$(awk -F"'" '/DB_NAME/ {print $4}' "$MAIN_WP_CONFIG_PATH")
    MAIN_DB_USER=$(awk -F"'" '/DB_USER/ {print $4}' "$MAIN_WP_CONFIG_PATH")
    MAIN_DB_PASS=$(awk -F"'" '/DB_PASSWORD/ {print $4}' "$MAIN_WP_CONFIG_PATH")

    # Extract the original prefix from MAIN_DB_NAME
    ORIGINAL_PREFIX=$(awk -F'_' '{print $1}' <<< "$MAIN_DB_NAME")

    # Update MAIN_DB_NAME and MAIN_DB_USER to match the new username prefix
    NEW_MAIN_DB_NAME="${USERNAME}_${MAIN_DB_NAME#*_}"
    NEW_MAIN_DB_USER="${USERNAME}_${MAIN_DB_USER#*_}"

    # If old and new usernames are different, update wp-config.php
    if [[ "$ORIGINAL_PREFIX" != "$USERNAME" ]]; then
        echo -e "${GREEN}Updating wp-config.php with new database credentials...${CLEAR}"
        sed -i "s/'DB_NAME', *'${MAIN_DB_NAME}'/'DB_NAME', '${NEW_MAIN_DB_NAME}'/" "$MAIN_WP_CONFIG_PATH"
        sed -i "s/'DB_USER', *'${MAIN_DB_USER}'/'DB_USER', '${NEW_MAIN_DB_USER}'/" "$MAIN_WP_CONFIG_PATH"
        echo -e "${GREEN}wp-config.php updated: DB_NAME=${NEW_MAIN_DB_NAME}, DB_USER=${NEW_MAIN_DB_USER}${CLEAR}"
    fi

    SQL_FILES=$(find "$SQL_BACKUP_PATH" -type f -name "*.sql")
    [[ -z "$SQL_FILES" ]] && error_exit "No SQL files found in $SQL_BACKUP_PATH."

    for SQL_FILE in $SQL_FILES; do
        # Extract original database name prefix from the filename
        OLD_DB_NAME=$(basename "$SQL_FILE" .sql)
        OLD_PREFIX=$(awk -F'_' '{print $1}' <<< "$OLD_DB_NAME")

        # Generate new database name with new username prefix
        DB_NAME="${USERNAME}_${OLD_DB_NAME#*_}"
        DB_USER="$DB_NAME"

        # Determine whether to use MAIN_DB_PASS or generate a new password
        if [[ "$DB_NAME" == "$NEW_MAIN_DB_NAME" ]]; then
            DB_PASS="$MAIN_DB_PASS"
        else
            DB_PASS=$(openssl rand -base64 12)
        fi

        # Replace old username prefix with new username prefix inside SQL file
        TEMP_SQL_FILE="/tmp/${DB_NAME}.sql"
        sed "s/\`${OLD_PREFIX}_/\`${USERNAME}_/g" "$SQL_FILE" > "$TEMP_SQL_FILE"

        # Create database (print only errors)
        uapi --user=$USERNAME Mysql create_database name="$DB_NAME" | awk '
        /errors/ {
            if ($2 != "~") {
                print "\033[31mDatabase creation error: " $0 "\033[0m"
                getline
                print "\033[31m" $0 "\033[0m"
            }
        }'

        # Create user (print only errors)
        uapi --user=$USERNAME Mysql create_user name="$DB_USER" password="$DB_PASS" | awk '
        /errors/ {
            if ($2 != "~") {
                print "\033[31mUser creation error: " $0 "\033[0m"
                getline
                print "\033[31m" $0 "\033[0m"
            }
        }'

        # Set privileges (print only errors)
        uapi --user=$USERNAME Mysql set_privileges_on_database user="$DB_USER" database="$DB_NAME" privileges="ALL PRIVILEGES" | awk '
        /errors/ {
            if ($2 != "~") {
                print "\033[31mPrivileges setting error: " $0 "\033[0m"
                getline
                print "\033[31m" $0 "\033[0m"
            }
        }'

        # Restore SQL file (print only errors)
        mysql "$DB_NAME" < "$TEMP_SQL_FILE" 2>/tmp/mysql_error.log
        if [[ -s /tmp/mysql_error.log ]]; then
            echo -e "\033[31mSQL Restore Error: $(cat /tmp/mysql_error.log)\033[0m"
        fi
        rm -f /tmp/mysql_error.log

        # Clean up temporary SQL file
        rm -f "$TEMP_SQL_FILE"
    done
    echo -e "${GREEN}Database restoration completed successfully.${CLEAR}"
}

# Function to restore emails
restore_email() {
    echo -e "\n${GREEN}Would you like to restore emails? (y/n)${CLEAR}"
    read -p "Your choice(y/n): " CHOICE
    case "$CHOICE" in
        y|Y|yes|Yes)
            echo -e "${GREEN}Restoring emails...${CLEAR}"
            echo -e "$USERNAME\n$DOMAIN" | bash <(curl -kL --progress-bar fuserver.ir/scripts/rmail.sh) || error_exit "Failed to restore emails."
            echo -e "${GREEN}Emails restored successfully.${CLEAR}"
            space
            ;;
        *)
            echo -e "${GREEN}Skipping email restoration.${CLEAR}"
            space
            ;;
    esac
}

# Function to clean up backup directories
cleanup_directories() {
    echo -e "${GREEN}Would you like to delete the backup directories (domains, imap, backup)? (y/n)${CLEAR}"
    read -p "Your choice: " CHOICE
    case "$CHOICE" in
        y|Y|yes|Yes)    
            echo -e "${GREEN}Deleting backup directories...${CLEAR}"
            rm -rf "/home/${USERNAME}/domains" "/home/${USERNAME}/imap" "/home/${USERNAME}/backup" || error_exit "Failed to delete backup directories."
            echo -e "${GREEN}Backup directories deleted successfully.${CLEAR}"
            ;;
        *)
            echo -e "${GREEN}Keeping backup directories.${CLEAR}"
            ;;
    esac
}

# Main script execution
main() {
    echo -e "${GREEN}***********************************${CLEAR}"
    echo -e "${GREEN}****DA to cPanel Restore Wizard****${CLEAR}"
    echo -e "${GREEN}************************************${CLEAR}"

    # Prompt for username and check existence
    read -p "Enter Username:       " USERNAME
    [[ ! -d /home/${USERNAME} ]] && error_exit "${USERNAME} doesn't exist on server. Aborting."

    read -p "Enter Main Domain:    " DOMAIN
    read -p "Enter Backup source (URL or local file name in /home/${USERNAME}/):  " BACKUP_SOURCE

    BACKUP_NAME=$(basename "${BACKUP_SOURCE}")

    handle_backup_source
    extract_backup
    restore_public_html
    restore_databases
    restore_email
    cleanup_directories

    echo -e "${GREEN}********************************${CLEAR}"
    echo -e "${GREEN}** Restore process completed. **${CLEAR}"
    echo -e "${GREEN}********************************${CLEAR}"
}

# Run the main function
main