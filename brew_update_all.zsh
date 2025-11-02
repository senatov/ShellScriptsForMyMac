#!/bin/zsh
# shellcheck shell=zsh

###############################################################################
# macOS 26.1 Maintenance Script (Apple Silicon ready)
# Safe pruning of caches: Homebrew, Xcode, SwiftPM, Simulators, JetBrains IDEs,
# VS Code, browsers (Safari/Chromium/Firefox) including service workers,
# and common system/user logs. DRY-RUN supported.
###############################################################################

set -euo pipefail
IFS=$'\n\t'
setopt extendedglob null_glob

# ---------- Retention windows (days) ----------
DAYS_DERIVED_DATA=3
DAYS_BREW_CACHE=0
DAYS_USER_CACHES=7
DAYS_TMP_FOLDERS=3
DAYS_SIMULATOR_DATA=10
DAYS_TRASH=3
DAYS_LOGS_SYS=3
DAYS_XCODE_ARCHIVES=21
DAYS_DEVICE_SUPPORT=90
DAYS_VSCODE_WS=14
DAYS_JB_CACHES=14
DAYS_FIREFOX_PROFILE=7

# ---------- Feature toggles ----------
DRY_RUN="${DRY_RUN:-0}"
VERBOSE="${VERBOSE:-1}"
KEEP_SUDO="${KEEP_SUDO:-1}"

PRUNE_BROWSERS="${PRUNE_BROWSERS:-1}"
PRUNE_SAFARI_HISTORY="${PRUNE_SAFARI_HISTORY:-0}"   # risky, off by default
PRUNE_NODE_PIP="${PRUNE_NODE_PIP:-0}"
PRUNE_DOCKER="${PRUNE_DOCKER:-0}"
PRUNE_IDE_JETBRAINS="${PRUNE_IDE_JETBRAINS:-1}"
PRUNE_VSCODE="${PRUNE_VSCODE:-1}"
PRUNE_XCODE_DEEP="${PRUNE_XCODE_DEEP:-1}"          # includes Previews/Docs/ModuleCache
PRUNE_FIREFOX_EXTRAS="${PRUNE_FIREFOX_EXTRAS:-1}"  # service workers, storage caches
AGGRESSIVE_FIND="${AGGRESSIVE_FIND:-0}"

# ---------- Paths / brew ----------
BREW_BIN=""
[[ -x "/opt/homebrew/bin/brew" ]] && BREW_BIN="/opt/homebrew/bin/brew"
[[ -z "$BREW_BIN" && -x "/usr/local/bin/brew" ]] && BREW_BIN="/usr/local/bin/brew"
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"

# ---------- Logging ----------
ts() { date "+%Y-%m-%d %H:%M:%S"; }
log_i() { [[ "$VERBOSE" = "1" ]] && echo "[INFO  $(ts)] $*"; }
log_w() { echo "[WARN  $(ts)] $*" >&2; }
log_e() { echo "[ERROR $(ts)] $*" >&2; }

rm_safely() {
  if [[ "$DRY_RUN" = "1" ]]; then
    for p in "$@"; do [[ -e "$p" || -L "$p" ]] && echo "DRY-RUN: rm -rf \"$p\""; done
  else
    rm -rf "$@" 2>/dev/null || true
  fi
}
rmdir_safely() {
  if [[ "$DRY_RUN" = "1" ]]; then
    for p in "$@"; do [[ -d "$p" ]] && echo "DRY-RUN: rmdir \"$p\""; done
  else
    rmdir "$@" 2>/dev/null || true
  fi
}

sudo_keepalive() {
  [[ "$KEEP_SUDO" = "1" ]] || return
  while true; do sudo -n true 2>/dev/null || true; sleep 60; done & SUDO_PID=$!
  trap '[[ -n "${SUDO_PID:-}" ]] && kill $SUDO_PID 2>/dev/null || true' EXIT
}
prompt_sudo() {
  log_i "Requesting admin privileges for certain maintenance steps..."
  if sudo -v; then sudo_keepalive; else log_w "No sudo acquired; sudo-required steps will be skipped."; fi
}

