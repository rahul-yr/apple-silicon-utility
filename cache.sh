#!/bin/bash

MODE="$1"
TARGET="$2"

###############################################
# Full Disk Access Check
###############################################
check_fda() {
    local TEST="$HOME/Library/Calendars"
    if [ ! -r "$TEST" ]; then
        echo "⚠️  Full Disk Access NOT enabled. Caches may not fully delete."
        echo "Enable for Terminal:"
        echo "System Settings → Privacy & Security → Full Disk Access"
        echo ""
    fi
}
check_fda


###############################################
# Convert bytes to human readable
###############################################
human() {
    awk '
    function human(x){
        s="B KB MB GB TB PB";
        for(a=split(s,ar); x>=1024 && a<6; x/=1024) a++;
        return sprintf("%.2f %s", x, ar[a])
    }
    {print human($0)}'
}


###############################################
# Get installed app bundle IDs
###############################################
get_bundle_ids() {
    local NAME="$1"
    local RESULTS=()

    find /Applications "$HOME/Applications" -maxdepth 3 -name "*.app" -print0 2>/dev/null |
    while IFS= read -r -d '' APP; do
        BID=$(mdls -name kMDItemCFBundleIdentifier "$APP" 2>/dev/null | awk -F'"' '{print $2}')
        if [[ "$BID" != "" ]]; then
            if [[ "$NAME" == "" || "$APP" =~ "$NAME".*\.app ]]; then
                RESULTS+=("$BID")
            fi
        fi
    done

    echo "${RESULTS[@]}"
}


###############################################
# Find cache folders safely (NULL-delimited)
###############################################
find_cache_paths() {
    local BID="$1"
    local NAME_PART="${BID##*.}"
    local MATCHES=()

    # ~/Library/Caches/<bundle>
    if [ -d "$HOME/Library/Caches/$BID" ]; then
        MATCHES+=("$HOME/Library/Caches/$BID")
    fi

    # ~/Library/Caches/* name-based
    find "$HOME/Library/Caches" -maxdepth 1 -iname "*$NAME_PART*" -print0 2>/dev/null |
    while IFS= read -r -d '' p; do
        MATCHES+=("$p")
    done

    # ~/Library/Application Support/**/Cache*
    find "$HOME/Library/Application Support" -type d -iname "Cache*" -maxdepth 5 -print0 2>/dev/null |
    while IFS= read -r -d '' p; do
        if [[ "$p" =~ $NAME_PART ]]; then
            MATCHES+=("$p")
        fi
    done

    # /private/var/folders
    find /private/var/folders -type d -iname "$BID*" -print0 2>/dev/null |
    while IFS= read -r -d '' p; do
        MATCHES+=("$p")
    done

    # Electron/Chrome style caches
    find "$HOME/Library/Application Support" -type d \
        \( -iname "GPUCache" -o -iname "ShaderCache" -o -iname "Code Cache" \) \
        -print0 2>/dev/null |
    while IFS= read -r -d '' p; do
        if [[ "$p" =~ $NAME_PART ]]; then
            MATCHES+=("$p")
        fi
    done

    printf "%s\n" "${MATCHES[@]}" | awk '!seen[$0]++'
}


