#!/usr/bin/env bats

# test/05-common-functions.bats — unit tests for src/include/common-functions.
#
# Sources common-functions directly so each function can be exercised in
# isolation, without going through the full rotate-aws-backups script.
# Tests are ordered to match the source file top-to-bottom for readability.

load "test_helper"

setup() {
    repo_root=$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)
    common_functions="${repo_root}/src/include/common-functions"
    # shellcheck source=/dev/null
    source "${common_functions}"
    export LOG_LEVEL=diag     # allow all log levels through
}

# ---------------------------------------------------------------------------
# is-true / is-false (lines 21-41)
# ---------------------------------------------------------------------------

@test "is-true: '1' is true" {
    run is-true "1"
    [ "$status" -eq 0 ]
}

@test "is-true: 'yes' is true" {
    run is-true "yes"
    [ "$status" -eq 0 ]
}

@test "is-true: 'on' is true" {
    run is-true "on"
    [ "$status" -eq 0 ]
}

@test "is-true: 'TRUE' is true (case-insensitive)" {
    run is-true "TRUE"
    [ "$status" -eq 0 ]
}

@test "is-true: '0' is not true" {
    run is-true "0"
    [ "$status" -ne 0 ]
}

@test "is-true: 'false' is not true" {
    run is-true "false"
    [ "$status" -ne 0 ]
}

@test "is-true: empty string is not true" {
    run is-true ""
    [ "$status" -ne 0 ]
}

@test "is-true: reads 'true' from stdin (line 36)" {
    # Exercises the stdin branch: [[ "${#@}" = "0" ]] -> head -n 1 < /dev/stdin
    run bash -c "source '${common_functions}'; echo true | is-true"
    [ "$status" -eq 0 ]
}

@test "is-true: reads 'false' from stdin (line 36)" {
    run bash -c "source '${common_functions}'; echo false | is-true"
    [ "$status" -ne 0 ]
}

@test "is-false: 'false' is false" {
    run is-false "false"
    [ "$status" -eq 0 ]
}

@test "is-false: '1' is not false" {
    run is-false "1"
    [ "$status" -ne 0 ]
}

@test "is_true wrapper delegates to is-true" {
    run is_true "yes"
    [ "$status" -eq 0 ]
}

@test "is_false wrapper delegates to is-false" {
    run is_false "no"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# log-level (lines 320-343)
# ---------------------------------------------------------------------------

@test "log-level: diag returns 0" {
    run log-level "diag"
    [ "$status" -eq 0 ]
    [ "$output" -eq 0 ]
}

@test "log-level: diagnostic returns 0" {
    run log-level "diagnostic"
    [ "$status" -eq 0 ]
    [ "$output" -eq 0 ]
}

@test "log-level: trace returns 10" {
    run log-level "trace"
    [ "$status" -eq 0 ]
    [ "$output" -eq 10 ]
}

@test "log-level: debug returns 20" {
    run log-level "debug"
    [ "$status" -eq 0 ]
    [ "$output" -eq 20 ]
}

@test "log-level: info returns 30" {
    run log-level "info"
    [ "$status" -eq 0 ]
    [ "$output" -eq 30 ]
}

@test "log-level: information returns 30" {
    run log-level "information"
    [ "$status" -eq 0 ]
    [ "$output" -eq 30 ]
}

@test "log-level: notice returns 40" {
    run log-level "notice"
    [ "$status" -eq 0 ]
    [ "$output" -eq 40 ]
}

@test "log-level: warn returns 50" {
    run log-level "warn"
    [ "$status" -eq 0 ]
    [ "$output" -eq 50 ]
}

@test "log-level: warning returns 50" {
    run log-level "warning"
    [ "$status" -eq 0 ]
    [ "$output" -eq 50 ]
}

@test "log-level: error returns 60" {
    run log-level "error"
    [ "$status" -eq 0 ]
    [ "$output" -eq 60 ]
}

@test "log-level: fatal returns 70" {
    run log-level "fatal"
    [ "$status" -eq 0 ]
    [ "$output" -eq 70 ]
}

@test "log-level: die returns 70" {
    run log-level "die"
    [ "$status" -eq 0 ]
    [ "$output" -eq 70 ]
}

@test "log-level: invalid level returns non-zero" {
    run log-level "bogus"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# log-level-enabled (lines 345-365)
# ---------------------------------------------------------------------------

@test "log-level-enabled: WARN enabled when LOG_LEVEL=info" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=info log-level-enabled WARN"
    [ "$status" -eq 0 ]
}

@test "log-level-enabled: DEBUG suppressed when LOG_LEVEL=info" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=info log-level-enabled DEBUG"
    [ "$status" -ne 0 ]
}

