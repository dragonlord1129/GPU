#!/bin/bash

# =====================================================
# Usage:
#   ./run_verilog.sh module_name tb_module_name
# =====================================================

MODULE=$1
TB=$2

SRC_DIR="./"
DOCS_DIR="../docs/${MODULE}"

VERILOG_FILE="${SRC_DIR}/${MODULE}.v"
TB_FILE="${SRC_DIR}/${TB}.v"

OUT_EXE="${MODULE}.out"
LOG_FILE="${DOCS_DIR}/simulation.log"
VCD_FILE="${DOCS_DIR}/${MODULE}.vcd"

mkdir -p "${DOCS_DIR}"

echo "========================================"
echo " Module     : ${MODULE}"
echo " Testbench  : ${TB}"
echo "========================================"

# -------------------------
# Compile
# -------------------------
iverilog -o "${OUT_EXE}" "${VERILOG_FILE}" "${TB_FILE}" > "${LOG_FILE}" 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Compilation failed. Check log:"
    echo "${LOG_FILE}"
    exit 1
fi

echo "✔ Compilation successful"

# -------------------------
# Run simulation
# -------------------------
vvp "${OUT_EXE}" >> "${LOG_FILE}" 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Simulation failed. Check log:"
    echo "${LOG_FILE}"
    exit 1
fi

echo "✔ Simulation completed"

# -------------------------
# Save VCD
# -------------------------
if [ -f "dump.vcd" ]; then
    mv dump.vcd "${VCD_FILE}"
    echo "✔ VCD saved: ${VCD_FILE}"
else
    echo "⚠ No VCD file generated (did you call \$dumpfile?)"
fi

echo "========================================"
echo " Log  : ${LOG_FILE}"
echo " VCD  : ${VCD_FILE}"
echo "========================================"