###############################################
# DRY RUN cache scan
###############################################
dry_cache() {
    local TARGET_APP="$1"

    BIDS=($(get_bundle_ids "$TARGET_APP"))
    if [ ${#BIDS[@]} -eq 0 ]; then
        echo "❌ No installed app found matching: $TARGET_APP"
        exit 1
    fi

    echo "------------------------------------------------------"
    echo " DRY RUN — Cache folders for: $TARGET_APP"
    echo "------------------------------------------------------"
    echo ""

    TOTAL=0

    for BID in "${BIDS[@]}"; do
        echo "== Caches for: $BID =="

        PATHS=($(find_cache_paths "$BID"))

        for P in "${PATHS[@]}"; do
            BYTES=$(du -sk "$P" 2>/dev/null | awk '{print $1 * 1024}')
            HSIZE=$(echo "$BYTES" | human)
            TOTAL=$((TOTAL + BYTES))
            echo "[FOUND] $P ($HSIZE)"
        done

        echo ""
    done

    echo "------------------------------------------------------"
    echo " Total reclaimable: $(echo "$TOTAL" | human)"
    echo "------------------------------------------------------"
}


###############################################
# CLEAR (interactive delete)
###############################################
clear_cache() {
    local TARGET_APP="$1"

    BIDS=($(get_bundle_ids "$TARGET_APP"))
    if [ ${#BIDS[@]} -eq 0 ]; then
        echo "❌ No installed app found matching: $TARGET_APP"
        exit 1
    fi

    echo "------------------------------------------------------"
    echo " Interactive CACHE CLEAN for: $TARGET_APP"
    echo "------------------------------------------------------"
    echo ""

    for BID in "${BIDS[@]}"; do
        echo "== Caches for: $BID =="

        PATHS=($(find_cache_paths "$BID"))

        for P in "${PATHS[@]}"; do
            HSIZE=$(du -sh "$P" 2>/dev/null | awk '{print $1}')
            echo "[FOUND] $P ($HSIZE)"
            read -p "Delete this cache? (y/N): " CONFIRM

            case "$CONFIRM" in
                y|Y)
                    echo "[DELETING] $P"
                    /usr/bin/sudo /bin/rm -rf "$P"
                    ;;
                *)
                    echo "[SKIPPED]"
                    ;;
            esac

            echo ""
        done
    done

    echo "------------------------------------------------------"
    echo " Cache Cleanup Complete"
    echo "------------------------------------------------------"
}


###############################################
# DRY CACHE ALL
###############################################
dry_cache_all() {
    APPS=($(get_bundle_ids ""))

    TOTAL=0

    for BID in "${APPS[@]}"; do
        echo "== Caches for: $BID =="

        PATHS=($(find_cache_paths "$BID"))

        for P in "${PATHS[@]}"; do
            BYTES=$(du -sk "$P" 2>/dev/null | awk '{print $1 * 1024}')
            HSIZE=$(echo "$BYTES" | human)
            TOTAL=$((TOTAL + BYTES))
            echo "[FOUND] $P ($HSIZE)"
        done
        echo ""
    done

    echo "------------------------------------------------------"
    echo " Total reclaimable from ALL apps: $(echo "$TOTAL" | human)"
    echo "------------------------------------------------------"
}


###############################################
# CLEAR CACHE ALL
###############################################
clear_cache_all() {
    APPS=($(get_bundle_ids ""))

    for BID in "${APPS[@]}"; do
        echo "== Caches for: $BID =="

        PATHS=($(find_cache_paths "$BID"))

        for P in "${PATHS[@]}"; do
            HSIZE=$(du -sh "$P" 2>/dev/null | awk '{print $1}')
            echo "[FOUND] $P ($HSIZE)"
            read -p "Delete? (y/N): " CONFIRM

            case "$CONFIRM" in
                y|Y) /usr/bin/sudo /bin/rm -rf "$P"; echo "[DELETED]";;
                *) echo "[SKIPPED]";;
            esac
            echo ""
        done
    done
}


###############################################
# USAGE
###############################################
usage() {
    echo "Usage:"
    echo "  $0 --dry-cache <AppName>       # Show what cache can be removed"
    echo "  $0 --clear-cache <AppName>     # Delete app cache (interactive)"
    echo "  $0 --dry-cache-all             # Show all caches for all apps"
    echo "  $0 --clear-cache-all           # Interactive cleanup for all apps"
    exit 1
}



###############################################
# MODE HANDLER
###############################################
case "$MODE" in
    --dry-cache)
        [ -z "$TARGET" ] && usage
        dry_cache "$TARGET"
        ;;
    --clear-cache)
        [ -z "$TARGET" ] && usage
        clear_cache "$TARGET"
        ;;
    --dry-cache-all)
        dry_cache_all
        ;;
    --clear-cache-all)
        clear_cache_all
        ;;
    *)
        usage
        ;;
esac
