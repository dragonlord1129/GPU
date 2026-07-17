# SIMT GPU Architecture for Parallel Matrix Operations

A Verilog implementation of a **SIMT (Single Instruction Multiple Threads) GPU architecture** capable of executing parallel matrix kernels. The design includes a warp scheduler, SIMT ALU, coalesced memory subsystem, register file, and instruction execution pipeline.

The project demonstrates:

- Parallel **Matrix Addition (C = A + B)**
- Parallel **Matrix Multiplication (C = A × B)**
- Round-robin warp scheduling with stall detection
- Memory coalescing across 16 SIMT lanes
- SIMT execution with per-lane register files
- Functional verification using VCD waveforms

---

## Features

- 16-lane SIMT execution engine
- 4-warp round-robin scheduler
- Per-lane 16-register file (R0 = zero, R15 = lane ID hardwired)
- Booth-encoded multiplier (signed, radix-2)
- Non-restoring signed integer divider
- Memory Scheduler with cache-line coalescing (16-word lines)
- 12-bit byte-addressable Data Memory
- Load/Store with automatic memory stall/resume
- Branch (BEQ) and unconditional Jump support
- Matrix Addition kernel
- Matrix Multiplication kernel
- Complete Verilog testbenches with pass/fail checking
- GTKWave-compatible VCD generation

---

## Architecture

```mermaid
flowchart LR

    A[Instruction Memory]
    B[Instruction Decoder]
    C[Warp Scheduler]
    D[SIMT Register File]
    E[SIMT ALU]
    F[Memory Scheduler]
    G[Coalesced Memory Interface]
    H[Data Memory]
    I[Writeback MUX]

    A --> B
    B --> C
    C --> D
    D --> E
    E --> F
    F --> G
    G --> H
    H --> I
    I --> D
```

---

## Overall Data Flow

```text
              +-------------------+
              | Instruction Memory|
              +---------+---------+
                        |
                        v
             +----------------------+
             | Instruction Decoder  |
             +----------+-----------+
                        |
                        v
              +--------------------+
              | Warp Scheduler     |   <-- round-robin, stall/resume
              +----------+---------+
                         |
                         v
              +--------------------+
              | Register File      |   <-- 16 lanes × 16 regs; R15 = lane ID
              +----------+---------+
                         |
                         v
                  +--------------+
                  | SIMT ALU     |   <-- 16 parallel ALU instances
                  +------+-------+
                         |
             +-----------+------------+
             |                        |
             v                        v
       Write Back               Memory Scheduler
                                       |
                                 Coalesce requests
                                 from 16 lanes into
                                 cache-line bursts
                                       |
                                       v
                                 Data Memory
                               (12-bit, 32-bit wide)
```

---

## Project Structure

```text
├── rtl/
│   ├── gpu_top.v              # Top-level integration
│   ├── alu.v                  # Single-lane ALU with flags
│   ├── simt_alu.v             # 16× ALU array
│   ├── warp_scheduler.v       # 4-warp round-robin FSM
│   ├── memory_scheduler.v     # Coalescing memory FSM
│   ├── reg_file_simt.v        # 16-lane register file
│   ├── instruction_memory.v   # ROM loaded from .hex
│   ├── data_memory.v          # RAM with initialised matrices
│   ├── instruction_decoder.v  # Fixed-width instruction decode
│   ├── main_decoder.v         # Control-signal generation
│   ├── imm_gen.v              # Zero-extend 16-bit immediate
│   └── writeback_mux.v        # ALU vs. load-data selection
│
├── tests/
│   ├── tb_matrix_add.v        # Matrix addition testbench
│   ├── tb_matrix_mul.v        # Matrix multiplication testbench
│
├── programs/
│   ├── matrix_add.mem         # Assembled addition kernel
│   ├── matrix_mul.mem         # Assembled multiplication kernel
│
├── waves/
│   ├── tb_matrix_add.vcd      # Addition simulation trace
│   └── tb_matrix_mul.vcd      # Multiplication simulation trace
│
└── README.md
```

---

## Module Reference

### `gpu_top.v` — Top-Level Integration

Instantiates and wires every sub-module. Key responsibilities:

- Drives `mem_req_pulse` from the current instruction's opcode, gating on `mem_pending` and `ms_stall`.
- Tracks per-warp `mem_pending`, `mem_is_load`, and `mem_dest` in four registers.
- Latches `lw_out` into `captured_lw_data` when `mem_done` fires and the request was a load.
- Generates write-back control: on a load completion, `wb_rd_addr` comes from the captured destination; otherwise it comes from the decoded `rd` field.
- Implements BEQ/Jump redirection: all 16 `lane_ok` bits must agree before the PC is redirected.

