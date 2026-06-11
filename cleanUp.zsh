#!/bin/zsh
# Safe macOS home and developer cleanup.
# Targets macOS 26 and never runs the whole script as root.

set -u
setopt NULL_GLOB

SCRIPT_NAME="${0:t}"
DRY_RUN=false
ASSUME_YES=false
CLEAN_TRASH=false
CLEAN_LOGS=false
CLEAN_CORES=false
CLEAN_DEVELOPER=false
CLEAN_PACKAGES=false
CLEAN_BROWSER_CACHES=false
CLEAN_PRIVACY=false
CLEAN_DOCKER=false
CLEAN_SIMULATORS=false
DEVELOPER_DAYS=14
ARCHIVE_DAYS=90
LOG_DAYS=30
CACHE_DAYS=30
REMOVED=0
FAILED=0
SKIPPED=0

# MARK: - Usage
usage() {
    cat <<'EOF'
Usage: cleanUp.zsh [options]

Safe default cleanup:
  - home-root Finder metadata and crashed shell-history fragments
  - user crash reports older than 30 days

Options:
  -n, --dry-run          Show actions without deleting anything
  -y, --yes              Do not ask for confirmation
      --trash            Empty this user's Trash, including mounted volumes
      --logs             Remove user log files older than --log-days
      --cores            Remove system core dumps, requesting sudo if needed
      --developer        Remove stale Xcode DerivedData and archives
      --package-caches   Prune Homebrew, npm, pnpm, and Gradle caches
      --browser-caches   Remove browser cache files, never passwords/bookmarks
      --simulators       Delete only simulators unavailable to current Xcode
      --docker           Prune Docker objects unused for at least 30 days
      --privacy          Clear shell/Chrome history and browser login sessions
      --all-safe         Enable all options except --privacy and --docker
      --developer-days N Age for DerivedData cleanup (default: 14)
      --archive-days N   Age for Xcode archives (default: 90)
      --log-days N       Age for logs and crash reports (default: 30)
      --cache-days N     Age for package caches (default: 30)
  -h, --help             Show this help

Examples:
  ./cleanUp.zsh --dry-run --all-safe
  ./cleanUp.zsh --developer --package-caches
  ./cleanUp.zsh --privacy --yes
EOF
}

# MARK: - Output
section() {
    print
    print -r -- "── $1"
}

info() {
    print -r -- "   $1"
}

warn() {
    print -u2 -r -- "   Warning: $1"
}

# MARK: - Argument Validation
require_days() {
    local option="$1"
    local value="${2:-}"
    if [[ ! "$value" =~ '^[0-9]+$' ]] || (( value < 1 )); then
        print -u2 -r -- "${option} requires a positive integer."
        exit 2
    fi
}

while (( $# > 0 )); do
    case "$1" in
        -n|--dry-run) DRY_RUN=true ;;
        -y|--yes) ASSUME_YES=true ;;
        --trash) CLEAN_TRASH=true ;;
        --logs) CLEAN_LOGS=true ;;
        --cores) CLEAN_CORES=true ;;
        --developer) CLEAN_DEVELOPER=true ;;
        --package-caches) CLEAN_PACKAGES=true ;;
        --browser-caches) CLEAN_BROWSER_CACHES=true ;;
        --privacy) CLEAN_PRIVACY=true ;;
        --docker) CLEAN_DOCKER=true ;;
        --simulators) CLEAN_SIMULATORS=true ;;
        --all-safe)
            CLEAN_TRASH=true
            CLEAN_LOGS=true
            CLEAN_CORES=true
            CLEAN_DEVELOPER=true
            CLEAN_PACKAGES=true
            CLEAN_BROWSER_CACHES=true
            CLEAN_SIMULATORS=true
            ;;
        --developer-days)
            require_days "$1" "${2:-}"
            DEVELOPER_DAYS="$2"
            shift
            ;;
        --archive-days)
            require_days "$1" "${2:-}"
            ARCHIVE_DAYS="$2"
            shift
            ;;
        --log-days)
            require_days "$1" "${2:-}"
            LOG_DAYS="$2"
            shift
            ;;
        --cache-days)
            require_days "$1" "${2:-}"
            CACHE_DAYS="$2"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print -u2 -r -- "Unknown option: $1"
            usage
            exit 2
            ;;
    esac
    shift
done

# MARK: - Safety
if [[ "$(uname -s)" != "Darwin" ]]; then
    print -u2 -r -- "${SCRIPT_NAME} supports macOS only."
    exit 1
