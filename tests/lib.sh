# Shared helpers for test scripts.
# Each test prints one line per assertion in the form:
#   PASS|FAIL <test-id> <description>
# and exits with 0 on success, 1 on at least one FAIL.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[1]:-$0}")" && pwd)"
PROTOTYPE_DIR="$(cd "${TESTS_DIR}/../prototype" && pwd)"
RESULT_DIR="${TESTS_DIR}/.results"
mkdir -p "${RESULT_DIR}"

# Counters in subshell are tracked via a tiny state file.
__test_pass=0
__test_fail=0
__test_skip=0

assert() {
    local desc="$1"
    local actual="$2"
    local expected="$3"
    if [[ "${actual}" == "${expected}" ]]; then
        echo "PASS  ${desc}"
        __test_pass=$((__test_pass+1))
    else
        echo "FAIL  ${desc}"
        echo "      expected: ${expected}"
        echo "      actual  : ${actual}"
        __test_fail=$((__test_fail+1))
    fi
}

assert_contains() {
    local desc="$1"
    local haystack="$2"
    local needle="$3"
    if [[ "${haystack}" == *"${needle}"* ]]; then
        echo "PASS  ${desc}"
        __test_pass=$((__test_pass+1))
    else
        echo "FAIL  ${desc}"
        echo "      haystack: ${haystack:0:200}"
        echo "      needle  : ${needle}"
        __test_fail=$((__test_fail+1))
    fi
}

skip() {
    local desc="$1"
    local reason="$2"
    echo "SKIP  ${desc} (${reason})"
    __test_skip=$((__test_skip+1))
}

summarize() {
    echo
    echo "------------------------------------------------"
    echo "PASS=${__test_pass}  FAIL=${__test_fail}  SKIP=${__test_skip}"
    echo "------------------------------------------------"
    [[ ${__test_fail} -eq 0 ]] && return 0 || return 1
}
