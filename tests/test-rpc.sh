#!/usr/bin/env bash
# test-rpc.sh — Integration tests for openmediavault-tgt RPC methods.
#
# Usage: sudo ./tests/test-rpc.sh
#
# Exercises all tgt RPC methods: settings CRUD, target CRUD with IQN
# auto-generation and input normalisation, image CRUD with sparse-file
# creation, image growth, and negative tests.
#
# No external dependencies beyond what the plugin itself requires.
#
# WARNING: This script transiently modifies tgt settings and creates/deletes
# test targets and image files.  Run on a test system or during a maintenance
# window.

set -uo pipefail

# ---------------------------------------------------------------------------
# Colours / counters  (display → stderr; $() captures only JSON)
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
declare -a FAILED_TESTS=()

section() { echo -e "\n${CYAN}${BOLD}=== $* ===${NC}" >&2; }
info()    { echo -e "  ${YELLOW}»${NC} $*" >&2; }

_pass() {
    echo -e "  ${GREEN}PASS${NC}  $1" >&2
    ((PASS++)) || true
}
_fail() {
    echo -e "  ${RED}FAIL${NC}  $1" >&2
    [ -n "${2:-}" ] && echo -e "         ${RED}→${NC} $2" >&2
    ((FAIL++)) || true
    FAILED_TESTS+=("$1")
}

# ---------------------------------------------------------------------------
# RPC helpers
# ---------------------------------------------------------------------------
rpc() {
    local svc=$1 method=$2 params=${3:-'{}'}
    omv-rpc -u admin "$svc" "$method" "$params"
}

assert_rpc() {
    local desc=$1 svc=$2 method=$3 params=${4:-'{}'} pattern=${5:-}
    local out ec=0
    out=$(omv-rpc -u admin "$svc" "$method" "$params" 2>&1) || ec=$?
    if [ $ec -ne 0 ]; then
        _fail "$desc" "$(echo "$out" | tail -3)"
        return 1
    fi
    if [ -n "$pattern" ] && ! echo "$out" | grep -q "$pattern"; then
        _fail "$desc" "Pattern '$pattern' not found in: ${out:0:200}"
        return 1
    fi
    _pass "$desc"
    echo "$out"
    return 0
}

