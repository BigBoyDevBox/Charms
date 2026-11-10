#!/bin/bash
# End-to-end check of the built app: drives dist/Charms.app with real key
# events against the CharmsHarness text host and compares what arrives.
#
#   scripts/e2e.sh [scenario ...]      run all scenarios, or only the named ones
#
# Needs a built app (scripts/build-app.sh) and a terminal that has the
# Accessibility permission, which the app started from here inherits. It
# types and moves windows on the real screen for about a minute: do not use
# the keyboard meanwhile. Charms runs with CHARMS_HOME pointing at a temporary
# directory, so your own favourites and settings are neither read nor changed.
#
# Exit status: 0 all passed, 1 a scenario failed, 77 could not run here.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${CHARMS_BUILD_DIR:-$ROOT/.build}"
APP="${CHARMS_APP:-$ROOT/dist/Charms.app}"
# Key code of the default shortcut, Control-P (the P position on any layout).
SHORTCUT_CODE=35

skip() { echo "e2e: $1" >&2; exit 77; }

[[ -x "$APP/Contents/MacOS/Charms" ]] || skip "no app at $APP; run scripts/build-app.sh first"
pgrep -x Charms >/dev/null && skip "Charms is already running; quit it first"

swift build --product CharmsHarness --scratch-path "$BUILD_DIR" >/dev/null || skip "the harness did not build"
HARNESS="$(swift build --product CharmsHarness --scratch-path "$BUILD_DIR" --show-bin-path)/CharmsHarness"

field() { plutil -extract "$1" raw -o - - 2>/dev/null; }

[[ "$("$HARNESS" focused | field trusted)" == "true" ]] \
    || skip "this terminal lacks the Accessibility permission (System Settings, Privacy & Security)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/charms-e2e.XXXXXX")"
TRACE="$WORK/trace.log"
HOST_PID=""
APP_PID=""
SAVED_CLIPBOARD="$(pbpaste 2>/dev/null || true)"

cleanup() {
    # `wait` collects them quietly; otherwise the shell reports each as
    # "Terminated".
    for pid in $APP_PID $HOST_PID; do
        kill "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
    done
    printf '%s' "$SAVED_CLIPBOARD" | pbcopy
    rm -rf "$WORK"
}
trap cleanup EXIT

# The host runs from a bundle so that it has a bundle identifier, which the
# per-application settings are keyed by.
HOST_ID=ch.lkmc.CharmsHarness
HOST_APP="$WORK/CharmsHarness.app"
mkdir -p "$HOST_APP/Contents/MacOS"
cp "$HARNESS" "$HOST_APP/Contents/MacOS/CharmsHarness"
cat > "$HOST_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$HOST_ID</string>
<key>CFBundleName</key><string>Charms Harness</string>
<key>CFBundleExecutable</key><string>CharmsHarness</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
"$HOST_APP/Contents/MacOS/CharmsHarness" host --x 240 --y 860 > "$WORK/host.log" 2>&1 &
HOST_PID=$!

# Starts Charms with the given preferences document, replacing a running one.
CURRENT_PREFERENCES=""
start_charms() {
    [[ "$1" == "$CURRENT_PREFERENCES" ]] && return 0
    if [[ -n "$APP_PID" ]]; then
        kill "$APP_PID" 2>/dev/null
        wait "$APP_PID" 2>/dev/null
    fi
    printf '%s' "$1" > "$WORK/preferences.json"
    : > "$TRACE"
    CHARMS_HOME="$WORK" CHARMS_SKIP_ONBOARDING=1 CHARMS_TRACE=1 "$APP/Contents/MacOS/Charms" > /dev/null 2>> "$TRACE" &
    APP_PID=$!
    CURRENT_PREFERENCES="$1"
    for _ in $(seq 1 100); do
        grep -q "catalogue-loaded" "$TRACE" 2>/dev/null && return 0
        sleep 0.1
    done
    return 1
}

# --- helpers -----------------------------------------------------------------

send() { "$HARNESS" send "$@"; }
editor() { send --op state | field editor; }
press() { "$HARNESS" key --name "$@" >/dev/null; }
shortcut() { "$HARNESS" hotkey --code "$SHORTCUT_CODE" --control >/dev/null; }
typing() { "$HARNESS" type --text "$1" --gap-ms "${2:-25}" >/dev/null; }
clipboard() { "$HARNESS" pasteboard | field string; }
clipboard_count() { "$HARNESS" pasteboard | field changeCount; }