# ---------- Homebrew ----------
update_brew() {
  log_i "Updating Homebrew..."
  if [[ -z "$BREW_BIN" ]]; then log_w "Homebrew not found. Skipping."; return; fi
  "$BREW_BIN" update || log_e "brew update failed."
  "$BREW_BIN" upgrade || log_e "brew upgrade failed."
  "$BREW_BIN" autoremove || true
  "$BREW_BIN" cleanup --prune=all -s || true
  if [[ "$DAYS_BREW_CACHE" -eq 0 ]]; then
    local cache="$("$BREW_BIN" --cache 2>/dev/null || echo "")"
    if [[ -n "$cache" && -e "$cache" ]]; then
      log_i "Wiping Homebrew cache: $cache"
      rm_safely "$cache"/*
    fi
  fi
}

# ---------- Xcode / Developer ----------
cleanup_derived_data() {
  local dir="$HOME/Library/Developer/Xcode/DerivedData"
  log_i "Pruning DerivedData (> ${DAYS_DERIVED_DATA}d): $dir"
  [[ -d "$dir" ]] || { log_w "DerivedData not found"; return; }
  [[ "$AGGRESSIVE_FIND" = "1" && "$DRY_RUN" = "0" ]] && find "$dir" -mindepth 1 -maxdepth 1 -type d -mtime +$DAYS_DERIVED_DATA -depth -print -delete || find "$dir" -mindepth 1 -maxdepth 1 -type d -mtime +$DAYS_DERIVED_DATA -print -exec sh -c 'if [ "${DRY_RUN:-0}" = "1" ]; then echo "DRY-RUN: rm -rf \"$1\""; else rm -rf "$1"; fi' _ {} \;
}
cleanup_xcode_archives() {
  local dir="$HOME/Library/Developer/Xcode/Archives"
  [[ -d "$dir" ]] || return
  log_i "Pruning Xcode Archives (> ${DAYS_XCODE_ARCHIVES}d): $dir"
  [[ "$AGGRESSIVE_FIND" = "1" && "$DRY_RUN" = "0" ]] && find "$dir" -mindepth 1 -maxdepth 1 -type d -mtime +$DAYS_XCODE_ARCHIVES -depth -print -delete || find "$dir" -mindepth 1 -maxdepth 1 -type d -mtime +$DAYS_XCODE_ARCHIVES -print -exec sh -c 'if [ "${DRY_RUN:-0}" = "1" ]; then echo "DRY-RUN: rm -rf \"$1\""; else rm -rf "$1"; fi' _ {} \;
}
cleanup_device_support() {
  for ds in "$HOME/Library/Developer/Xcode/"{iOS,tvOS,watchOS}" DeviceSupport"; do
    [[ -d "$ds" ]] || continue
    log_i "Pruning DeviceSupport (> ${DAYS_DEVICE_SUPPORT}d): $ds"
    [[ "$AGGRESSIVE_FIND" = "1" && "$DRY_RUN" = "0" ]] && find "$ds" -mindepth 1 -maxdepth 1 -type d -mtime +$DAYS_DEVICE_SUPPORT -depth -print -delete || find "$ds" -mindepth 1 -maxdepth 1 -type d -mtime +$DAYS_DEVICE_SUPPORT -print -exec sh -c 'if [ "${DRY_RUN:-0}" = "1" ]; then echo "DRY-RUN: rm -rf \"$1\""; else rm -rf "$1"; fi' _ {} \;
  done
}
cleanup_xcode_deep() {
  [[ "$PRUNE_XCODE_DEEP" = "1" ]] || return
  # SwiftPM caches
  for p in "$HOME/Library/Caches/org.swift.swiftpm" \
           "$HOME/Library/org.swift.swiftpm" \
           "$HOME/.swiftpm/cache" \
           "$HOME/Library/Developer/Xcode/Previews"; do
    [[ -d "$p" ]] || continue
    log_i "Cleaning Xcode/SwiftPM cache: $p"
    rm_safely "$p"/**/*
  done
  # ModuleCache.noindex
  for p in "$HOME/Library/Developer/Xcode/DerivedData/ModuleCache.noindex"; do
    [[ -d "$p" ]] || continue
    log_i "Cleaning ModuleCache.noindex: $p"
    rm_safely "$p"/**/*
  done
  # Documentation caches
  for p in "$HOME/Library/Developer/Xcode/DocumentationCache" \
           "$HOME/Library/Developer/Xcode/DocumentationCache.noindex" \
           "$HOME/Library/Developer/Xcode/SharedDocumentationCache"; do
    [[ -d "$p" ]] || continue
    log_i "Cleaning Xcode documentation cache: $p"
    rm_safely "$p"/**/*
  done
  # DTDeviceKit (device logs & metadata)
  for p in "$HOME/Library/Developer/Xcode/iOS Device Logs" \
           "$HOME/Library/Developer/Xcode/DTDeviceKit"; do
    [[ -d "$p" ]] || continue
    log_i "Cleaning Xcode device logs/DTDeviceKit: $p"
    rm_safely "$p"/**/*
  done
}