fi
if [[ -z "${HOME:-}" || "$HOME" == "/" || ! -d "$HOME" ]]; then
    print -u2 -r -- "Unsafe HOME value: ${HOME:-<unset>}"
    exit 1
fi
HOME_ROOT="${HOME:A}"
if (( EUID == 0 )); then
    print -u2 -r -- "Do not run this script with sudo. It requests elevation only when needed."
    exit 1
fi
if $CLEAN_PRIVACY; then
    warn "--privacy closes no applications and removes login/session state."
fi
if ! $DRY_RUN && ! $ASSUME_YES; then
    if [[ ! -t 0 ]]; then
        print -u2 -r -- "Non-interactive cleanup requires --yes or --dry-run."
        exit 2
    fi
    print -n -r -- "Run selected cleanup tasks? [y/N] "
    read -r reply
    [[ "$reply" == [yY] ]] || exit 0
fi

# MARK: - Removal Helpers
is_allowed_path() {
    local target="${1:A}"
    [[ "$target" == "$HOME_ROOT"/* || "$target" == /cores/core.* || "$target" == /Volumes/*/.Trashes/"$UID"/* ]]
}

remove_path() {
    local target="$1"
    local label="${2:-${target:t}}"
    [[ -e "$target" || -L "$target" ]] || return 0
    if ! is_allowed_path "$target"; then
        warn "Blocked path outside allowed cleanup roots: $target"
        ((SKIPPED++))
        return 1
    fi
    if $DRY_RUN; then
        print -r -- "   [dry-run] remove $label"
        ((REMOVED++))
        return 0
    fi
    if rm -rf -- "$target"; then
        print -r -- "   Removed $label"
        ((REMOVED++))
    else
        warn "Could not remove $target"
        ((FAILED++))
    fi
}

remove_old_files() {
    local root="$1"
    local days="$2"
    local label="$3"
    [[ -d "$root" ]] || return 0
    local target
    while IFS= read -r -d '' target; do
        remove_path "$target" "$label: ${target:t}"
    done < <(find "$root" -type f -mtime +"$days" -print0 2>/dev/null)
}

remove_old_directories() {
    local root="$1"
    local depth="$2"
    local days="$3"
    local name_pattern="$4"
    local label="$5"
    [[ -d "$root" ]] || return 0
    local target
    while IFS= read -r -d '' target; do
        remove_path "$target" "$label: ${target:t}"
    done < <(find "$root" -mindepth 1 -maxdepth "$depth" -type d -name "$name_pattern" -mtime +"$days" -print0 2>/dev/null)
}

run_command() {
    local label="$1"
    shift
    if $DRY_RUN; then
        print -r -- "   [dry-run] $label: ${(q+)@}"
        return 0
    fi
    info "$label"
    if "$@"; then
        ((REMOVED++))
    else
        warn "$label failed"
        ((FAILED++))
    fi
}

application_running() {
    local process_name="$1"
    pgrep -x "$process_name" >/dev/null 2>&1
}

# MARK: - Basic Home Cleanup
section "Home metadata"
for target in "$HOME"/.!*!.zsh_history(N) "$HOME"/._*(N) "$HOME"/.CFUserTextEncoding.*(N) "$HOME"/.*.sw[op](N); do
    remove_path "$target"
done
remove_path "$HOME/.DS_Store"

section "Old crash reports"
remove_old_files "$HOME/Library/Logs/DiagnosticReports" "$LOG_DAYS" "crash report"

if $CLEAN_LOGS; then
    section "Old user logs"
    remove_old_files "$HOME/Library/Logs" "$LOG_DAYS" "user log"
fi

if $CLEAN_CORES; then
    section "Core dumps"
    for target in /cores/core.*(N); do
        if [[ -w "$target" ]]; then
            remove_path "$target"
        elif $DRY_RUN; then
            info "[dry-run] sudo remove ${target:t}"
            ((REMOVED++))
        else
            run_command "Remove ${target:t}" sudo rm -f -- "$target"
        fi
    done
fi

# MARK: - Trash
if $CLEAN_TRASH; then
    section "Trash"
    for target in "$HOME/.Trash"/*(DN); do
        remove_path "$target" "Trash: ${target:t}"
    done
    for target in /Volumes/*/.Trashes/"$UID"/*(DN); do
        remove_path "$target" "volume Trash: ${target:t}"
    done
fi

# MARK: - Developer Data
if $CLEAN_DEVELOPER; then
    section "Xcode developer data"
    remove_old_directories "$HOME/Library/Developer/Xcode/DerivedData" 1 "$DEVELOPER_DAYS" "*" "DerivedData"
    remove_old_directories "$HOME/Library/Developer/Xcode/Archives" 2 "$ARCHIVE_DAYS" "*.xcarchive" "Xcode archive"
    remove_old_files "$HOME/Library/Developer/Xcode/DocumentationCache" "$CACHE_DAYS" "Xcode documentation cache"
fi

if $CLEAN_SIMULATORS; then
    section "Unavailable simulators"
    if command -v xcrun >/dev/null 2>&1; then
        run_command "Delete simulators unavailable to current Xcode" xcrun simctl delete unavailable
    else
        warn "xcrun is unavailable"
        ((SKIPPED++))
    fi
fi

# MARK: - Package Caches
if $CLEAN_PACKAGES; then
    section "Package manager caches"
    if command -v brew >/dev/null 2>&1; then
        if $DRY_RUN; then
            run_command "Homebrew cleanup preview" brew cleanup --dry-run --prune="$CACHE_DAYS"
        else
            run_command "Prune Homebrew downloads older than ${CACHE_DAYS} days" brew cleanup --prune="$CACHE_DAYS"
        fi
    fi
    if command -v npm >/dev/null 2>&1; then
        run_command "Verify and garbage-collect npm cache" npm cache verify
    fi
    if command -v pnpm >/dev/null 2>&1; then
        run_command "Prune unreferenced pnpm packages" pnpm store prune
    fi
    if [[ -d "$HOME/.gradle/caches" ]]; then
        remove_old_directories "$HOME/.gradle/caches" 1 "$CACHE_DAYS" "[0-9]*" "Gradle version cache"
    fi
fi

# MARK: - Browser Caches
if $CLEAN_BROWSER_CACHES; then
    section "Browser caches"
    if application_running "Google Chrome"; then
        warn "Google Chrome is running; Chrome caches were skipped."
        ((SKIPPED++))
    else
        for target in "$HOME/Library/Caches/Google/Chrome" "$HOME/Library/Application Support/Google/Chrome"/*/"Cache" "$HOME/Library/Application Support/Google/Chrome"/*/"Code Cache"; do
            remove_path "$target" "Chrome cache"
        done
    fi
    if application_running "firefox"; then
        warn "Firefox is running; Firefox caches were skipped."
        ((SKIPPED++))
    else
        remove_path "$HOME/Library/Caches/Firefox" "Firefox cache"
        remove_path "$HOME/Library/Caches/Mozilla" "Mozilla cache"
        for target in "$HOME/Library/Application Support/Firefox/Profiles"/*/cache2(N); do
            remove_path "$target" "Firefox profile cache"
        done
    fi
fi

# MARK: - Privacy Cleanup
if $CLEAN_PRIVACY; then
    section "Privacy data"
    remove_path "$HOME/.bash_history" "bash history"
    remove_path "$HOME/.zsh_history" "zsh history"
    if application_running "Google Chrome"; then
        warn "Google Chrome is running; Chrome history and cookies were skipped."
        ((SKIPPED++))
    else
        for profile in "$HOME/Library/Application Support/Google/Chrome"/{Default,Profile\ *}(N); do
            for item in History History-journal Cookies Cookies-journal "Current Session" "Current Tabs" "Last Session" "Last Tabs"; do
                remove_path "$profile/$item" "Chrome ${item}"
            done
        done
    fi
    if application_running "firefox"; then
        warn "Firefox is running; Firefox cookies and sessions were skipped."
        ((SKIPPED++))
    else
        for profile in "$HOME/Library/Application Support/Firefox/Profiles"/*(N/); do
            for item in cookies.sqlite cookies.sqlite-shm cookies.sqlite-wal formhistory.sqlite sessionstore.jsonlz4 sessionstore-backups; do
                remove_path "$profile/$item" "Firefox ${item}"
            done
        done
    fi
fi

# MARK: - Docker
if $CLEAN_DOCKER; then
    section "Docker"
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        run_command "Prune Docker objects unused for 30 days" docker system prune --force --filter until=720h
    else
        warn "Docker is unavailable or its daemon is not running."
        ((SKIPPED++))
    fi
fi

# MARK: - Summary
print
print "═══════════════════════════════════════════"
if $DRY_RUN; then
    print -r -- "  Dry run complete: $REMOVED item/action(s) would be cleaned"
else
    print -r -- "  Cleanup complete: $REMOVED item/action(s)"
fi
print -r -- "  Failed: $FAILED  Skipped: $SKIPPED"
print "═══════════════════════════════════════════"
(( FAILED == 0 ))