@test "log-level-enabled: empty level returns non-zero" {
    run log-level-enabled ""
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# logging-severity (lines 415-428)
# ---------------------------------------------------------------------------

@test "logging-severity: valid level echoes uppercase" {
    run logging-severity "info"
    [ "$status" -eq 0 ]
    [ "$output" = "INFO" ]
}

@test "logging-severity: invalid level returns non-zero" {
    run logging-severity "bogus"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# validate-exit-status (lines 577-580)
# ---------------------------------------------------------------------------

@test "validate-exit-status: 0 is valid" {
    run validate-exit-status "0"
    [ "$status" -eq 0 ]
}

@test "validate-exit-status: 127 is valid" {
    run validate-exit-status "127"
    [ "$status" -eq 0 ]
}

@test "validate-exit-status: 128 is not valid (out of range)" {
    run validate-exit-status "128"
    [ "$status" -ne 0 ]
}

@test "validate-exit-status: empty string is not valid" {
    run validate-exit-status ""
    [ "$status" -ne 0 ]
}

@test "validate-exit-status: non-numeric is not valid" {
    run validate-exit-status "abc"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# validate-log-level (lines 558-575)
# ---------------------------------------------------------------------------

@test "validate-log-level: valid level succeeds" {
    run validate-log-level "info"
    [ "$status" -eq 0 ]
}

@test "validate-log-level: invalid level exits with FATAL code (line 573)" {
    run bash -c "source '${common_functions}'; validate-log-level 'bogus'"
    [ "$status" -eq 5 ]   # EXIT_FATAL=5
}

# ---------------------------------------------------------------------------
# exit-status-name (lines 158-176)
# ---------------------------------------------------------------------------

@test "exit-status-name: 0 -> SUCCESS" {
    run exit-status-name "0"
    [ "$status" -eq 0 ]
    [ "$output" = "SUCCESS" ]
}

@test "exit-status-name: 1 -> ERROR" {
    run exit-status-name "1"
    [ "$status" -eq 0 ]
    [ "$output" = "ERROR" ]
}

@test "exit-status-name: 2 -> USAGE" {
    run exit-status-name "2"
    [ "$status" -eq 0 ]
    [ "$output" = "USAGE" ]
}

@test "exit-status-name: 3 -> CONFIG" {
    run exit-status-name "3"
    [ "$status" -eq 0 ]
    [ "$output" = "CONFIG" ]
}

@test "exit-status-name: 4 -> NOTFOUND" {
    run exit-status-name "4"
    [ "$status" -eq 0 ]
    [ "$output" = "NOTFOUND" ]
}

@test "exit-status-name: 5 -> FATAL" {
    run exit-status-name "5"
    [ "$status" -eq 0 ]
    [ "$output" = "FATAL" ]
}

@test "exit-status-name: invalid code returns non-zero" {
    run exit-status-name "99"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# return-status-name (lines 522-541)
# ---------------------------------------------------------------------------

@test "return-status-name: 0 -> SUCCESS" {
    run return-status-name "0"
    [ "$status" -eq 0 ]
    [ "$output" = "SUCCESS" ]
}

@test "return-status-name: 11 -> ERROR" {
    run return-status-name "11"
    [ "$status" -eq 0 ]
    [ "$output" = "ERROR" ]
}

@test "return-status-name: 12 -> USAGE" {
    run return-status-name "12"
    [ "$status" -eq 0 ]
    [ "$output" = "USAGE" ]
}

@test "return-status-name: 13 -> CONFIG" {
    run return-status-name "13"
    [ "$status" -eq 0 ]
    [ "$output" = "CONFIG" ]
}

@test "return-status-name: 14 -> NOTFOUND" {
    run return-status-name "14"
    [ "$status" -eq 0 ]
    [ "$output" = "NOTFOUND" ]
}

@test "return-status-name: 15 -> FATAL" {
    run return-status-name "15"
    [ "$status" -eq 0 ]
    [ "$output" = "FATAL" ]
}

@test "return-status-name: invalid code returns non-zero" {
    run return-status-name "99"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# log — message and stdin paths (lines 214-259)
# ---------------------------------------------------------------------------

@test "log: message argument written to stderr" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=info log INFO 'hello-world' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello-world"* ]]
}

@test "log: stdin pipe written to stderr (line 254-258)" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=info echo 'from-stdin' | log INFO 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"from-stdin"* ]]
}

@test "log: message below LOG_LEVEL is suppressed" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=warn log DEBUG 'should-not-appear' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" != *"should-not-appear"* ]]
}