### `warp_scheduler.v` — 4-Warp Round-Robin FSM

States: **RUN → SWITCH → RUN**

| Signal | Direction | Description |
|--------|-----------|-------------|
| `mem_req` | in | Memory op issued; stall this warp |
| `mem_done` | in | Memory op complete; un-stall the warp |
| `halt` | in | Mark current warp finished |
| `hold` | in | Freeze PC (bubble; do not advance) |
| `redirect` | in | BEQ/Jump taken; load `pc_target` |
| `warp_ready` | out | PC of the currently scheduled warp |
| `warp_ready_mask` | out | Active-lane mask (always `0xFFFF` here) |
| `done` | out | All four warps finished |

Warp initial PCs (set in `initial` block):

| Warp | Start PC |
|------|----------|
| 0 | 0 |
| 1 | 24 |
| 2 | 25 |
| 3 | 26 |

On `mem_req`, the warp's PC is **immediately advanced by 1** before the warp is stalled. This ensures the warp resumes at the correct instruction after memory completes, avoiding the re-issue bug.

### `reg_file_simt.v` — 16-Lane Register File

- 16 registers per lane (4-bit address)
- **R0** always reads as zero and is never written
- **R15** is hardwired to the lane index (0–15); writes are silently ignored
- All 16 lanes share a single `rd_addr` / `rs1_addr` / `rs2_addr`; per-lane data diverges in the data arrays
- `active_mask` gates writes: a lane whose mask bit is 0 retains its register value

### `alu.v` — Single-Lane ALU

Supports:

| `ALUControl` | Operation | Notes |
|---|---|---|
| `0000` | ADD | |
| `0001` | SUB | Two's complement via B-invert + carry-in |
| `0010` | AND | |
| `0011` | OR | |
| `0100` | XOR | |
| `0101` | MUL (low 16 bits) | Via Booth multiplier |
| `0110` | MUL (high 16 bits) | Upper half of 32-bit product |
| `0111` | DIV (quotient) | Non-restoring signed divider |
| `1000` | REM (remainder) | Non-restoring signed divider |
| `1001` | SLT | Sign-aware set-less-than |

Flags produced: `zero`, `carry`, `negative`, `overflow`, `divide_by_zero`.

**Booth Multiplier** (`booth_multiplier.v`): Radix-2 signed Booth encoding, fully combinational, produces a 2×N-bit product. The ALU exposes the low and high halves separately via two opcodes.

**Non-Restoring Divider** (`non_restoring_divider_comb.v`): Fully combinational, signed mode controlled by `signed_mode`. Sets `divide_by_zero` when the divisor is zero.

### `simt_alu.v` — 16-Lane ALU Array

Instantiates 16 copies of `alu.v`, each receiving its own `A[i]` / `B[i]` while sharing the `ALUControl` bus. Results emerge independently per lane.

### `memory_scheduler.v` — Coalescing Memory FSM

States: **IDLE → WARP → REQ\_CHECK → REQ → WAIT → CAPTURE → DONE**

Accepts memory requests from the warp scheduler, queues up to **4 outstanding requests** (one per warp), then services them one cache line at a time.

**Coalescing algorithm (REQ state):**
1. Find the first un-serviced active lane (the "leader").
2. Collect all other active lanes whose address falls in the **same 16-word cache line** as the leader (upper 8 bits of the 12-bit address).
3. Issue one `addr_out` to `data_memory_line`, writing or reading all matched lanes in a single memory transaction.
4. Mark those lanes as serviced; loop back for remaining lanes.

On a store, `sw_word_mask` selects only the words within the cache line that belong to the coalesced group, so unrelated words are not overwritten.

### `data_memory.v` / `data_memory_line.v` — Data Memory

`data_memory`: Single-port synchronous RAM, 4096 × 32-bit words (12-bit address).

`data_memory_line`: Generates 16 parallel `data_memory` instances sharing an upper-address bus, forming a 16-word cache line interface. Each word is individually write-enabled via `sw_word_mask`.

Pre-loaded layout:

| Address range | Contents |
|---|---|
| 0 – 15 | Matrix A (values 1–16, row-major) |
| 16 – 31 | Matrix B (4×4 identity matrix) |
| 100 – 115 | Row index table (0,0,0,0, 1,1,1,1, 2,2,2,2, 3,3,3,3) |
| 116 – 131 | Column index table (0,1,2,3 repeating) |
| 200 | Constant 32 (base address of output matrix C) |

