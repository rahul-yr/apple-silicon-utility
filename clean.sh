#!/bin/bash

APPNAME="$1"
MODE="$2"

###########################################
# Full Disk Access Check
###########################################
check_full_disk_access() {
    TESTDIR="$HOME/Library/Calendars"
    if [ ! -r "$TESTDIR" ]; then
        echo "⚠️  Full Disk Access NOT enabled. Some items may not delete."
        echo ""
        echo "Enable it here:"
        echo "System Settings → Privacy & Security → Full Disk Access"
        echo ""
        FDA_ENABLED=false
    else
        FDA_ENABLED=true
    fi
}

check_full_disk_access

###########################################
# Input validation
###########################################

if [ -z "$APPNAME" ]; then
    echo "Usage: $0 <AppName> [--delete | --delete-app]"
    exit 1
fi

echo "==================================================="
echo "        macOS Application Cleanup Utility"
echo "---------------------------------------------------"
echo " App Name : $APPNAME"
echo " Mode     : ${MODE:-DRY RUN}"
echo " FDA      : ${FDA_ENABLED}"
echo "==================================================="
echo ""

###########################################
# Directories to scan
###########################################

SCAN_DIRS=(
    "$HOME/Library/Application Support"
    "$HOME/Library/Caches"
    "$HOME/Library/Containers"
    "$HOME/Library/Group Containers"
    "$HOME/Library/Saved Application State"
    "$HOME/Library/Preferences"
    "$HOME/Library/Preferences/ByHost"
    "$HOME/Library/Logs"
    "$HOME/Library/LaunchAgents"
    "/private/var/folders"
)

###########################################
# Find all leftover paths (no com.apple)
###########################################

FOUND_PATHS=()

echo "Searching for leftover files related to: $APPNAME"
echo ""

for DIR in "${SCAN_DIRS[@]}"; do
    if [ -d "$DIR" ]; then
        # Filter out com.apple COMPLETELY
        MATCHES=$(find "$DIR" -maxdepth 3 -iname "*$APPNAME*" ! -path "*com.apple*" 2>/dev/null)

        if [ -n "$MATCHES" ]; then
            echo "---- In $DIR ----"
            while IFS= read -r ITEM; do
                FOUND_PATHS+=("$ITEM")
                echo "[FOUND] $ITEM"
            done <<< "$MATCHES"
            echo ""
        fi
    fi
done


###########################################
# DRY RUN summary (only show items)
###########################################

if [ "$MODE" != "--delete" ] && [ "$MODE" != "--delete-app" ]; then
    echo "==================================================="
    echo " DRY RUN COMPLETE — Nothing will be deleted."
    echo " Items shown above are the ONLY ones that can be deleted."
    echo "==================================================="
    exit 0
fi

###########################################
# DELETE leftover paths (ONLY what was shown)
###########################################

if [ "$MODE" == "--delete" ] || [ "$MODE" == "--delete-app" ]; then
    echo "Deleting leftover files..."
    echo ""

    for ITEM in "${FOUND_PATHS[@]}"; do
        echo "[DELETE] $ITEM"
        /usr/bin/sudo /bin/rm -rf "$ITEM"
    done
fi

###########################################
# DELETE APP BUNDLE ONLY IF --delete-app
###########################################

if [ "$MODE" == "--delete-app" ]; then
    APP_PATH="/Applications/$APPNAME.app"
    USER_APP_PATH="$HOME/Applications/$APPNAME.app"

    if [ -d "$APP_PATH" ]; then
        echo "[DELETE APP] $APP_PATH"
        /usr/bin/sudo /bin/rm -rf "$APP_PATH"
    fi

    if [ -d "$USER_APP_PATH" ]; then
        echo "[DELETE APP] $USER_APP_PATH"
        /usr/bin/sudo /bin/rm -rf "$USER_APP_PATH"
    fi
fi

###########################################
# DONE
###########################################

echo ""
echo "==================================================="
if [ "$MODE" == "--delete" ]; then
    echo " Leftover cleanup completed for: $APPNAME"
elif [ "$MODE" == "--delete-app" ]; then
    echo " Full uninstall completed for: $APPNAME"
fi
echo "==================================================="