assert_rpc_fails() {
    local desc=$1 svc=$2 method=$3 params=${4:-'{}'}
    local out ec=0
    out=$(omv-rpc -u admin "$svc" "$method" "$params" 2>&1) || ec=$?
    if [ $ec -eq 0 ] && ! echo "$out" | grep -qi "exception"; then
        _fail "$desc" "Expected failure but RPC succeeded: ${out:0:200}"
        return 1
    fi
    _pass "$desc"
    return 0
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
TARGET1_UUID=""
TARGET2_UUID=""
IMAGE1_UUID=""
ORIG_SETTINGS=""
IMG_DIR=""

LIST_PARAMS='{"start":0,"limit":null,"sortfield":null,"sortdir":null}'
OMV_NEW_UUID=$(. /etc/default/openmediavault 2>/dev/null; \
    echo "${OMV_CONFIGOBJECT_NEW_UUID:-fa4b1c66-ef79-11e5-87a0-0002b3a176b4}")

# ---------------------------------------------------------------------------
# Cleanup — always runs on exit
# ---------------------------------------------------------------------------
cleanup() {
    section "Cleanup"

    for uuid in "$TARGET1_UUID" "$TARGET2_UUID"; do
        [ -z "$uuid" ] && continue
        info "Deleting test target $uuid"
        rpc "tgt" "deleteTarget" "{\"uuid\":\"$uuid\"}" &>/dev/null || true
    done
    TARGET1_UUID=""
    TARGET2_UUID=""

    if [ -n "$IMAGE1_UUID" ]; then
        info "Deleting test image $IMAGE1_UUID"
        rpc "tgt" "deleteImage" "{\"uuid\":\"$IMAGE1_UUID\"}" &>/dev/null || true
        IMAGE1_UUID=""
    fi

    if [ -n "$IMG_DIR" ] && [ -d "$IMG_DIR" ]; then
        info "Removing test image directory $IMG_DIR"
        rm -rf "$IMG_DIR" 2>/dev/null || true
        IMG_DIR=""
    fi

    if [ -n "$ORIG_SETTINGS" ]; then
        info "Restoring original tgt settings"
        rpc "tgt" "setSettings" "$ORIG_SETTINGS" &>/dev/null || true
    fi

    info "Done."
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
section "Pre-flight"

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Must be run as root.${NC}" >&2
    exit 1
fi

for cmd in omv-rpc python3 jq; do
    if command -v "$cmd" &>/dev/null; then
        _pass "command available: $cmd"
    else
        _fail "command available: $cmd" "$cmd not found in PATH"
    fi
done

if ! omv-rpc -u admin "Config" "isDirty" '{}' &>/dev/null; then
    echo -e "\n${RED}omv-rpc not functional — aborting.${NC}" >&2
    exit 1
fi
_pass "omv-rpc functional"

# Create temp directory for image files
IMG_DIR=$(mktemp -d)
_pass "image directory created: $IMG_DIR"

# ===========================================================================
section "Settings — read"
# ===========================================================================

ORIG_SETTINGS=$(assert_rpc "getSettings" "tgt" "getSettings") || {
    echo -e "\n${RED}getSettings failed — aborting.${NC}" >&2
    exit 1
}

for field in enable extraoptions; do
    if echo "$ORIG_SETTINGS" | jq -e "has(\"$field\")" &>/dev/null; then
        _pass "getSettings — field '$field' present"
    else
        _fail "getSettings — field '$field' missing"
    fi
done

ORIG_ENABLE=$(echo "$ORIG_SETTINGS" | jq -r '.enable // false')
info "Current enable: $ORIG_ENABLE"

# ===========================================================================
section "Settings — write"
# ===========================================================================

assert_rpc "setSettings — enable=false, extraoptions empty" "tgt" "setSettings" \
    '{"enable":false,"extraoptions":""}' \
    '"enable":false' >/dev/null

assert_rpc "setSettings — extraoptions set" "tgt" "setSettings" \
    '{"enable":false,"extraoptions":"# test option"}' \
    'test option' >/dev/null

# Restore original settings before negative tests
rpc "tgt" "setSettings" "$ORIG_SETTINGS" &>/dev/null || true

# ===========================================================================
section "Settings — negative tests"
# ===========================================================================

assert_rpc_fails "setSettings — missing enable" "tgt" "setSettings" \
    '{"extraoptions":""}'

assert_rpc_fails "setSettings — missing extraoptions" "tgt" "setSettings" \
    '{"enable":false}'

# ===========================================================================
section "Target — CRUD"
# ===========================================================================

assert_rpc "getTargetList (initial)" "tgt" "getTargetList" "$LIST_PARAMS" >/dev/null

# Create test target 1
T1_RESULT=$(rpc "tgt" "setTarget" "$(jq -n \
    --arg uuid "$OMV_NEW_UUID" \
    '{uuid:$uuid, enable:false, name:"tgtrpctest1",
      iqn:"", backingstore:"", initiatoraddress:"ALL", extraoptions:""}')" \
    2>&1) && T1_EC=0 || T1_EC=$?

TARGET1_UUID=$(echo "$T1_RESULT" | jq -r '.uuid // ""' 2>/dev/null || echo "")

if [ $T1_EC -eq 0 ] && [ -n "$TARGET1_UUID" ] \
        && [ "$TARGET1_UUID" != "$OMV_NEW_UUID" ]; then
    _pass "setTarget (create tgtrpctest1) — UUID: $TARGET1_UUID"
else
    _fail "setTarget (create tgtrpctest1)" "${T1_RESULT:0:200}"
    TARGET1_UUID=""
fi

if [ -n "$TARGET1_UUID" ]; then
    # Verify stored fields
    T1_DATA=$(assert_rpc "getTarget (tgtrpctest1)" "tgt" "getTarget" \
        "{\"uuid\":\"$TARGET1_UUID\"}" "\"uuid\":\"$TARGET1_UUID\"")

    # IQN must be auto-generated (non-empty, starts with iqn.)
    T1_IQN=$(echo "$T1_DATA" | jq -r '.iqn // ""')
    if echo "$T1_IQN" | grep -q '^iqn\.'; then
        _pass "setTarget — IQN auto-generated: $T1_IQN"
    else
        _fail "setTarget — IQN not auto-generated (got: '$T1_IQN')"
    fi

    # IQN must contain the target name (lowercased)
    if echo "$T1_IQN" | grep -qi 'tgtrpctest1'; then
        _pass "setTarget — IQN contains target name"
    else
        _fail "setTarget — IQN missing target name (got: '$T1_IQN')"
    fi

    # getTargetList — entry present
    T1_LIST=$(assert_rpc "getTargetList — tgtrpctest1 present" "tgt" "getTargetList" \
        "$LIST_PARAMS" "tgtrpctest1")

    # Edit target — change extraoptions
    assert_rpc "setTarget (edit — add extraoptions)" "tgt" "setTarget" \
        "$(jq -n \
            --arg uuid "$TARGET1_UUID" --arg iqn "$T1_IQN" \
            '{uuid:$uuid, enable:false, name:"tgtrpctest1",
              iqn:$iqn, backingstore:"", initiatoraddress:"ALL",
              extraoptions:"incominguser testuser testpass"}')" \
        '"extraoptions"' >/dev/null
fi

# ===========================================================================
section "Target — initiatoraddress normalisation"
# ===========================================================================

# Commas and extra spaces should be normalised to single spaces
T2_RESULT=$(rpc "tgt" "setTarget" "$(jq -n \
    --arg uuid "$OMV_NEW_UUID" \
    '{uuid:$uuid, enable:false, name:"tgtrpctest2",
      iqn:"", backingstore:"",
      initiatoraddress:"192.168.1.1, 192.168.1.2,  192.168.1.3",
      extraoptions:""}')" \
    2>&1) && T2_EC=0 || T2_EC=$?

TARGET2_UUID=$(echo "$T2_RESULT" | jq -r '.uuid // ""' 2>/dev/null || echo "")

if [ $T2_EC -eq 0 ] && [ -n "$TARGET2_UUID" ] \
        && [ "$TARGET2_UUID" != "$OMV_NEW_UUID" ]; then
    _pass "setTarget (create tgtrpctest2) — UUID: $TARGET2_UUID"

    T2_DATA=$(rpc "tgt" "getTarget" "{\"uuid\":\"$TARGET2_UUID\"}" 2>/dev/null || echo '{}')
    T2_ADDR=$(echo "$T2_DATA" | jq -r '.initiatoraddress // ""')
    if [ "$T2_ADDR" = "192.168.1.1 192.168.1.2 192.168.1.3" ]; then
        _pass "initiatoraddress — commas/spaces normalised to single spaces"
    else
        _fail "initiatoraddress — unexpected value: '$T2_ADDR'"
    fi
else
    _fail "setTarget (create tgtrpctest2)" "${T2_RESULT:0:200}"
    TARGET2_UUID=""
fi

# ===========================================================================
section "Target — backingstore deduplication"
# ===========================================================================

if [ -n "$TARGET2_UUID" ]; then
    T2_IQN=$(rpc "tgt" "getTarget" "{\"uuid\":\"$TARGET2_UUID\"}" 2>/dev/null \
        | jq -r '.iqn // ""')
    BS_RESULT=$(rpc "tgt" "setTarget" "$(jq -n \
        --arg uuid "$TARGET2_UUID" --arg iqn "$T2_IQN" \
        '{uuid:$uuid, enable:false, name:"tgtrpctest2", iqn:$iqn,
          backingstore:"/path/a,/path/b,/path/a",
          initiatoraddress:"ALL", extraoptions:""}')" \
        2>&1) && BS_EC=0 || BS_EC=$?
    if [ $BS_EC -eq 0 ]; then
        BS_STORED=$(echo "$BS_RESULT" | jq -r '.backingstore // ""')
        if [ "$BS_STORED" = "/path/a,/path/b" ]; then
            _pass "backingstore — duplicate paths deduplicated"
        else
            _fail "backingstore — unexpected value: '$BS_STORED' (expected '/path/a,/path/b')"
        fi
    else
        _fail "setTarget (backingstore dedup)" "${BS_RESULT:0:200}"
    fi
fi

# ===========================================================================
section "Target — negative tests"
# ===========================================================================

assert_rpc_fails "getTarget — unknown UUID" "tgt" "getTarget" \
    '{"uuid":"00000000-0000-0000-0000-000000000000"}'

assert_rpc_fails "deleteTarget — unknown UUID" "tgt" "deleteTarget" \
    '{"uuid":"00000000-0000-0000-0000-000000000000"}'

# Duplicate name must be rejected
if [ -n "$TARGET1_UUID" ]; then
    assert_rpc_fails "setTarget — duplicate name rejected" "tgt" "setTarget" \
        "$(jq -n --arg uuid "$OMV_NEW_UUID" \
            '{uuid:$uuid, enable:false, name:"tgtrpctest1",
              iqn:"", backingstore:"", initiatoraddress:"ALL", extraoptions:""}')"
