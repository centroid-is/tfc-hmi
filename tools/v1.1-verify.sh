#!/usr/bin/env bash
# v1.1-verify.sh — tfc-hmi3 v1.1 UMAS Hardening milestone acceptance gate.
#
# Orchestrates the four Phase 6 success criteria against the live M580 at
# 192.168.112.159 and reports pass/fail per requirement:
#
#   VERIFY-02 — Bug A (STRING-clamp) regression: `read stStatusElevator`
#               returns a real value, never the literal "underflow".
#   VERIFY-01 — FB visibility: `browse` reports non-zero FB children;
#               M_Elevator has at minimum its VAR_INPUT/VAR_OUTPUT members.
#   VERIFY-03 — Scalar pass-rate: `check` exits zero, baseline 35-scalar
#               pass rate preserved, new STRING leaves also pass.
#   TEST-03  — Test-suite regression: `dart test` under packages/tfc_dart
#               AND `flutter test` from repo root, both pass.
#
# Plus an Advantys STB no-regression smoke check (covered by the flutter
# test run; loud NOTE so this isn't a silent pass-through).
#
# Exit codes:
#   0 — v1.1 GATE: PASSED  (all checks passed, or dry-run completed)
#   1 — v1.1 GATE: FAILED  (one or more requirement checks failed)
#   2 — FATAL              (environmental abort: missing SDK / unreachable PLC)
#
# Usage:
#   tools/v1.1-verify.sh                  Live run (PLC required)
#   tools/v1.1-verify.sh --dry-run        Print commands without running
#   tools/v1.1-verify.sh --no-flutter     Skip flutter test (faster local sanity)
#   tools/v1.1-verify.sh --verbose        Echo per-command stdout
#   tools/v1.1-verify.sh --help

set -euo pipefail

# ─── Globals ───────────────────────────────────────────────────────────────────

PLC_HOST="${PLC_HOST:-192.168.112.159}"
PLC_PORT="${PLC_PORT:-502}"
PLC_UNIT="${PLC_UNIT:-255}"

# Resolve repo root (script lives in tools/ at the repo top).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DRY_RUN=0
NO_FLUTTER=0
VERBOSE=0

# Accumulator state
PASSES=0
FAILS=0
SKIPS=0
RESULTS=()

# ─── Arg parsing ───────────────────────────────────────────────────────────────

print_help() {
    cat <<'EOF'
v1.1-verify.sh — tfc-hmi3 v1.1 UMAS Hardening milestone acceptance gate

Usage:
  tools/v1.1-verify.sh [options]

Options:
  --dry-run        Print the commands each check would run; do not execute.
  --no-flutter     Skip the `flutter test` step (TEST-03 partial; recorded).
  -v, --verbose    Echo per-command stdout/stderr for live checks.
  -h, --help       Show this help and exit.

Environment overrides:
  PLC_HOST   (default: 192.168.112.159)
  PLC_PORT   (default: 502)
  PLC_UNIT   (default: 255)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)    DRY_RUN=1 ;;
        --no-flutter) NO_FLUTTER=1 ;;
        -v|--verbose) VERBOSE=1 ;;
        -h|--help)    print_help; exit 0 ;;
        *)            echo "[v1.1-verify] Unknown option: $1" >&2; print_help; exit 64 ;;
    esac
    shift
done

# ─── Logging helpers ───────────────────────────────────────────────────────────

log() { echo "[v1.1-verify] $*"; }
note() { echo "[v1.1-verify] NOTE: $*"; }
err() { echo "[v1.1-verify] ERROR: $*" >&2; }

record_pass() {
    local req="$1"; shift
    local note_text="$*"
    PASSES=$((PASSES + 1))
    RESULTS+=("PASS ${req} — ${note_text}")
}

record_fail() {
    local req="$1"; shift
    local note_text="$1"; shift
    local repro="$*"
    FAILS=$((FAILS + 1))
    RESULTS+=("FAIL ${req} — ${note_text} | repro: ${repro}")
}

record_skip() {
    local req="$1"; shift
    local reason="$*"
    SKIPS=$((SKIPS + 1))
    RESULTS+=("SKIP ${req} — ${reason}")
}