cleanup_simulators() {
  local dev="$HOME/Library/Developer/CoreSimulator/Devices"
  if [[ -d "$dev" ]]; then
    log_i "Pruning CoreSimulator data (> ${DAYS_SIMULATOR_DATA}d): $dev"
    [[ "$AGGRESSIVE_FIND" = "1" && "$DRY_RUN" = "0" ]] && find "$dev" -type d -name "data" -mtime +$DAYS_SIMULATOR_DATA -depth -print -delete || find "$dev" -type d -name "data" -mtime +$DAYS_SIMULATOR_DATA -print -exec sh -c 'if [ "${DRY_RUN:-0}" = "1" ]; then echo "DRY-RUN: rm -rf \"$1\""; else rm -rf "$1"; fi' _ {} \;
  fi
  if command -v xcrun &>/dev/null; then
    log_i "Deleting unavailable simulators (xcrun simctl)..."
    if [[ "$DRY_RUN" = "1" ]]; then
      xcrun simctl list devices unavailable
      log_i "DRY-RUN: xcrun simctl delete unavailable"
    else
      xcrun simctl delete unavailable || true
    fi
  fi
}

# ---------- VS Code ----------
cleanup_vscode() {
  [[ "$PRUNE_VSCODE" = "1" ]] || return
  local base="$HOME/Library/Application Support/Code"
  [[ -d "$base" ]] || return
  log_i "Cleaning VS Code caches/workspaces..."
  rm_safely "$base/Cache"/**/*
  rm_safely "$base/CachedData"/**/*
  [[ "$AGGRESSIVE_FIND" = "1" && "$DRY_RUN" = "0" ]] && find "$base/User/workspaceStorage" -mindepth 1 -maxdepth 1 -type d -mtime +$DAYS_VSCODE_WS -depth -print -delete || find "$base/User/workspaceStorage" -mindepth 1 -maxdepth 1 -type d -mtime +$DAYS_VSCODE_WS -print -exec sh -c 'if [ "${DRY_RUN:-0}" = "1" ]; then echo "DRY-RUN: rm -rf \"$1\""; else rm -rf "$1"; fi' _ {} \;
}