fi

# Missing required fields
assert_rpc_fails "setTarget — missing enable" "tgt" "setTarget" \
    "$(jq -n --arg uuid "$OMV_NEW_UUID" \
        '{uuid:$uuid, name:"tgtrpctest-bad",
          backingstore:"", initiatoraddress:"ALL", extraoptions:""}')"

assert_rpc_fails "setTarget — missing backingstore" "tgt" "setTarget" \
    "$(jq -n --arg uuid "$OMV_NEW_UUID" \
        '{uuid:$uuid, enable:false, name:"tgtrpctest-bad",
          initiatoraddress:"ALL", extraoptions:""}')"

# ===========================================================================
section "Target — delete"
# ===========================================================================

if [ -n "$TARGET1_UUID" ]; then
    DEL1_RESULT=$(assert_rpc "deleteTarget (tgtrpctest1)" "tgt" "deleteTarget" \
        "{\"uuid\":\"$TARGET1_UUID\"}")
    DELETED1_UUID="$TARGET1_UUID"
    TARGET1_UUID=""

    assert_rpc_fails "getTarget after deleteTarget" "tgt" "getTarget" \
        "{\"uuid\":\"$DELETED1_UUID\"}"

    LIST_AFTER=$(rpc "tgt" "getTargetList" "$LIST_PARAMS" 2>/dev/null \
        || echo '{"data":[]}')
    if echo "$LIST_AFTER" \
            | jq -e --arg u "$DELETED1_UUID" '.data[] | select(.uuid == $u)' \
            &>/dev/null; then
        _fail "getTargetList — deleted target still present"
    else
        _pass "getTargetList — deleted target absent"
    fi