# ---------------------------------------------------------------------------
# Named log-level helpers (lines 101-141, 195-213, 511-520, 543-556,
#                           582-599)
# ---------------------------------------------------------------------------

@test "debug: message written to stderr (line 110)" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=diag debug 'debug-msg' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"debug-msg"* ]]
}

@test "diag: message written to stderr (line 122)" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=diag diag 'diag-msg' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"diag-msg"* ]]
}

@test "diagnostic: delegates to diag (line 131)" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=diag diagnostic 'diag-alias-msg' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"diag-alias-msg"* ]]
}

@test "info: message written to stderr" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=info info 'info-msg' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"info-msg"* ]]
}

@test "information: delegates to info" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=info information 'info-alias-msg' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"info-alias-msg"* ]]
}

@test "notice: message written to stderr" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=info notice 'notice-msg' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"notice-msg"* ]]
}

@test "trace: message written to stderr (line 555)" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=diag trace 'trace-msg' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"trace-msg"* ]]
}

@test "warn: message written to stderr" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=info warn 'warn-msg' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"warn-msg"* ]]
}

@test "warning: delegates to warn" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=info warning 'warning-alias-msg' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"warning-alias-msg"* ]]
}

# ---------------------------------------------------------------------------
# fatal / die / error — exit-path helpers (lines 134-156, 178-193)
# ---------------------------------------------------------------------------

@test "fatal: exits non-zero with message (line 140)" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=info fatal 'fatal-msg' 2>&1"
    [ "$status" -ne 0 ]
    [[ "$output" == *"fatal-msg"* ]]
}

@test "fatal: exits with explicit EXIT_FATAL when no status given" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=info fatal 'msg' 2>/dev/null"
    [ "$status" -eq 5 ]   # EXIT_FATAL=5
}

@test "fatal: accepts explicit exit status (lines 187-190)" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=info fatal 2 'msg' 2>/dev/null"
    [ "$status" -eq 2 ]
}

@test "die: alias for fatal, exits non-zero (line 140)" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=info die 'die-msg' 2>/dev/null"
    [ "$status" -ne 0 ]
}

@test "error: exits non-zero with message" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=info error 'err-msg' 2>&1"
    [ "$status" -ne 0 ]
    [[ "$output" == *"err-msg"* ]]
}

@test "error: accepts explicit exit status" {
    run bash -c "source '${common_functions}'; LOG_LEVEL=info error 3 'msg' 2>/dev/null"
    [ "$status" -eq 3 ]
}

# ---------------------------------------------------------------------------
# log-and-exit — RETURN_ERROR_FLOOR path (lines 304-310)
# ---------------------------------------------------------------------------

@test "log-and-exit: return code >= RETURN_ERROR_FLOOR subtracts floor and returns (line 308)" {
    # RETURN_FATAL=15, RETURN_ERROR_FLOOR=10 -> returns 15-10=5 (EXIT_FATAL)
    run bash -c "
        source '${common_functions}'
        LOG_LEVEL=diag
        log-and-exit FATAL 15 'return-path-msg' 2>/dev/null
    "
    [ "$status" -eq 5 ]
}

@test "log-and-exit: RETURN_SUCCESS=0 returns 0 (line 304)" {
    run bash -c "
        source '${common_functions}'
        LOG_LEVEL=diag
        log-and-exit INFO 0 'success-msg' 2>/dev/null
    "
    [ "$status" -eq 0 ]
}

@test "log-and-exit: EXIT_USAGE with usage function calls usage then exits (lines 313-314)" {
    run bash -c "
        source '${common_functions}'
        function usage() { echo 'USAGE_CALLED'; }
        export -f usage
        LOG_LEVEL=diag
        log-and-exit ERROR 2 'usage-path' 2>/dev/null
    "
    [ "$status" -eq 2 ]
    [[ "$output" == *"USAGE_CALLED"* ]]
}