# ---------- JetBrains / IntelliJ family ----------
cleanup_jetbrains() {
  [[ "$PRUNE_IDE_JETBRAINS" = "1" ]] || return
  # Wildcards for caches across IDEs and versions
  local JB_CACHE=(
    "$HOME/Library/Caches/JetBrains"/*/caches
    "$HOME/Library/Caches"/*Idea*/caches
    "$HOME/Library/Caches"/*WebStorm*/caches
    "$HOME/Library/Caches"/*PyCharm*/caches
    "$HOME/Library/Caches"/*CLion*/caches
    "$HOME/Library/Caches"/*GoLand*/caches
    "$HOME/Library/Caches"/*Rider*/caches
    "$HOME/Library/Caches/AndroidStudio"*/caches
  )
  for p in "${JB_CACHE[@]}"; do
    [[ -d "$p" ]] || continue
    log_i "Cleaning JetBrains caches: $p"
    [[ "$AGGRESSIVE_FIND" = "1" && "$DRY_RUN" = "0" ]] && find "$p" -mindepth 1 -mtime +$DAYS_JB_CACHES -depth -print -delete || find "$p" -mindepth 1 -mtime +$DAYS_JB_CACHES -print -exec sh -c 'if [ "${DRY_RUN:-0}" = "1" ]; then echo "DRY-RUN: rm -rf \"$1\""; else rm -rf "$1"; fi' _ {} \;
  done

  # Indexes and system folders
  local JB_SYSTEM=(
    "$HOME/Library/Application Support/JetBrains"/*/index
    "$HOME/Library/Application Support/JetBrains"/*/caches
    "$HOME/Library/Application Support/AndroidStudio"*/caches
    "$HOME/Library/Application Support/AndroidStudio"*/system/caches
  )
  for p in "${JB_SYSTEM[@]}"; do
    [[ -d "$p" ]] || continue
    log_i "Cleaning JetBrains system: $p"
    rm_safely "$p"/**/*
  done

  # Logs older than retention
  local JB_LOGS=(
    "$HOME/Library/Logs/JetBrains"/*
    "$HOME/Library/Logs/AndroidStudio"*
  )
  for p in "${JB_LOGS[@]}"; do
    [[ -d "$p" ]] || continue
    find "$p" -type f -mtime +$DAYS_LOGS_SYS -print -exec sh -c 'if [ "${DRY_RUN:-0}" = "1" ]; then echo "DRY-RUN: rm -f \"$1\""; else rm -f "$1"; fi' _ {} \;
  done
}

# ---------- System / user temp & caches ----------
clean_temp_folders() {
  log_i "Pruning temporary system folders (> ${DAYS_TMP_FOLDERS}d)..."
  sudo find /var/folders -mindepth 1 -type d -mtime +$DAYS_TMP_FOLDERS -empty -print -exec rmdir {} \; 2>/dev/null || true
}
clean_user_caches() {
  log_i "Pruning user caches (> ${DAYS_USER_CACHES}d)..."
  local C="$HOME/Library/Caches"
  if [[ -d "$C" ]]; then
    [[ "$AGGRESSIVE_FIND" = "1" && "$DRY_RUN" = "0" ]] && find "$C" -mindepth 1 -maxdepth 1 -type d \
      ! -name 'com.apple.*' ! -name 'mds' ! -name 'com.apple.Spotlight' \
      -mtime +$DAYS_USER_CACHES -depth -print -delete || find "$C" -mindepth 1 -maxdepth 1 -type d \
      ! -name 'com.apple.*' ! -name 'mds' ! -name 'com.apple.Spotlight' \
      -mtime +$DAYS_USER_CACHES -print -exec sh -c 'if [ "${DRY_RUN:-0}" = "1" ]; then echo "DRY-RUN: rm -rf \"$1\""; else rm -rf "$1"; fi' _ {} \;
  fi
  # Common app caches
  local APP_CACHE=(
    "$HOME/Library/Application Support/Slack/Service Worker/CacheStorage"
    "$HOME/Library/Application Support/Slack/Cache"
  )
  for p in "${APP_CACHE[@]}"; do
    [[ -d "$p" ]] || continue
    log_i "Cleaning app cache: $p"
    rm_safely "$p"/**/*
  done
}

# ---------- Extra safe caches ----------
clean_quicklook_cache() {
  # Quick Look thumbnail cache rebuilds automatically
  local QL1="$HOME/Library/Caches/com.apple.QuickLook.thumbnailcache"
  local QL2="$HOME/Library/Caches/com.apple.QuickLookUIService"
  for p in "$QL1" "$QL2"; do
    [[ -d "$p" ]] || continue
    log_i "Cleaning QuickLook cache: $p"
    rm_safely "$p"/**/*
  done
}

clean_iconservices_cache() {
  # IconServices cache is safe to purge; icons will be regenerated
  local IS1="$HOME/Library/Caches/com.apple.iconservices.store"
  local IS2="$HOME/Library/Caches/com.apple.iconservices"
  for p in "$IS1" "$IS2"; do
    [[ -e "$p" ]] || continue
    log_i "Cleaning IconServices cache: $p"
    rm_safely "$p"/**/*
  done
}

clean_nsurlsessiond_cache() {
  # NSURLSession daemon cache (download tasks). Safe to clear old entries
  local NSURLC="$HOME/Library/Caches/com.apple.nsurlsessiond"
  if [[ -d "$NSURLC" ]]; then
    log_i "Cleaning NSURLSessiond cache: $NSURLC"
    rm_safely "$NSURLC"/**/*
  fi
}

clean_simulator_logs_cache() {
  # CoreSimulator logs and cache can grow quite large
  local CSL="$HOME/Library/Logs/CoreSimulator"
  local CSC="$HOME/Library/Developer/CoreSimulator/Caches"
  for p in "$CSL" "$CSC"; do
    [[ -d "$p" ]] || continue
    log_i "Cleaning CoreSimulator logs/cache: $p"
    rm_safely "$p"/**/*
  done
}

# ---------- Browsers ----------
clean_safari_webkit() {
  local SAFARI_CACHES=(
    "$HOME/Library/Caches/com.apple.Safari"
    "$HOME/Library/Caches/com.apple.WebKit.Networking"
    "$HOME/Library/Caches/com.apple.WebKit.GPU"
    "$HOME/Library/Caches/com.apple.WebKit.WebContent"
  )
  for p in "${SAFARI_CACHES[@]}"; do
    [[ -d "$p" ]] || continue
    log_i "Cleaning Safari/WebKit cache: $p"
    rm_safely "$p"/**/*
  done
  if [[ "$PRUNE_SAFARI_HISTORY" = "1" ]]; then
    local hist="$HOME/Library/Safari/History.db"
    if [[ -f "$hist" ]]; then
      log_w "Compacting Safari History.db (ensure Safari is closed)"
      [[ "$DRY_RUN" = "1" ]] && echo "DRY-RUN: sqlite3 \"$hist\" 'VACUUM;'" || /usr/bin/sqlite3 "$hist" 'VACUUM;' || true
    fi
  fi
}

clean_chromium() {
  local CHROMIUM_DIRS=(
    "$HOME/Library/Application Support/Google/Chrome"
    "$HOME/Library/Application Support/Microsoft Edge"
    "$HOME/Library/Application Support/BraveSoftware/Brave-Browser"
  )
  for base in "${CHROMIUM_DIRS[@]}"; do
    [[ -d "$base" ]] || continue
    # Per-profile Cache folders older than 3 days
    [[ "$AGGRESSIVE_FIND" = "1" && "$DRY_RUN" = "0" ]] && find "$base" -type d -path "*/Cache" -mtime +3 -depth -print -delete || find "$base" -type d -path "*/Cache" -mtime +3 -print -exec sh -c 'if [ "${DRY_RUN:-0}" = "1" ]; then echo "DRY-RUN: rm -rf \"$1\""; else rm -rf "$1"; fi' _ {} \;
    # Code Cache, GPUCache, Service Worker CacheStorage
    for p in "$base"/**/{Code\ Cache,GPUCache,Service\ Worker/CacheStorage}; do
      [[ -d "$p" ]] || continue
      log_i "Cleaning Chromium cache: $p"
      rm_safely "$p"/**/*
    done
  done
}

clean_firefox() {
  # Basic Firefox cache2 purge
  for prof in "$HOME/Library/Application Support/Firefox/Profiles"/*; do
    [[ -d "$prof" ]] || continue
    log_i "Firefox profile: $prof"
    # cache2
    [[ -d "$prof/cache2" ]] && rm_safely "$prof/cache2"/**/*
    # optional extras
    if [[ "$PRUNE_FIREFOX_EXTRAS" = "1" ]]; then
      [[ -d "$prof/startupCache" ]] && rm_safely "$prof/startupCache"/**/*
      [[ -d "$prof/shader-cache" ]] && rm_safely "$prof/shader-cache"/**/*
      [[ -d "$prof/thumbnails" ]] && ( [[ "$AGGRESSIVE_FIND" = "1" && "$DRY_RUN" = "0" ]] && find "$prof/thumbnails" -type f -mtime +$DAYS_FIREFOX_PROFILE -print -delete || find "$prof/thumbnails" -type f -mtime +$DAYS_FIREFOX_PROFILE -print -exec sh -c 'if [ "${DRY_RUN:-0}" = "1" ]; then echo "DRY-RUN: rm -f \"$1\""; else rm -f "$1"; fi' _ {} \; )
      # Service workers and storage caches
      for p in "$prof"/storage/default/*/cache; do
        [[ -d "$p" ]] || continue
        log_i "Cleaning Firefox storage cache: $p"
        rm_safely "$p"/**/*
      done
      [[ -d "$prof/storage/temporary" ]] && rm_safely "$prof/storage/temporary"/**/*

      # Service Worker CacheStorage (new profiles can keep it elsewhere)
      for p in "$prof"/storage/default/*/serviceworker \
               "$prof"/storage/default/*/Cache \
               "$prof"/storage/default/*/caches \
               "$prof"/storage/default/*/cacheStorage; do
        [[ -d "$p" ]] || continue
        log_i "Cleaning Firefox service worker cache: $p"
        rm_safely "$p"/**/*
      done
    fi
  done
}

clean_browser_caches() {
  [[ "$PRUNE_BROWSERS" = "1" ]] || return
  clean_safari_webkit
  clean_chromium
  clean_firefox
}

# ---------- Extended cleanup ----------
extended_cleanup() {
  log_i "Extended cleanup: Trash, crash logs, and legacy reports"
  [[ "$AGGRESSIVE_FIND" = "1" && "$DRY_RUN" = "0" ]] && find "$HOME/.Trash" -mindepth 1 -mtime +$DAYS_TRASH -depth -print -delete || find "$HOME/.Trash" -mindepth 1 -mtime +$DAYS_TRASH -print -exec sh -c 'if [ "${DRY_RUN:-0}" = "1" ]; then echo "DRY-RUN: rm -rf \"$1\""; else rm -rf "$1"; fi' _ {} \;

  local USER_LOGS=(
    "$HOME/Library/Logs/DiagnosticReports"
    "$HOME/Library/Application Support/CrashReporter"
    "$HOME/Library/Saved Application State"
  )
  for dir in "${USER_LOGS[@]}"; do
    [[ -d "$dir" ]] || continue
    [[ "$AGGRESSIVE_FIND" = "1" && "$DRY_RUN" = "0" ]] && find "$dir" -type f -mtime +$DAYS_LOGS_SYS -print -delete || find "$dir" -type f -mtime +$DAYS_LOGS_SYS -print -exec sh -c 'if [ "${DRY_RUN:-0}" = "1" ]; then echo "DRY-RUN: rm -f \"$1\""; else rm -f "$1"; fi' _ {} \;
  done

  for dir in "/Library/Logs/DiagnosticReports" "/Library/Application Support/CrashReporter"; do
    [[ -d "$dir" ]] || continue
    if [[ "$AGGRESSIVE_FIND" = "1" && "$DRY_RUN" = "0" ]]; then sudo find "$dir" -mindepth 1 -mtime +$DAYS_LOGS_SYS -depth -print -delete 2>/dev/null || true; else sudo find "$dir" -mindepth 1 -mtime +$DAYS_LOGS_SYS -print -exec sh -c 'if [ "${DRY_RUN:-0}" = "1" ]; then echo "DRY-RUN: rm -rf \"$1\""; else rm -rf "$1"; fi' _ {} \; 2>/dev/null || true; fi
  done
}

optional_dev_caches() {
  [[ "$PRUNE_NODE_PIP" = "1" ]] || return
  if command -v npm &>/dev/null; then
    log_i "Cleaning npm cache..."
    [[ "$DRY_RUN" = "1" ]] && echo "DRY-RUN: npm cache clean --force" || npm cache clean --force || true
  fi
  if command -v pip &>/dev/null; then
    log_i "Cleaning pip cache..."
    [[ "$DRY_RUN" = "1" ]] && echo "DRY-RUN: pip cache purge" || pip cache purge || true
  fi
}

optional_docker() {
  [[ "$PRUNE_DOCKER" = "1" ]] || return
  if command -v docker &>/dev/null; then
    log_i "Pruning Docker (dangling images/volumes)..."
    [[ "$DRY_RUN" = "1" ]] && echo "DRY-RUN: docker system prune -f" || docker system prune -f || true
  fi
}

# ---------- Main ----------
main() {
  log_i "Please enter your password to proceed with maintenance tasks (if required)."
  prompt_sudo

  update_brew
  cleanup_derived_data
  cleanup_xcode_archives
  cleanup_device_support
  cleanup_xcode_deep
  cleanup_simulators
  clean_temp_folders
  clean_user_caches
  clean_quicklook_cache
  clean_iconservices_cache
  clean_nsurlsessiond_cache
  clean_simulator_logs_cache
  cleanup_vscode
  cleanup_jetbrains
  clean_browser_caches
  extended_cleanup
  optional_dev_caches
  optional_docker

  log_i "Maintenance tasks completed."
}

main "$@"