#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GRDB_CHECKOUT="$ROOT_DIR/.build/checkouts/GRDB.swift"
GRDB_GIT_DIR="$GRDB_CHECKOUT/.git"
SUBMODULE_GIT_DIR="$GRDB_GIT_DIR/modules/SQLiteCustom/src"
FORCE=0

usage() {
    cat <<'EOF'
Usage: bash scripts/doctor_build_checkout.sh [--force]

Cleans stale generated git state in the SwiftPM GRDB checkout, then verifies the
checkout and SQLiteCustom submodule are clean. Refuses to run while matching
build or git-status processes are active unless --force is supplied.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --force)
            FORCE=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 64
            ;;
    esac
    shift
done

find_related_processes() {
    ps -axo pid=,command= \
        | grep -E 'swift( |-)(build|test)|git -C .*/GRDB\.swift(/SQLiteCustom/src)? status' \
        | grep -v grep || true
}

ensure_checkout_exists() {
    if [ ! -d "$GRDB_GIT_DIR" ]; then
        echo "GRDB checkout missing. Resolving Swift packages..."
        swift package resolve
    fi

    if [ ! -d "$GRDB_GIT_DIR" ]; then
        echo "GRDB checkout still missing after package resolution."
        exit 1
    fi
}

guard_no_active_processes() {
    local processes
    processes="$(find_related_processes)"

    if [ -n "$processes" ] && [ "$FORCE" -ne 1 ]; then
        echo "Refusing to clean generated checkout state while related processes are active:"
        echo "$processes"
        echo "Re-run with --force after those processes exit if cleanup is still needed."
        exit 1
    fi
}

remove_if_present() {
    local path="$1"

    if [ -e "$path" ]; then
        rm -f "$path"
        echo "Removed stale file: $path"
    fi
}

configure_checkout() {
    # GRDB vendors SQLite as a git submodule. Ignoring that submodule for
    # status scans keeps SwiftPM status refreshes fast and prevents hangs.
    git -C "$GRDB_CHECKOUT" config submodule.SQLiteCustom/src.ignore all || true
}

verify_checkout() {
    echo
    echo "SQLiteCustom submodule status:"
    git -C "$GRDB_CHECKOUT/SQLiteCustom/src" status --porcelain=2 -b
    echo
    echo "GRDB checkout status:"
    git -C "$GRDB_CHECKOUT" status --porcelain=2 -b
}

ensure_checkout_exists
guard_no_active_processes

echo "Inspecting generated SwiftPM checkout state..."
remove_if_present "$GRDB_GIT_DIR/index.lock"
remove_if_present "$GRDB_GIT_DIR/index 2"
remove_if_present "$SUBMODULE_GIT_DIR/index.lock"
remove_if_present "$SUBMODULE_GIT_DIR/index 2"
configure_checkout
verify_checkout

echo
echo "GRDB generated checkout is ready for normal builds."
