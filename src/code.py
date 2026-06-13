# Tiny assembler for the mini-SIMT ISA -> verifies encodings and emits annotated memfile.hex
# instr = (imm<<16)|(op<<12)|(rd<<8)|(rs2<<4)|rs1
OP = dict(ADD=0,SUB=1,AND=2,OR=3,XOR=4,MUL=5,LW=6,SW=7,ADDI=8,SUBI=9,
          SLT=0xA,BEQ=0xB,BLT=0xC,JMP=0xD,DIV=0xE,HALT=0xF)

def R(s): return int(s[1:])  # 'r13'->13

# program: (mnemonic, asm-text-comment, fields)
# fields encode (op, rd, rs2, rs1, imm); helpers below build them.
def rrr(op,rd,rs1,rs2): return (OP[op],rd,rs2,rs1,0)         # rd = rs1 op rs2
def rri(op,rd,rs1,imm):  return (OP[op],rd,0,rs1,imm&0xFFFF) # rd = rs1 op imm
def lw(rd,rs1,imm):      return (OP['LW'],rd,0,rs1,imm&0xFFFF)
def sw(data,base,imm):   return (OP['SW'],0,data,base,imm&0xFFFF)
def blt(rs1,rs2,imm):    return (OP['BLT'],0,rs2,rs1,imm&0xFFFF)
def halt():              return (OP['HALT'],0,0,0,0)

# C[i][j] = sum_{k=0..3} A[i][k]*B[k][j]
#   i = blockIdx (R13, warp id),  j = threadIdx (R15, lane id),  R14 = 16
#   A @ 0   (A[i][k] = word i*4+k)         4x4
#   B @ 64  (B[k][j] = word 64+k*16+j)     4x16
#   C @ 128 (C[i][j] = word 128+i*16+j)    4x16
prog = [
 # idx  builder                       human-readable
 (rri('ADDI',2,0,4),   "ADDI r2, r0, 4        ; r2 = K = 4 (inner dim & loop bound)"),
 (rrr('MUL',3,13,2),   "MUL  r3, r13, r2       ; r3 = i*4 = &A[i][0]  (baseA=0)"),
 (rrr('MUL',4,13,14),  "MUL  r4, r13, r14      ; r4 = i*16"),
 (rri('ADDI',8,0,128), "ADDI r8, r0, 128      ; r8 = baseC = 128"),
 (rrr('ADD',4,4,8),    "ADD  r4, r4, r8        ; r4 = baseC + i*16"),
 (rrr('ADD',4,4,15),   "ADD  r4, r4, r15       ; r4 = &C[i][j]"),
 (rri('ADDI',7,0,64),  "ADDI r7, r0, 64       ; r7 = baseB = 64"),
 (rri('ADDI',5,0,0),   "ADDI r5, r0, 0        ; r5 = acc = 0"),
 (rri('ADDI',6,0,0),   "ADDI r6, r0, 0        ; r6 = k = 0"),
 # ---- LOOP (idx 9) ----
 (rrr('ADD',10,3,6),   "ADD  r10, r3, r6       ; r10 = &A[i][k]   (LOOP)"),
 (lw(11,10,0),         "LW   r11, r10, 0      ; r11 = A[i][k]   (broadcast load)"),
 (rrr('MUL',12,6,14),  "MUL  r12, r6, r14      ; r12 = k*16"),
 (rrr('ADD',12,12,7),  "ADD  r12, r12, r7      ; r12 = baseB + k*16"),
 (rrr('ADD',12,12,15), "ADD  r12, r12, r15     ; r12 = &B[k][j]"),
 (lw(1,12,0),          "LW   r1, r12, 0       ; r1  = B[k][j]   (coalesced load)"),
 (rrr('MUL',11,11,1),  "MUL  r11, r11, r1      ; r11 = A[i][k]*B[k][j]"),
 (rrr('ADD',5,5,11),   "ADD  r5, r5, r11       ; acc += product"),
 (rri('ADDI',6,6,1),   "ADDI r6, r6, 1        ; k++"),
 (blt(6,2,9-18),       "BLT  r6, r2, LOOP     ; if (k < K) goto LOOP  (imm = 9-18 = -9)"),
 # ---- end loop ----
 (sw(5,4,0),           "SW   r5, r4, 0        ; C[i][j] = acc   (coalesced store)"),
 (halt(),              "HALT"),
]

def encode(f):
    op,rd,rs2,rs1,imm = f
    return ((imm&0xFFFF)<<16)|((op&0xF)<<12)|((rd&0xF)<<8)|((rs2&0xF)<<4)|(rs1&0xF)

N=256
words=[0x0000F000]*N   # HALT fill
for i,(f,_) in enumerate(prog): words[i]=encode(f)

with open("memfile.hex","w") as fh:
    fh.write("// memfile.hex -- matrix-multiply kernel  C[4][16] = A[4][4] x B[4][16]\n")
    fh.write("// auto layout: A@0  B@64  C@128 ; all 4 warps enter at PC 0 (blockIdx=warp id)\n")
    fh.write("// (Verilog $readmemh ignores // comments; addresses 0..%d, rest = HALT)\n@00\n" % (len(prog)-1))
    for i,(f,txt) in enumerate(prog):
        fh.write("%08X    // %02X: %s\n" % (encode(f), i, txt))
    fh.write("// ---- remaining instruction memory: HALT ----\n")
    fh.write("@%02X\n" % len(prog))
    for a in range(len(prog),N):
        fh.write("0000F000\n")

# print listing
print("ADDR  HEX        ASSEMBLY")
for i,(f,txt) in enumerate(prog):
    print("%02X    %08X   %s" % (i, encode(f), txt))