# Waits until the trace has a line matching $1 after line number $2.
await() {
    local pattern="$1" from="$2" tries=0
    while (( tries < 150 )); do
        tail -n +"$((from + 1))" "$TRACE" | grep -q -- "$pattern" && return 0
        sleep 0.02
        tries=$((tries + 1))
    done
    return 1
}
mark() { wc -l < "$TRACE" | tr -d ' '; }

# Puts the host in front with the given text and the caret at its end.
reset() {
    press escape
    send --op activate >/dev/null
    send --op focus --target editor >/dev/null
    send --op setText --text "$1" >/dev/null
    sleep 0.15
}

FAILURE=""
expect() {
    # expect <what> <actual> <wanted>; bash compares bytes, so canonically
    # equivalent but different strings do not pass for each other.
    [[ "$2" == "$3" ]] && return 0
    FAILURE="$1: got '$2', wanted '$3'"
    return 1
}

open_picker() {
    local from; from="$(mark)"
    shortcut
    await "presented-" "$from" || { FAILURE="the picker did not open"; return 1; }
}

choose() {
    # choose <query> [key options...]: type a query and press Return.
    local from; from="$(mark)"
    typing "$1"
    shift
    press return "$@"
    await "outcome-" "$from" || { FAILURE="the session did not end"; return 1; }
    sleep 0.15
}

# --- scenarios ---------------------------------------------------------------

scenario_insert() {
    reset "A "
    local count; count="$(clipboard_count)"
    open_picker && choose "arrow" || return 1
    expect "text" "$(editor)" "A →" || return 1
    expect "clipboard change count" "$(clipboard_count)" "$count" || return 1
    send --op undo >/dev/null
    expect "text after one undo" "$(editor)" "A "
}

scenario_escape() {
    reset "A "
    local count; count="$(clipboard_count)"
    open_picker || return 1
    typing "heart"
    press escape
    sleep 0.3
    expect "text" "$(editor)" "A " || return 1
    expect "clipboard change count" "$(clipboard_count)" "$count" || return 1
    expect "key window" "$(send --op state | field isKeyWindow)" "true"
}

scenario_replace_selection() {
    reset "A xyz"
    send --op select --location 2 --length 3 >/dev/null
    open_picker && choose "check" || return 1
    expect "text" "$(editor)" "A ✓"
}

scenario_sequence() {
    # A joined emoji sequence has to arrive scalar for scalar.
    reset ""
    open_picker && choose "technologist" || return 1
    expect "text" "$(editor)" "$(printf '\xf0\x9f\xa7\x91\xe2\x80\x8d\xf0\x9f\x92\xbb')"
}

scenario_navigate() {
    reset ""
    open_picker || return 1
    local from; from="$(mark)"
    typing "arrow"
    press right
    press return
    await "outcome-" "$from" || { FAILURE="the session did not end"; return 1; }
    sleep 0.15
    expect "text" "$(editor)" "←"
}

scenario_copy() {
    reset "A "
    open_picker && choose "infinity" --command || return 1
    expect "text" "$(editor)" "A " || return 1
    expect "clipboard" "$(clipboard)" "∞"
}

scenario_placement() {
    # The picker is on the caret's display, beside the caret and not over
    # the line being typed.
    reset "The caret is at the end of this line"
    local caret picker
    caret="$("$HARNESS" focused)"
    open_picker || return 1
    picker="$("$HARNESS" windows --pid "$APP_PID")"
    press escape
    local cx cy ch px py pw ph index=0 found=""
    cx="$(field caretBounds.0 <<< "$caret")"; cy="$(field caretBounds.1 <<< "$caret")"; ch="$(field caretBounds.3 <<< "$caret")"
    # The status item is a window too; the picker is the wide one.
    while pw="$(field "windows.$index.bounds.2" <<< "$picker")" && [[ -n "$pw" ]]; do
        if awk "BEGIN { exit !($pw > 300) }"; then found="$index"; break; fi
        index=$((index + 1))
    done
    [[ -n "$found" ]] || { FAILURE="no picker window on screen"; return 1; }
    px="$(field "windows.$found.bounds.0" <<< "$picker")"; py="$(field "windows.$found.bounds.1" <<< "$picker")"
    ph="$(field "windows.$found.bounds.3" <<< "$picker")"
    awk "BEGIN { exit !(($py >= $cy + $ch) || ($py + $ph <= $cy)) }" \
        || { FAILURE="picker (y $py, height $ph) covers the caret line (y $cy, height $ch)"; return 1; }
    awk "BEGIN { exit !($px <= $cx && $cx <= $px + $pw) }" \
        || { FAILURE="picker (x $px, width $pw) is not at the caret (x $cx)"; return 1; }
}