### `instruction_decoder.v` — Fixed-Width Decode

Instruction word is 32 bits wide:

```
 31      28 27    24 23    20 19    16 15               0
 +--------+--------+--------+--------+-----------------+
 | opcode |   rd   |   rs1  |   rs2  |    immediate    |
 +--------+--------+--------+--------+-----------------+
    4 b       4 b     4 b      4 b         16 b
```

### `main_decoder.v` — Control Signal Generation

| Opcode | Mnemonic | RegWrite | MemRead | MemWrite | ALUSrc | ALUControl |
|--------|----------|----------|---------|----------|--------|------------|
| `0x0` | ADD | 1 | 0 | 0 | 0 | 0000 |
| `0x1` | SUB | 1 | 0 | 0 | 0 | 0001 |
| `0x2` | AND | 1 | 0 | 0 | 0 | 0010 |
| `0x3` | OR | 1 | 0 | 0 | 0 | 0011 |
| `0x4` | XOR | 1 | 0 | 0 | 0 | 0100 |
| `0x5` | MUL | 1 | 0 | 0 | 0 | 0101 |
| `0x6` | LW | 1 | 1 | 0 | 1 | 0000 |
| `0x7` | SW | 0 | 0 | 1 | 1 | 0000 |
| `0x8` | BEQ | 0 | 0 | 0 | 0 | 0001 |
| `0x9` | JUMP | 0 | 0 | 0 | — | — |
| `0xA` | HALT | 0 | 0 | 0 | — | — |

---

## Instruction Set Summary

```
ADD   rd, rs1, rs2   →  rd = rs1 + rs2
SUB   rd, rs1, rs2   →  rd = rs1 - rs2
AND   rd, rs1, rs2   →  rd = rs1 & rs2
OR    rd, rs1, rs2   →  rd = rs1 | rs2
XOR   rd, rs1, rs2   →  rd = rs1 ^ rs2
MUL   rd, rs1, rs2   →  rd = (rs1 × rs2)[15:0]
LW    rd, rs1, imm   →  rd = Mem[rs1 + imm]
SW    rs2, rs1, imm  →  Mem[rs1 + imm] = rs2
BEQ   rs1, rs2, imm  →  if (rs1 == rs2) PC += 1 + imm
JUMP  imm            →  PC = imm
HALT                 →  Mark warp complete
```

Immediates are **zero-extended** to 16 bits by `imm_gen.v`.

---

## Matrix Addition

The addition kernel computes

$$C = A + B$$

where every lane computes one matrix element in parallel — all 16 elements complete in a single warp pass.

### Input Matrices

**Matrix A** (addresses 0–15):

| 1 | 2 | 3 | 4 |
|---|---|---|---|
| 5 | 6 | 7 | 8 |
| 9 | 10 | 11 | 12 |
| 13 | 14 | 15 | 16 |

**Matrix B** (addresses 16–31, identity matrix):

| 1 | 0 | 0 | 0 |
|---|---|---|---|
| 0 | 1 | 0 | 0 |
| 0 | 0 | 1 | 0 |
| 0 | 0 | 0 | 1 |

### Output Matrix C (addresses 32–47):

| 2 | 2 | 3 | 4 |
|---|---|---|---|
| 5 | 7 | 7 | 8 |
| 9 | 10 | 12 | 12 |
| 13 | 14 | 15 | 17 |

### Kernel Execution Trace

The warp scheduler issues Warp 0 first. Warps 1–3 start at PC 24–26 (HALT instructions — placeholder warps) and finish immediately, leaving Warp 0 as the sole active warp.

| Phase | Opcode | Description |
|-------|--------|-------------|
| 1 | LW | Load all 16 elements of Matrix A into registers (16 lanes simultaneously) |
| 2 | LW | Load all 16 elements of Matrix B |
| 3 | ADD | 16-lane parallel element-wise add |
| 4 | SW | Store all 16 results to Matrix C base address 32 |
| 5 | HALT | Mark Warp 0 complete; `done` asserted |

---

## Matrix Multiplication

The multiplication kernel computes

$$C = A \times B$$

For the supplied test case, B is the identity matrix, so:

$$C = A \times I = A$$

### Output Matrix C:

| 1 | 2 | 3 | 4 |
|---|---|---|---|
| 5 | 6 | 7 | 8 |
| 9 | 10 | 11 | 12 |
| 13 | 14 | 15 | 16 |

### Kernel Execution Trace