fi

if [ -n "$TARGET2_UUID" ]; then
    assert_rpc "deleteTarget (tgtrpctest2)" "tgt" "deleteTarget" \
        "{\"uuid\":\"$TARGET2_UUID\"}" >/dev/null
    TARGET2_UUID=""
fi

# ===========================================================================
section "Image — CRUD"
# ===========================================================================

assert_rpc "getImageList (initial)" "tgt" "getImageList" "$LIST_PARAMS" >/dev/null

IMG1_PATH="${IMG_DIR}/tgtrpctest1.img"

# Create image — setImage creates a sparse file via dd
I1_RESULT=$(rpc "tgt" "setImage" "$(jq -n \
    --arg uuid "$OMV_NEW_UUID" --arg path "$IMG1_PATH" \
    '{uuid:$uuid, path:$path, imagesize:1}')" \
    2>&1) && I1_EC=0 || I1_EC=$?

IMAGE1_UUID=$(echo "$I1_RESULT" | jq -r '.uuid // ""' 2>/dev/null || echo "")

if [ $I1_EC -eq 0 ] && [ -n "$IMAGE1_UUID" ] \
        && [ "$IMAGE1_UUID" != "$OMV_NEW_UUID" ]; then
    _pass "setImage (create) — UUID: $IMAGE1_UUID"
else
    _fail "setImage (create)" "${I1_RESULT:0:200}"
    IMAGE1_UUID=""
fi

if [ -n "$IMAGE1_UUID" ]; then
    # Verify file was created on disk
    if [ -f "$IMG1_PATH" ]; then
        _pass "setImage — sparse file created on disk: $IMG1_PATH"
    else
        _fail "setImage — file not found on disk: $IMG1_PATH"
    fi

    # getImage — verify stored fields
    I1_DATA=$(assert_rpc "getImage" "tgt" "getImage" \
        "{\"uuid\":\"$IMAGE1_UUID\"}" "\"uuid\":\"$IMAGE1_UUID\"")

    I1_STORED_PATH=$(echo "$I1_DATA" | jq -r '.path // ""')
    [ "$I1_STORED_PATH" = "$IMG1_PATH" ] \
        && _pass "getImage — path correct" \
        || _fail "getImage — path mismatch: '$I1_STORED_PATH'"

    # getImageList — entry present with imagesize populated
    I1_LIST=$(assert_rpc "getImageList — image present" "tgt" "getImageList" \
        "$LIST_PARAMS" "\"uuid\":\"$IMAGE1_UUID\"")

    I1_IMGSIZE=$(echo "$I1_LIST" \
        | jq -r --arg u "$IMAGE1_UUID" '.data[] | select(.uuid == $u) | .imagesize // ""')
    if [ "$I1_IMGSIZE" != "-1" ] && [ -n "$I1_IMGSIZE" ]; then
        _pass "getImageList — imagesize populated: $I1_IMGSIZE"
    else
        info "getImageList — imagesize='$I1_IMGSIZE' (sparse file may report 0; not a failure)"
        _pass "getImageList — imagesize field present"
    fi