# Top-left corner of the picker window while it is open, as "x y".
picker_origin() {
    local windows index=0 width
    windows="$("$HARNESS" windows --pid "$APP_PID")"
    while width="$(field "windows.$index.bounds.2" <<< "$windows")" && [[ -n "$width" ]]; do
        if awk "BEGIN { exit !($width > 300) }"; then
            echo "$(field "windows.$index.bounds.0" <<< "$windows") $(field "windows.$index.bounds.1" <<< "$windows")"
            return 0
        fi
        index=$((index + 1))
    done
    return 1
}

scenario_click_cell() {
    reset ""
    open_picker || return 1
    local from origin px py
    from="$(mark)"
    typing "arrow"
    sleep 0.2
    origin="$(picker_origin)" || { FAILURE="no picker window on screen"; return 1; }
    read -r px py <<< "$origin"
    # The second cell of the first row: 12 points of padding, cells of 44
    # with 2 between them, under a 46 point search area.
    "$HARNESS" click --x "$(awk "BEGIN { print $px + 12 + 46 + 22 }")" --y "$(awk "BEGIN { print $py + 46 + 12 + 22 }")" >/dev/null
    await "outcome-" "$from" || { FAILURE="the click did not end the session"; return 1; }
    sleep 0.15
    expect "text" "$(editor)" "←"
}

scenario_click_outside() {
    # A click anywhere else closes the picker and changes nothing.
    reset "A "
    open_picker || return 1
    local from frame height x y
    from="$(mark)"
    typing "arrow"
    frame="$(send --op state)"
    height="$("$HARNESS" displays | field displays.0.frame.3)"
    x="$(awk "BEGIN { print $(field windowFrame.0 <<< "$frame") + $(field windowFrame.2 <<< "$frame") / 2 }")"
    # The title bar of the host window, converted to top-left coordinates.
    y="$(awk "BEGIN { print $height - ($(field windowFrame.1 <<< "$frame") + $(field windowFrame.3 <<< "$frame")) + 12 }")"
    "$HARNESS" click --x "$x" --y "$y" >/dev/null
    await "outcome-cancelled" "$from" || { FAILURE="clicking outside did not cancel"; return 1; }
    expect "text" "$(editor)" "A "
}

scenario_cancel_while_held() {
    # Escape pressed while Return is still down. The picker keeps the
    # keyboard until Return comes up, so that the held key cannot repeat
    # into the document; then it closes without inserting.
    reset "A "
    open_picker || return 1
    local from holder; from="$(mark)"
    typing "arrow"
    "$HARNESS" key --name return --hold-ms 900 >/dev/null &
    holder=$!
    sleep 0.25
    press escape
    if ! picker_origin >/dev/null; then
        wait "$holder"
        FAILURE="the picker closed while Return was still held"
        return 1
    fi
    wait "$holder"
    await "outcome-cancelled" "$from" || { FAILURE="the session was not cancelled"; return 1; }
    sleep 0.15
    expect "text" "$(editor)" "A "
}

scenario_paste_backend() {
    # For applications set to "insert by pasting".
    reset "A "
    "$HARNESS" pasteboard --set "KEEP" >/dev/null
    local from; from="$(mark)"
    open_picker && choose "arrow" || return 1
    expect "text" "$(editor)" "A →" || return 1
    tail -n +"$((from + 1))" "$TRACE" | grep -q "sent-paste" || { FAILURE="the paste backend was not used"; return 1; }
    sleep 1
    # The clipboard is put back unless the system would have had to ask
    # before letting Charms read it; then it is left alone.
    if ! tail -n +"$((from + 1))" "$TRACE" | grep -q "clipboard-snapshot-skipped"; then
        expect "clipboard after restore" "$(clipboard)" "KEEP" || return 1
    fi
}