Matrix multiplication requires dot products: for each output element C[i][j], the kernel iterates over the inner dimension (k = 0…3), performing a multiply-accumulate:

```
accumulator = 0
for k in 0..3:
    accumulator += A[i][k] * B[k][j]
C[i][j] = accumulator
```

This inner loop requires repeated LW → MUL → ADD cycles, which accounts for the significantly higher cycle count compared to addition.

| Phase | Opcode(s) | Description |
|-------|-----------|-------------|
| 1 | LW | Load A[i][k] for current k iteration |
| 2 | LW | Load B[k][j] for current k iteration |
| 3 | MUL | 16-lane parallel multiply (Booth) |
| 4 | ADD | Accumulate into result register |
| 5 | BEQ/JUMP | Loop back for next k; exit when k == 4 |
| 6 | SW | Store accumulated results to Matrix C |
| 7 | HALT | Warp complete |

---

## Simulation Results

Both kernels execute correctly and produce matching output.

| Test | Clock Cycles | Runtime | Result |
|------|:---:|:---:|:---:|
| Matrix Addition | 42 | 425 ns | **PASS** |
| Matrix Multiplication | 247 | 2475 ns | **PASS** |

---

## Waveform Analysis — Matrix Addition

![Matrix Addition Waveform](./pics/vcd_waveform_matrix_add.png)

**File:** `tb_matrix_add.vcd` · **Tool:** GTKWave · **Timescale:** 1 ns/1 ps

### Key Events

| Time | Event | Signal(s) |
|------|-------|-----------|
| 0 ns | Simulation start; reset asserted | `rst = 1` |
| 35 ns | Reset released | `rst = 0` |
| ~35 ns | Warp 0 scheduled; first LW issued | `current_warp_id = W0`, `opcode = LW` |
| ~45–106 ns | W1, W2, W3 each execute their HALT | `opcode = HALT` for placeholder warps |
| ~106–159 ns | Warp 0 resumes; second LW (Matrix B) | `opcode = LW`, `mem_req_pulse` rises |
| ~212 ns | ADD instruction | `opcode = ADD`; 16 ALUs add in parallel |
| ~265–318 ns | SW instruction; memory scheduler builds coalesced write | `opcode = SW`, `mem_req_pulse` |
| 345 ns | Coalesced store fires: 16 lanes → **1 memory transaction** | `ms_mem_write = 1`, `addr = 32` |
| ~370 ns | Warp 0 executes HALT | `opcode = HALT` |
| 415 ns | `done` asserted; kernel complete | `done = 1` |

### Warp Execution Summary

```
W0: LW (A) → stall/resume → LW (B) → stall/resume → ADD → SW → stall/resume → HALT
W1: HALT  (placeholder)
W2: HALT  (placeholder)
W3: HALT  (placeholder)
```

Round-robin scheduling is visible in the `current_warp_id` trace: W0 → W1 → W2 → W3 → W0, with W1/W2/W3 retiring almost immediately.

### Execution Metrics

| Metric | Value |
|--------|------:|
| Clock Cycles | 42 |
| Runtime | 425 ns |
| Memory Transactions | 3 (2 LW + 1 SW) |
| Coalescing Ratio | 16:1 (16 lanes per transaction) |
| ALU Cycles | 1 (single parallel ADD) |

---

## Waveform Analysis — Matrix Multiplication

![Matrix Multiplication Waveform](./pics/vcd_waveform_matrix_mul.png)

**File:** `tb_matrix_mul.vcd` · **Tool:** GTKWave · **Timescale:** 1 ns/1 ps

### Key Events

| Time | Event | Signal(s) |
|------|-------|-----------|
| 0 ns | Simulation start; reset asserted | `rst = 1` |
| 35 ns | Reset released | `rst = 0` |
| ~35 ns | W0 and W3 scheduled; initial LW and HALT | `opcode = LW / HALT` |
| ~35–2395 ns | Repeated LW → MUL → ADD cycles across 4 accumulation steps | `mem_req_pulse` fires ~24 times |
| ~1236 ns | Mid-kernel LW (inner loop continuation) | `opcode = LW`, `current_warp_id = W0` |
| ~2350–2395 ns | MUL instructions; final ADD accumulation | `opcode = MUL / ADD` |
| 2395 ns | Coalesced store: 16 lanes → **1 memory write** to addr 32 | `ms_mem_write = 1` |
| ~2450 ns | HALT | `opcode = HALT` |
| 2465 ns | `done` asserted | `done = 1` |

### `mem_req_pulse` Activity