# Run a command (or print it in dry-run). Echoes the chosen mode.
# Usage: run_or_dry <label> -- <cmd> [args...]
# Returns the command's exit code (0 in dry-run).
run_or_dry() {
    local label="$1"; shift
    if [ "$1" = "--" ]; then shift; fi
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[v1.1-verify] DRY-RUN ${label}: $*"
        return 0
    fi
    if [ "$VERBOSE" -eq 1 ]; then
        log "RUN ${label}: $*"
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

# Run a command and capture its stdout into a global variable CAPTURED_OUTPUT.
# In dry-run, prints the command and sets CAPTURED_OUTPUT="" + returns 0.
CAPTURED_OUTPUT=""
CAPTURED_RC=0
run_capture() {
    local label="$1"; shift
    if [ "$1" = "--" ]; then shift; fi
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[v1.1-verify] DRY-RUN ${label}: $*"
        CAPTURED_OUTPUT=""
        CAPTURED_RC=0
        return 0
    fi
    if [ "$VERBOSE" -eq 1 ]; then
        log "RUN ${label}: $*"
    fi
    set +e
    CAPTURED_OUTPUT="$("$@" 2>&1)"
    CAPTURED_RC=$?
    set -e
    if [ "$VERBOSE" -eq 1 ]; then
        printf '%s\n' "$CAPTURED_OUTPUT"
    fi
}

# ─── Pre-flight ────────────────────────────────────────────────────────────────

preflight() {
    log "Pre-flight checks..."

    if ! command -v dart >/dev/null 2>&1; then
        err "dart not found on PATH"
        exit 2
    fi
    if ! command -v flutter >/dev/null 2>&1; then
        err "flutter not found on PATH"
        exit 2
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        err "python3 not found on PATH (used for inline JSON parsing)"
        exit 2
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY-RUN — skipping PLC reachability probe (${PLC_HOST}:${PLC_PORT})"
        return 0
    fi

    log "Probing PLC ${PLC_HOST}:${PLC_PORT}..."
    if ! nc -z -w 2 "$PLC_HOST" "$PLC_PORT" >/dev/null 2>&1; then
        err "PLC ${PLC_HOST}:${PLC_PORT} unreachable. Cannot run live gate."
        err "  repro: nc -z -w 2 ${PLC_HOST} ${PLC_PORT}"
        exit 2
    fi
    log "PLC reachable."
}

# ─── VERIFY-02: Bug A regression (STRING-clamp) ───────────────────────────────

check_verify_02() {
    log "VERIFY-02 — Bug A regression: read stStatusElevator must not say 'underflow'..."
    local cmd=(dart run packages/tfc_dart/tool/umas_cli.dart read "$PLC_HOST" stStatusElevator)
    local repro="(cd ${REPO_ROOT} && ${cmd[*]})"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[v1.1-verify] DRY-RUN VERIFY-02: ${cmd[*]}"
        record_pass "VERIFY-02" "dry-run stub (would run: read stStatusElevator, assert no 'underflow')"
        return 0
    fi

    pushd "$REPO_ROOT" >/dev/null
    run_capture "VERIFY-02" -- "${cmd[@]}"
    popd >/dev/null

    if [ "$CAPTURED_RC" -ne 0 ]; then
        record_fail "VERIFY-02" "umas_cli read exited ${CAPTURED_RC}" "$repro"
        return 0
    fi
    if echo "$CAPTURED_OUTPUT" | grep -qi 'underflow'; then
        record_fail "VERIFY-02" "output contains 'underflow' substring (Bug A regressed)" "$repro"
        return 0
    fi
    record_pass "VERIFY-02" "stStatusElevator read clean, no 'underflow' in output"
}

# ─── VERIFY-01: FB visibility (M_Elevator + 23 FB instances) ─────────────────

check_verify_01() {
    log "VERIFY-01 — FB visibility: M_Elevator and ≥23 FB instances must expand..."
    local cmd=(dart run packages/tfc_dart/tool/umas_cli.dart browse "$PLC_HOST")
    local repro="(cd ${REPO_ROOT} && ${cmd[*]})"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[v1.1-verify] DRY-RUN VERIFY-01: ${cmd[*]}"
        record_pass "VERIFY-01" "dry-run stub (would run: browse, count M_Elevator children + FB instances)"
        return 0
    fi

    pushd "$REPO_ROOT" >/dev/null
    run_capture "VERIFY-01" -- "${cmd[@]}"
    popd >/dev/null

    if [ "$CAPTURED_RC" -ne 0 ]; then
        record_fail "VERIFY-01" "umas_cli browse exited ${CAPTURED_RC}" "$repro"
        return 0
    fi

    # Parse with python3:
    #   - tree output is indented by 2 spaces per depth from _printTree.
    #   - A node has children iff the line immediately following it is more indented.
    #   - FB instances are heuristically identified as nodes whose name matches M_*,
    #     FB_*, fb*, etc. We don't have a perfect FB-vs-non-FB classifier from the
    #     browse output alone, so we additionally use the known-target count from
    #     the ROADMAP: ≥23 FB instances must have ≥1 child.
    #   - The strict assertion is on M_Elevator (line containing "M_Elevator") having
    #     ≥1 child. The wider 23-instance count is reported as supporting evidence.
    local parser
    parser=$(cat <<'PYEOF'
import sys, re

text = sys.stdin.read()
lines = text.splitlines()

def indent_of(s):
    return len(s) - len(s.lstrip(' '))

def has_child(idx, lines):
    if idx + 1 >= len(lines):
        return False
    cur = indent_of(lines[idx])
    nxt_line = lines[idx + 1]
    if not nxt_line.strip():
        return False
    return indent_of(nxt_line) > cur

# Locate variable lines (skip blank / "N root(s)" header lines).
var_lines = []
for i, ln in enumerate(lines):
    if not ln.strip():
        continue
    if re.match(r'^\d+ root', ln):
        continue
    # umas_cli printTree emits: "{indent}{name}  ({type}){addr}"
    if '(' in ln and ')' in ln:
        var_lines.append(i)

# M_Elevator check
m_elev_idx = None
for i in var_lines:
    name_part = lines[i].lstrip().split('  (')[0]
    if name_part == 'M_Elevator':
        m_elev_idx = i
        break

m_elev_has_child = (m_elev_idx is not None) and has_child(m_elev_idx, lines)

# FB-instance count (heuristic): any top-level-ish variable whose name
# starts with M_ or FB_ (case-insensitive), counted iff it has ≥1 child.
fb_with_children = 0
fb_total = 0
for i in var_lines:
    name_part = lines[i].lstrip().split('  (')[0]
    if re.match(r'^(M_|FB_|fb)', name_part):
        fb_total += 1
        if has_child(i, lines):
            fb_with_children += 1

print(f'm_elev_found={m_elev_idx is not None}')
print(f'm_elev_has_child={m_elev_has_child}')
print(f'fb_total={fb_total}')
print(f'fb_with_children={fb_with_children}')
PYEOF
)

    local parsed
    parsed=$(printf '%s\n' "$CAPTURED_OUTPUT" | python3 -c "$parser")

    local m_elev_found m_elev_has_child fb_total fb_with_children
    m_elev_found=$(echo "$parsed" | grep '^m_elev_found=' | cut -d= -f2)
    m_elev_has_child=$(echo "$parsed" | grep '^m_elev_has_child=' | cut -d= -f2)
    fb_total=$(echo "$parsed" | grep '^fb_total=' | cut -d= -f2)
    fb_with_children=$(echo "$parsed" | grep '^fb_with_children=' | cut -d= -f2)

    if [ "$m_elev_found" != "True" ]; then
        record_fail "VERIFY-01" "M_Elevator node not found in browse output" "$repro"
        return 0
    fi
    if [ "$m_elev_has_child" != "True" ]; then
        record_fail "VERIFY-01" "M_Elevator has zero children (FB visibility regressed)" "$repro"
        return 0
    fi
    if [ "${fb_with_children:-0}" -lt 23 ]; then
        record_fail "VERIFY-01" "only ${fb_with_children}/${fb_total} FB instances have children (target ≥23)" "$repro"
        return 0
    fi
    record_pass "VERIFY-01" "M_Elevator expands; ${fb_with_children}/${fb_total} FB instances have ≥1 child"
}

# ─── VERIFY-03: check exits zero with baseline scalar pass-rate ──────────────

check_verify_03() {
    log "VERIFY-03 — check must exit 0 with ≥35 scalars passing, 0 scalar/array fails..."
    local cmd=(dart run packages/tfc_dart/tool/umas_cli.dart check "$PLC_HOST" --json)
    local repro="(cd ${REPO_ROOT} && ${cmd[*]})"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[v1.1-verify] DRY-RUN VERIFY-03: ${cmd[*]}"
        record_pass "VERIFY-03" "dry-run stub (would run: check --json, assert scalars.ok>=35 and 0 fails)"
        return 0
    fi

    pushd "$REPO_ROOT" >/dev/null
    run_capture "VERIFY-03" -- "${cmd[@]}"
    popd >/dev/null

    if [ "$CAPTURED_RC" -ne 0 ]; then
        record_fail "VERIFY-03" "umas_cli check exited ${CAPTURED_RC}" "$repro"
        return 0
    fi

    local parsed
    parsed=$(printf '%s\n' "$CAPTURED_OUTPUT" | python3 -c '
import sys, json
raw = sys.stdin.read()
# `dart run` emits "Running build hooks..." to stderr (captured here via
# `2>&1` in run_capture) before the actual JSON. Strip everything before
# the first "{" so json.loads sees clean JSON.
brace = raw.find("{")
if brace > 0:
    raw = raw[brace:]
try:
    d = json.loads(raw)
except Exception as e:
    print("parse_error=" + str(e))
    sys.exit(0)
scalars = d.get("scalars", {})
arrays = d.get("arrays", {})
print("scalars_ok=" + str(scalars.get("ok", 0)))
print("scalars_fail=" + str(scalars.get("fail", 0)))
print("arrays_ok=" + str(arrays.get("ok", 0)))
print("arrays_fail=" + str(arrays.get("fail", 0)))
print("arrays_fb_in_out=" + str(arrays.get("fb_in_out", 0)))
')

    if echo "$parsed" | grep -q '^parse_error='; then
        record_fail "VERIFY-03" "JSON parse failure on check output" "$repro"
        return 0
    fi

    local scalars_ok scalars_fail arrays_fail
    scalars_ok=$(echo "$parsed" | grep '^scalars_ok=' | cut -d= -f2)
    scalars_fail=$(echo "$parsed" | grep '^scalars_fail=' | cut -d= -f2)
    arrays_fail=$(echo "$parsed" | grep '^arrays_fail=' | cut -d= -f2)

    if [ "${scalars_fail:-1}" -ne 0 ]; then
        record_fail "VERIFY-03" "${scalars_fail} scalar(s) failed (baseline expects 0)" "$repro"
        return 0
    fi
    if [ "${arrays_fail:-1}" -ne 0 ]; then
        record_fail "VERIFY-03" "${arrays_fail} array element(s) failed (baseline expects 0)" "$repro"
        return 0
    fi
    if [ "${scalars_ok:-0}" -lt 35 ]; then
        record_fail "VERIFY-03" "only ${scalars_ok} scalars passed (baseline expects ≥35)" "$repro"
        return 0
    fi
    record_pass "VERIFY-03" "${scalars_ok} scalars ok, 0 fails (arrays also clean)"
}

# ─── TEST-03: dart test + flutter test ────────────────────────────────────────

check_test_03() {
    log "TEST-03 — regression suite: packages/tfc_dart dart test + repo-root flutter test..."

    local dart_repro="(cd ${REPO_ROOT}/packages/tfc_dart && dart test)"
    local flutter_repro="(cd ${REPO_ROOT} && flutter test)"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[v1.1-verify] DRY-RUN TEST-03 (a): cd packages/tfc_dart && dart test"
        echo "[v1.1-verify] DRY-RUN TEST-03 (b): flutter test"
        record_pass "TEST-03" "dry-run stub (would run: dart test in packages/tfc_dart + flutter test at root)"
        return 0
    fi

    local dart_rc=0 flutter_rc=0

    pushd "$REPO_ROOT/packages/tfc_dart" >/dev/null
    if [ "$VERBOSE" -eq 1 ]; then
        dart test || dart_rc=$?
    else
        dart test >/dev/null 2>&1 || dart_rc=$?
    fi
    popd >/dev/null

    if [ "$dart_rc" -ne 0 ]; then
        record_fail "TEST-03" "dart test (packages/tfc_dart) exited ${dart_rc}" "$dart_repro"
        return 0
    fi

    if [ "$NO_FLUTTER" -eq 1 ]; then
        record_skip "TEST-03" "flutter test skipped via --no-flutter (partial coverage; orchestrator MUST NOT use this for the milestone gate)"
        return 0
    fi

    pushd "$REPO_ROOT" >/dev/null
    if [ "$VERBOSE" -eq 1 ]; then
        flutter test || flutter_rc=$?
    else
        flutter test >/dev/null 2>&1 || flutter_rc=$?
    fi
    popd >/dev/null

    if [ "$flutter_rc" -ne 0 ]; then
        record_fail "TEST-03" "flutter test (repo root) exited ${flutter_rc}" "$flutter_repro"
        return 0
    fi

    record_pass "TEST-03" "dart test + flutter test both green"
}

# ─── STB no-regression smoke ──────────────────────────────────────────────────

check_stb_smoke() {
    log "STB-SMOKE — Advantys STB no-regression (PR #121 fixture covered by flutter test)..."

    local fixture="test/page_creator/assets/advantys_stb_test.dart"
    if [ ! -f "$REPO_ROOT/$fixture" ]; then
        note "STB fixture not present at ${fixture} — this is a real regression signal."
        record_fail "STB-SMOKE" "fixture ${fixture} missing" "ls ${REPO_ROOT}/${fixture}"
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[v1.1-verify] DRY-RUN STB-SMOKE: fixture present at ${fixture}; covered by flutter test"
        record_pass "STB-SMOKE" "dry-run stub (fixture present; live coverage via flutter test)"
        return 0
    fi

    if [ "$NO_FLUTTER" -eq 1 ]; then
        record_skip "STB-SMOKE" "flutter test skipped — STB coverage NOT verified this run"
        return 0
    fi

    # If we got this far, TEST-03 (flutter test) already ran and passed (otherwise
    # we'd have a recorded FAIL). The STB fixture is part of that run.
    note "STB fixture coverage relies on the flutter test pass above. No live STB rig is in scope for v1.1 — that's a v2 milestone candidate."
    record_pass "STB-SMOKE" "fixture covered by flutter test (no live STB rig in v1.1 scope)"
}

# ─── Summary ───────────────────────────────────────────────────────────────────

print_summary() {
    echo
    echo "────────────────────────────────────────────────────────────────────"
    echo "v1.1 UMAS Hardening — milestone acceptance summary"
    echo "────────────────────────────────────────────────────────────────────"
    for r in "${RESULTS[@]}"; do
        echo "  $r"
    done
    echo "────────────────────────────────────────────────────────────────────"
    echo "  totals: ${PASSES} pass / ${FAILS} fail / ${SKIPS} skip"
    echo "────────────────────────────────────────────────────────────────────"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "v1.1 GATE: DRY-RUN OK (no checks executed)"
        exit 0
    fi
    if [ "$FAILS" -eq 0 ]; then
        echo "v1.1 GATE: PASSED"
        exit 0
    fi
    echo "v1.1 GATE: FAILED (${FAILS} failures)"
    exit 1
}

# ─── Main ──────────────────────────────────────────────────────────────────────

main() {
    log "Starting v1.1 UMAS Hardening acceptance gate (host=${PLC_HOST}:${PLC_PORT} unit=${PLC_UNIT})"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "Mode: DRY-RUN — no commands executed."
    fi
    if [ "$NO_FLUTTER" -eq 1 ]; then
        log "Mode: --no-flutter — flutter test will be skipped (partial TEST-03)."
    fi

    preflight
    check_verify_02
    check_verify_01
    check_verify_03
    check_test_03
    check_stb_smoke
    print_summary
}

main "$@"
