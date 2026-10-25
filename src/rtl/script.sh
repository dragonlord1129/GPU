#!/usr/bin/env bash

set -e

OUT="warp"

usage() {
    echo "Usage: $0 [-o output_name]"
    echo ""
    echo "Output name determines the testbench:"
    echo "  add*  -> ../tests/tb_matrix_add.v"
    echo "  mul*  -> ../tests/tb_matrix_mul.v"
    echo "  dot*  -> ../tests/tb_matrix_dot.v"
    echo "  other -> ../tests/tb_bench.v"
    echo ""
    echo "Example:"
    echo "  $0 -o add"
    echo "  $0 -o mul"
    echo "  $0 -o dot"
    exit 1
}

while getopts "o:h" opt; do
    case $opt in
        o) OUT="$OPTARG" ;;
        h|*) usage ;;
    esac
done

case "$OUT" in
    add*) TB="../tests/tb_matrix_add.v" ;;
    mul*) TB="../tests/tb_matrix_mul.v" ;;
    dot*) TB="../tests/tb_matrix_dot.v" ;;
    other) TB="../tests/tb_bench.v" ;;
    *)
        echo "Error: Unknown output name '$OUT'."
        echo "Please use one of the following prefixes: add, mul, dot, other."
        exit 1
        ;;
esac

echo "Output    : $OUT"
echo "Testbench : $TB"

iverilog  \
    -g2005-sv \
    -o "$OUT" \
    alu* \
    data_memory.v \
    gpu_top.v \
    imm_gen.v \
    instruction_* \
    main_decoder.v \
    memory_scheduler.v \
    reg_file_simt.v \
    simt_alu.v \
    warp_scheduler.v \
    "$TB"

echo "Build successful."
echo "Run with:"
echo "vvp $OUT"