The multiplication waveform shows approximately **24 `mem_req_pulse` assertions** across the full simulation. Each pulse corresponds to one warp stalling for a memory operation. The memory scheduler services them sequentially, with coalescing collapsing all 16-lane accesses into single-transaction bursts.

### Execution Metrics

| Metric | Value |
|--------|------:|
| Clock Cycles | 247 |
| Runtime | 2475 ns |
| Multiply Cycles | 4 per output element (inner loop k = 0–3) |
| Memory Transactions | ~24 (8 LW rounds × 3 loads each + 1 SW) |
| Coalescing Ratio | 16:1 per transaction |
| Speedup vs. Addition | ~5.9× more cycles (expected for O(N) inner loop) |

---

## Memory Coalescing — Detailed

The `memory_scheduler` combines accesses from multiple SIMT lanes that fall within the same **16-word cache line** into a single memory transaction.

### How It Works

1. A warp issues a memory instruction. `gpu_top` fires `mem_req_pulse` and latches the 16 per-lane addresses into the scheduler's request queue.
2. The scheduler enters the **WARP** state and picks the next pending warp.
3. In **REQ**, it scans active lanes for a "leader" (first un-serviced lane). It finds all lanes whose `addr[15:4]` (upper bits) match the leader's — these form a coalesced group.
4. It issues a single `addr_out` to `data_memory_line`. For stores, `sw_word_mask` enables only the relevant word slots within the line.
5. After **WAIT** + **CAPTURE**, the loaded data is distributed back to the correct per-lane slots in `lw_out`.
6. The REQ loop repeats for any remaining un-serviced lanes (different cache lines), then enters **DONE** and signals `mem_done` to the warp scheduler.

### Benefits

| Benefit | Detail |
|---------|--------|
| Reduced memory traffic | 16 logical accesses → 1 physical transaction when all lanes are in the same cache line |
| Improved bandwidth | Full cache-line utilisation on every transaction |
| Lower latency | One scheduler FSM cycle instead of 16 sequential accesses |
| Higher throughput | Enables full-warp load/store in constant cycles regardless of lane count |

---

## Test Output

### Matrix Addition

```
=== Matrix Addition: PASS ===
```

### Matrix Multiplication

```
=== Matrix Multiplication: PASS ===
```

---

## Running the Simulation

### Prerequisites

- Icarus Verilog (`iverilog`) or any standard Verilog-2005 simulator
- GTKWave (for waveform viewing)

### Compile and Simulate

```bash
# Matrix Addition
iverilog -o sim_add -g2005 rtl/*.v tests/tb_matrix_add.v
vvp sim_add

# Matrix Multiplication
iverilog -o sim_mul -g2005 rtl/*.v tests/tb_matrix_mul.v
vvp sim_mul
```

### View Waveforms

```bash
gtkwave waves/tb_matrix_add.vcd
gtkwave waves/tb_matrix_mul.vcd
```

Suggested signals to add in GTKWave:

```
clk
rst
current_warp_id[1:0]
opcode[3:0]
mem_req_pulse
ms_mem_write
ms_addr_out[15:0]
done
```

---

## Performance Analysis

### Matrix Addition vs. Multiplication

| Metric | Addition | Multiplication |
|--------|:---:|:---:|
| Clock cycles | 42 | 247 |
| Runtime | 425 ns | 2475 ns |
| Memory ops | 3 | ~24+ |
| ALU ops per element | 1 ADD | 4 MUL + 4 ADD |
| Inner loop iterations | — | 4 (per element) |
| Parallelism | 16 lanes / op | 16 lanes / op |

Despite the inner loop, all 16 output elements still compute **in parallel** within each loop iteration. The higher cycle count for multiplication reflects the sequential loop body, not a reduction in parallelism.

### Coalescing Efficiency

Both kernels achieve **16:1 coalescing** on every load and store because the lanes access a contiguous 16-element block, which fits exactly in one 16-word cache line. No second REQ pass is needed per memory operation.

---

## Future Improvements

- Branch divergence handling (per-lane active mask modification)
- L1 cache hierarchy to hide multi-cycle memory latency
- Shared memory (scratchpad) for warp-level data exchange
- Pipelined execution to overlap instruction stages
- Floating-point ALU (IEEE 754 single-precision)
- Tensor core instructions (4×4 matrix multiply-accumulate in one op)
- Multiple Streaming Multiprocessors (SMs) with inter-SM synchronisation
- Configurable warp count and lane width via parameters

---

## Author

**Bibhav Jha**

Designed for parallel matrix computation, warp scheduling, and memory coalescing demonstrations.