scenario_pass_through() {
    # In a listed application the shortcut belongs to that application:
    # Control-P moves the caret up a line there and Charms stays closed.
    reset "$(printf 'one\ntwo')"
    local from; from="$(mark)"
    shortcut
    sleep 0.4
    if tail -n +"$((from + 1))" "$TRACE" | grep -q "invoked-"; then
        FAILURE="the picker opened in a pass-through application"
        return 1
    fi
    expect "caret position" "$(send --op state | field editorSelection.0)" "3"
}

scenario_typed_trigger() {
    reset "x "
    local from; from="$(mark)"
    typing "::arrow"
    await "presented-" "$from" || { FAILURE="typing :: did not open the picker"; return 1; }
    press return
    await "outcome-" "$from" || { FAILURE="the session did not end"; return 1; }
    sleep 0.15
    expect "text" "$(editor)" "x →"
}

scenario_typed_trigger_fast() {
    reset "x "
    local from; from="$(mark)"
    typing "::check" 6
    await "presented-" "$from" || { FAILURE="typing :: did not open the picker"; return 1; }
    sleep 0.3
    press return
    await "outcome-" "$from" || { FAILURE="the session did not end"; return 1; }
    sleep 0.15
    expect "text" "$(editor)" "x ✓"
}

scenario_typed_trigger_escape() {
    # Escape leaves the colons exactly as typed.
    reset "x "
    local from; from="$(mark)"
    typing "::ar"
    await "presented-" "$from" || { FAILURE="typing :: did not open the picker"; return 1; }
    press escape
    sleep 0.3
    expect "text" "$(editor)" "x ::"
}

scenario_colons_inside_a_word() {
    reset ""
    local from; from="$(mark)"
    typing "std::cout"
    sleep 0.4
    expect "text" "$(editor)" "std::cout" || return 1
    if tail -n +"$((from + 1))" "$TRACE" | grep -q "invoked-"; then
        FAILURE="colons inside a word opened the picker"
        return 1
    fi
}

scenario_password_field() {
    # Nothing is ever sent into a password field; Return copies instead.
    reset "A "
    send --op focus --target secret >/dev/null
    sleep 0.15
    open_picker && choose "arrow" || return 1
    expect "password field length" "$(send --op state | field secretLength)" "0" || return 1
    expect "text" "$(editor)" "A " || return 1
    expect "clipboard" "$(clipboard)" "→"
}

ALL=(insert escape replace_selection sequence navigate copy placement click_cell click_outside cancel_while_held
     typed_trigger typed_trigger_fast typed_trigger_escape colons_inside_a_word password_field
     paste_backend pass_through)

# The preferences a scenario runs with. Charms is restarted when they change.
preferences_for() {
    case "$1" in
        paste_backend) echo "{\"pasteApplications\": [\"$HOST_ID\"]}" ;;
        pass_through) echo "{\"shortcutPassThrough\": [\"$HOST_ID\"]}" ;;
        *) echo '{"typedTriggerEnabled": true}' ;;
    esac
}

# --- run ---------------------------------------------------------------------

for _ in $(seq 1 100); do
    grep -q '"ready"' "$WORK/host.log" 2>/dev/null && break
    sleep 0.1
done
grep -q '"ready"' "$WORK/host.log" 2>/dev/null || skip "the test window did not open"
start_charms "$(preferences_for insert)" || skip "Charms did not start"
grep -q "insertion-enabled" "$TRACE" || skip "Charms started without the Accessibility permission"

failed=0
for name in "${@:-${ALL[@]}}"; do
    declare -F "scenario_$name" >/dev/null || { echo "e2e: unknown scenario '$name'" >&2; exit 2; }
    FAILURE=""
    start_charms "$(preferences_for "$name")" || { echo "FAIL  $name: Charms did not restart"; failed=1; continue; }
    # Another application taking the foreground cancels a session, as it
    # should. That is the screen's doing, not the app's: try once more.
    if "scenario_$name" || { sleep 1; FAILURE=""; "scenario_$name"; }; then
        echo "ok    $name"
    else
        echo "FAIL  $name: $FAILURE"
        # What the app recorded last, to see where the session went.
        tail -n 12 "$TRACE" | sed 's/^/        /'
        failed=1
    fi
done
press escape

exit "$failed"
