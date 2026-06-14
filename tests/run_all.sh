#!/usr/bin/env bash
# Run every test_*.sh, accumulate PASS/FAIL counts, print a Markdown summary.
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULT_DIR="${TESTS_DIR}/.results"
mkdir -p "${RESULT_DIR}"

declare -A SUITE_PASS
declare -A SUITE_FAIL
declare -A SUITE_DUR

TOTAL_PASS=0
TOTAL_FAIL=0

for f in "${TESTS_DIR}"/test_*.sh; do
    name=$(basename "${f}" .sh)
    log="${RESULT_DIR}/${name}.log"
    echo
    echo "############### ${name} ###############"
    start=$(date +%s)
    bash "${f}" 2>&1 | tee "${log}"
    end=$(date +%s)
    dur=$((end - start))
    p=$(grep -c '^PASS ' "${log}" || true)
    fl=$(grep -c '^FAIL ' "${log}" || true)
    SUITE_PASS[${name}]=${p}
    SUITE_FAIL[${name}]=${fl}
    SUITE_DUR[${name}]=${dur}
    TOTAL_PASS=$((TOTAL_PASS + p))
    TOTAL_FAIL=$((TOTAL_FAIL + fl))
done

echo
echo "================================================================"
echo "              Сводный отчёт по тестам"
echo "================================================================"
printf "%-30s %6s %6s %6s\n" "suite" "PASS" "FAIL" "dur,s"
echo "----------------------------------------------------------------"
for name in "${!SUITE_PASS[@]}"; do
    printf "%-30s %6d %6d %6d\n" "${name}" "${SUITE_PASS[${name}]}" "${SUITE_FAIL[${name}]}" "${SUITE_DUR[${name}]}"
done | sort
echo "----------------------------------------------------------------"
printf "%-30s %6d %6d\n" "TOTAL" "${TOTAL_PASS}" "${TOTAL_FAIL}"
echo "================================================================"


{
    echo "# Результаты прогона тестов прототипа"
    echo
    echo "_Сгенерировано: $(date -u +%Y-%m-%dT%H:%M:%SZ)_"
    echo
    echo "| Категория тестов | PASS | FAIL | Время, с |"
    echo "|---|---:|---:|---:|"
    for name in "${!SUITE_PASS[@]}"; do
        printf "| %s | %d | %d | %d |\n" "${name}" "${SUITE_PASS[${name}]}" "${SUITE_FAIL[${name}]}" "${SUITE_DUR[${name}]}"
    done | sort
    echo "| **Итого** | **${TOTAL_PASS}** | **${TOTAL_FAIL}** | |"
} > "${RESULT_DIR}/summary.md"
echo
echo "Markdown summary: ${RESULT_DIR}/summary.md"

[[ ${TOTAL_FAIL} -eq 0 ]] && exit 0 || exit 1