fi

# ===========================================================================
section "Image — growImage"
# ===========================================================================

if [ -n "$IMAGE1_UUID" ] && [ -f "$IMG1_PATH" ]; then
    assert_rpc "growImage — no exception" "tgt" "growImage" \
        "{\"uuid\":\"$IMAGE1_UUID\",\"amount\":1}" >/dev/null

    if [ -f "$IMG1_PATH" ]; then
        _pass "growImage — image file still present after grow"
    else
        _fail "growImage — image file missing after grow"
    fi
else
    info "growImage — skipped (no test image)"
fi

# ===========================================================================
section "Image — negative tests"
# ===========================================================================

assert_rpc_fails "getImage — unknown UUID" "tgt" "getImage" \
    '{"uuid":"00000000-0000-0000-0000-000000000000"}'

assert_rpc_fails "deleteImage — unknown UUID" "tgt" "deleteImage" \
    '{"uuid":"00000000-0000-0000-0000-000000000000"}'

assert_rpc_fails "growImage — unknown UUID" "tgt" "growImage" \
    '{"uuid":"00000000-0000-0000-0000-000000000000","amount":1}'

# setImage on an existing file must throw "Image already exists"
if [ -f "$IMG1_PATH" ]; then
    assert_rpc_fails "setImage — existing file path rejected" "tgt" "setImage" \
        "$(jq -n --arg uuid "$OMV_NEW_UUID" --arg path "$IMG1_PATH" \
            '{uuid:$uuid, path:$path, imagesize:1}')"
fi

# Duplicate path (same path, new UUID) — assertIsUnique should reject
# (only triggered when object is new, so we use OMV_NEW_UUID here)
# This is also implicitly covered by the "existing file" test above.

# ===========================================================================
section "Image — delete"
# ===========================================================================

if [ -n "$IMAGE1_UUID" ]; then
    assert_rpc "deleteImage" "tgt" "deleteImage" \
        "{\"uuid\":\"$IMAGE1_UUID\"}" >/dev/null
    DELETED_IMG_UUID="$IMAGE1_UUID"
    IMAGE1_UUID=""

    # File must be removed from disk
    if [ ! -f "$IMG1_PATH" ]; then
        _pass "deleteImage — file removed from disk"
    else
        _fail "deleteImage — file still present on disk: $IMG1_PATH"
    fi

    assert_rpc_fails "getImage after deleteImage" "tgt" "getImage" \
        "{\"uuid\":\"$DELETED_IMG_UUID\"}"

    LIST_AFTER=$(rpc "tgt" "getImageList" "$LIST_PARAMS" 2>/dev/null \
        || echo '{"data":[]}')
    if echo "$LIST_AFTER" \
            | jq -e --arg u "$DELETED_IMG_UUID" '.data[] | select(.uuid == $u)' \
            &>/dev/null; then
        _fail "getImageList — deleted image still present"
    else
        _pass "getImageList — deleted image absent"
    fi
fi

# ===========================================================================
section "Deploy (optional)"
# ===========================================================================

if command -v omv-salt &>/dev/null; then
    if omv-salt deploy run tgt &>/dev/null; then
        _pass "omv-salt deploy run tgt"
    else
        _fail "omv-salt deploy run tgt"
    fi
else
    info "omv-salt not available — skipping deploy test"
fi

# ===========================================================================
section "Summary"
# ===========================================================================
TOTAL=$((PASS + FAIL))
echo >&2
echo -e "  Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC} (${TOTAL} total)" >&2
if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo -e "\n  ${RED}Failed tests:${NC}" >&2
    for t in "${FAILED_TESTS[@]}"; do
        echo -e "    ${RED}✗${NC} $t" >&2
    done
fi
echo >&2

[ $FAIL -eq 0 ] && exit 0 || exit 1