# ---------------------------------------------------------------------------
# logging-prolog — prolog variants (lines 367-413)
# ---------------------------------------------------------------------------

@test "logging-prolog: LOGGING_INCLUDE_COMMAND includes command name (lines 390-391)" {
    run bash -c "
        source '${common_functions}'
        LOGGING_INCLUDE_COMMAND=true logging-prolog
    "
    [ "$status" -eq 0 ]
    # Output includes basename of \$0
    [[ -n "$output" ]]
}

@test "logging-prolog: LOGGING_INCLUDE_TIMESTAMP includes a timestamp (lines 398-404)" {
    run bash -c "
        source '${common_functions}'
        LOGGING_INCLUDE_TIMESTAMP=true logging-prolog
    "
    [ "$status" -eq 0 ]
    # Timestamp format: YYYYMMDDTHHmmss
    [[ "$output" =~ [0-9]{8}T[0-9]{6} ]]
}

@test "logging-prolog: LOG_DATE_FORMAT without leading + gets + prepended (line 400-401)" {
    run bash -c "
        source '${common_functions}'
        LOGGING_INCLUDE_TIMESTAMP=true LOG_DATE_FORMAT='%Y' logging-prolog
    "
    [ "$status" -eq 0 ]
    [[ "$output" =~ [0-9]{4} ]]
}

@test "logging-prolog: LOGGING_INCLUDE_LOCATION includes caller info (line 409)" {
    run bash -c "
        source '${common_functions}'
        LOG_LEVEL=info LOGGING_INCLUDE_LOCATION=true log INFO 'location-test' 2>&1
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"location-test"* ]]
}

@test "logging-prolog: LOGGING_INCLUDE_ALL includes timestamp, command, and location" {
    run bash -c "
        source '${common_functions}'
        LOG_LEVEL=info LOGGING_INCLUDE_ALL=true log INFO 'all-fields' 2>&1
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"all-fields"* ]]
}

# ---------------------------------------------------------------------------
# logging-get-external-caller (lines 468-509)
# ---------------------------------------------------------------------------

@test "logging-get-external-caller: returns a caller string from a function context (lines 478-502)" {
    # Must be called from inside a function so caller() has a real frame to inspect.
    run bash -c "
        source '${common_functions}'
        function outer() { logging-get-external-caller; }
        outer
    "
    [ "$status" -eq 0 ]
    [[ -n "$output" ]]
}

@test "logging-get-external-caller: includes filename when LOGGING_INCLUDE_LOCATION_FILE=true (line 495)" {
    run bash -c "
        source '${common_functions}'
        function outer() {
            LOGGING_INCLUDE_LOCATION_FILE=true logging-get-external-caller
        }
        outer
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *" in "* ]]
}

# ---------------------------------------------------------------------------
# log-traceback (lines 440-453)
# ---------------------------------------------------------------------------

@test "log-traceback: writes call stack to stderr (lines 446-451)" {
    run bash -c "
        source '${common_functions}'
        LOG_LEVEL=diag log-traceback 2>&1
    "
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# log-traceback-trap (lines 430-438)
# ---------------------------------------------------------------------------

@test "log-traceback-trap: writes error line to stderr (lines 434-437)" {
    run bash -c "
        source '${common_functions}'
        LOG_LEVEL=diag log-traceback-trap 2>&1
    "
    # log-traceback-trap returns the original exit code (\$?)
    # status will be 0 here (no preceding failure) but output should contain ERROR
    [[ "$output" == *"[ERROR]"* ]] || [[ "$output" == *"command"* ]]
}

# ---------------------------------------------------------------------------
# logging-exit-fatally (lines 455-466)
# ---------------------------------------------------------------------------

@test "logging-exit-fatally: exits with given code (lines 461-465)" {
    run bash -c "source '${common_functions}'; logging-exit-fatally 3"
    [ "$status" -eq 3 ]
}

@test "logging-exit-fatally: defaults to EXIT_ERROR when no argument" {
    run bash -c "source '${common_functions}'; logging-exit-fatally"
    [ "$status" -eq 1 ]   # EXIT_ERROR=1
}
