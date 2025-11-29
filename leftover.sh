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
        echo "Enable in: System Settings → Privacy & Security → Full Disk Access"
        echo ""
        FDA_ENABLED=false
    else
        FDA_ENABLED=true
    fi
}
check_full_disk_access

###########################################
# DIRECTORIES TO SCAN
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
    "/Library/Application Support"
    "/Library/Caches"
    "/Library/LaunchAgents"
    "/Library/LaunchDaemons"
    "/private/var/folders"
)

###########################################
# SKIP APPLE PATHS
###########################################
is_apple_path() {
    [[ "$1" == *"/com.apple/"* ]] && return 0
    [[ "$1" == com.apple.* ]] && return 0
    [[ "$1" == group.com.apple* ]] && return 0
    return 1
}

###########################################
# VALID BUNDLE-ID CHECK (STRICT)
###########################################
is_valid_bundleid_folder() {
    local NAME="$1"

    # Exclusions (false positives)
    [[ "$NAME" == *"ShipIt"* ]] && return 1
    [[ "$NAME" == *"helper"* ]] && return 1
    [[ "$NAME" == *"CloudKit"* ]] && return 1
    [[ "$NAME" == *"Telemetry"* ]] && return 1
    [[ "$NAME" == *"code_sign_clone"* ]] && return 1
    [[ "$NAME" == *"="* ]] && return 1

    # SavedState cleanup (Option A)
    if [[ "$NAME" == com.*.savedState ]]; then
        return 0
    fi

    # Canonical bundle ID regex
    if [[ "$NAME" =~ ^(com|group)\.[a-zA-Z0-9\-]+\.[a-zA-Z0-9\-]+$ ]]; then
        return 0
    fi

    return 1
}

###########################################
# PER-APP CLEANUP
###########################################
per_app_cleanup() {
    local TARGET_APP="$1"
    local DELETE_MODE="$2"
    local FOUND_ITEMS=()

    echo "Searching for leftover files related to: $TARGET_APP"
    echo ""

    for DIR in "${SCAN_DIRS[@]}"; do
        if [ -d "$DIR" ]; then

            MATCHES=$(find "$DIR" -maxdepth 5 -iname "*$TARGET_APP*" ! -path "*com.apple*" 2>/dev/null)

            if [ -n "$MATCHES" ]; then
                echo "---- In $DIR ----"
                while IFS= read -r ITEM; do
                    FOUND_ITEMS+=("$ITEM")
                    echo "[FOUND] $ITEM"
                done <<< "$MATCHES"
                echo ""
            fi
        fi
    done

    if [ "$DELETE_MODE" == "dry" ]; then
        echo "==================================================="
        echo " DRY RUN COMPLETE — No files deleted."
        echo "==================================================="
        return
    fi

    echo "Deleting leftover files..."
    for ITEM in "${FOUND_ITEMS[@]}"; do
        echo "[DELETE] $ITEM"
        /usr/bin/sudo /bin/rm -rf "$ITEM"
    done

    if [ "$DELETE_MODE" == "delete-app" ]; then
        APP_PATH="/Applications/$TARGET_APP.app"
        USER_APP_PATH="$HOME/Applications/$TARGET_APP.app"

        if [ -d "$APP_PATH" ]; then
            echo "[DELETE APP] $APP_PATH"
            /usr/bin/sudo /bin/rm -rf "$APP_PATH"
        fi

        if [ -d "$USER_APP_PATH" ]; then
            echo "[DELETE APP] $USER_APP_PATH"
            /usr/bin/sudo /bin/rm -rf "$USER_APP_PATH"
        fi
    fi

    echo ""
    echo "==================================================="
    echo " Cleanup completed for: $TARGET_APP"
    echo "==================================================="
}

###########################################
# GLOBAL CLEANUP (--all / --all-delete)
###########################################
global_cleanup() {

    echo "Scanning installed applications (reading bundle identifiers)..."
    echo ""

    INSTALLED_BUNDLES=()

    while IFS= read -r APP; do
        BID=$(mdls -name kMDItemCFBundleIdentifier "$APP" 2>/dev/null | awk -F'"' '{print $2}')

        if [[ "$BID" != "" ]]; then
            INSTALLED_BUNDLES+=("$BID")
            echo "Installed: $BID"
        fi
    done < <(find /Applications ~/Applications -name "*.app" -maxdepth 3)

    echo ""
    echo "==================================================="
    echo " Searching for orphaned leftover data"
    echo "==================================================="
    echo ""

    ORPHANS=()

    for DIR in "${SCAN_DIRS[@]}"; do
        if [ -d "$DIR" ]; then

            MATCHES=$(find "$DIR" -maxdepth 5 -type d ! -path "*com.apple*" 2>/dev/null)

            while IFS= read -r ITEM; do

                NAME=$(basename "$ITEM")

                # Skip anything not bundle-ID style
                if ! is_valid_bundleid_folder "$NAME"; then
                    continue
                fi

                # Compare with installed bundle-IDs
                MATCHED=false
                for BID in "${INSTALLED_BUNDLES[@]}"; do

                    # Exact match
                    if [[ "$NAME" == "$BID" ]]; then
                        MATCHED=true
                        break
                    fi

                    # Group container match
                    if [[ "$NAME" == group.*"$BID"* ]]; then
                        MATCHED=true
                        break
                    fi

                done

                if [ "$MATCHED" = false ]; then
                    echo "[ORPHAN] $ITEM"
                    ORPHANS+=("$ITEM")
                fi

            done <<< "$MATCHES"

        fi
    done

    ###################################################
    # Dry run mode ( --all )
    ###################################################
    if [ "$MODE" == "--all" ]; then
        echo ""
        echo "==================================================="
        echo " GLOBAL DRY RUN COMPLETE — No files deleted."
        echo "==================================================="
        exit 0
    fi

    ###################################################
    # Interactive delete mode ( --all-delete )
    ###################################################
    echo ""
    echo "Interactive deletion mode — confirm each item:"
    echo ""

    for ITEM in "${ORPHANS[@]}"; do
        echo "[ORPHAN] $ITEM"
        read -p "Delete this folder? (y/N): " CONFIRM

        case "$CONFIRM" in
            y|Y)
                echo "[DELETING] $ITEM"
                /usr/bin/sudo /bin/rm -rf "$ITEM"
                ;;
            *)
                echo "[SKIPPED] $ITEM"
                ;;
        esac

        echo ""
    done

    echo ""
    echo "==================================================="
    echo " GLOBAL INTERACTIVE CLEANUP COMPLETE"
    echo "==================================================="
}

###########################################
# MODE HANDLER (STRICT & SAFE)
###########################################

if [ -z "$APPNAME" ]; then
    echo "Usage:"
    echo "  $0 <AppName>                 # Dry run"
    echo "  $0 <AppName> --delete        # Delete leftovers"
    echo "  $0 <AppName> --delete-app    # Delete app + leftovers"
    echo "  $0 --all                     # Global orphan scan"
    echo "  $0 --all-delete              # Interactive orphan delete"
    exit 1
fi

if [ "$APPNAME" == "--all" ]; then
    MODE="--all"
    global_cleanup
    exit 0
fi

if [ "$APPNAME" == "--all-delete" ]; then
    MODE="--all-delete"
    global_cleanup
    exit 0
fi

case "$MODE" in
    "")
        per_app_cleanup "$APPNAME" dry
        ;;
    "--delete")
        per_app_cleanup "$APPNAME" delete
        ;;
    "--delete-app")
        per_app_cleanup "$APPNAME" delete-app
        ;;
    *)
        echo "Unknown mode: $MODE"
        ;;
esac
