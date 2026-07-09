#!/usr/bin/env python3
"""
Convert hex files into hardcoded Verilog memory modules.
- instruction_memory.v  ← memfile_mul.hex  (all unused entries → HALT)
- data_memory.v         ← datamemory.hex   (all unused entries → 0,
                         data_memory_line module preserved untouched)
"""

import sys, re

# ------------------------- Configuration -------------------------
INSTR_HEX   = "memfile_mul.hex"
INSTR_VLOG  = "instruction_memory.v"
DATA_HEX    = "datamemory.hex"
DATA_VLOG   = "data_memory.v"

INSTR_DEPTH = 32768
INSTR_DEF   = "32'hA0000000"   # HALT
DATA_DEPTH  = 4096
DATA_DEF    = "32'd0"

# ----------------------------------------------------------------
# 1. Generate instruction memory module (complete)
# ----------------------------------------------------------------
def generate_instruction_memory():
    mem = parse_hex(INSTR_HEX)
    with open(INSTR_VLOG, 'w') as f:
        f.write(f"""// Auto‑generated from {INSTR_HEX} – do not edit manually
module instruction_memory (
    input  [15:0] A,
    output [31:0] RD
);
    reg [31:0] memory [0:{INSTR_DEPTH-1}];
    integer idx;
    initial begin
        for (idx = 0; idx < {INSTR_DEPTH}; idx = idx + 1)
            memory[idx] = {INSTR_DEF};
""")
        for addr, val in sorted(mem.items()):
            f.write(f"        memory[{addr}] = 32'h{val:08X};\n")
        f.write("""    end
    assign RD = memory[A[14:0]];
endmodule
""")
    print(f"[OK] {INSTR_VLOG} generated from {INSTR_HEX}")

# ----------------------------------------------------------------
# 2. Generate data memory module (preserve data_memory_line)
# ----------------------------------------------------------------
def generate_data_memory():
    mem = parse_hex(DATA_HEX)
    # Read original data_memory.v
    try:
        with open(DATA_VLOG, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"[ERROR] {DATA_VLOG} not found. Cannot preserve data_memory_line.")
        sys.exit(1)

    # Find module data_memory (not data_memory_line)
    start = None
    for i, line in enumerate(lines):
        if re.search(r'\bmodule\s+data_memory\b', line) and 'data_memory_line' not in line:
            start = i
            break
    if start is None:
        print("[ERROR] Could not find 'module data_memory' in data_memory.v")
        sys.exit(1)

    # Find matching endmodule
    end = None
    for i in range(start+1, len(lines)):
        if re.search(r'\bendmodule\b', lines[i]):
            end = i
            break
    if end is None:
        print("[ERROR] Could not find endmodule for data_memory")
        sys.exit(1)

    before = lines[:start]
    after  = lines[end+1:]

    # Build new data_memory module
    new_mod = f"""// Auto‑generated from {DATA_HEX} – do not edit manually
module data_memory #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 12
)(
    input                         clk,
    input  [ADDR_WIDTH-1:0]       A,
    input  [DATA_WIDTH-1:0]       writeData,
    input                         writeEnable,
    output [DATA_WIDTH-1:0]       RD
);
    localparam DEPTH = (1 << ADDR_WIDTH);
    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];

    // ----- Hardcoded initialisation from {DATA_HEX} -----
    integer init_idx;
    initial begin
        for (init_idx = 0; init_idx < DEPTH; init_idx = init_idx + 1)
            memory[init_idx] = {DATA_DEF};
"""
    for addr, val in sorted(mem.items()):
        new_mod += f"        memory[{addr}] = 32'h{val:08X};\n"
    new_mod += """    end

    assign RD = memory[A];

    always @(posedge clk)
        if (writeEnable)
            memory[A] <= writeData;

endmodule
"""

    # Write file preserving other modules
    with open(DATA_VLOG, 'w') as f:
        f.writelines(before)
        f.write(new_mod)
        f.writelines(after)
    print(f"[OK] {DATA_VLOG} updated from {DATA_HEX} (data_memory_line untouched)")

# ----------------------------------------------------------------
# Helper: parse hex file → dict {address: value}
# ----------------------------------------------------------------
def parse_hex(filename):
    mem = {}
    addr = 0
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith('@'):
                addr = int(line[1:], 16)
            else:
                mem[addr] = int(line, 16)
                addr += 1
    return mem

# ----------------------------------------------------------------
# Main
# ----------------------------------------------------------------
if __name__ == '__main__':
    generate_instruction_memory()
    generate_data_memory()