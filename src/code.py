#!/usr/bin/env python3
OP = dict(ADD=0,SUB=1,AND=2,OR=3,XOR=4,MUL=5,LW=6,SW=7,ADDI=8,SUBI=9,
          SLT=0xA,BEQ=0xB,BLT=0xC,JMP=0xD,DIV=0xE,HALT=0xF)

def enc_rrr(op, rd, rs1, rs2):
    return (OP[op]<<12) | (rd<<8) | (rs2<<4) | rs1

def enc_rri(op, rd, rs1, imm):
    return ((imm & 0xFFFF) << 16) | (OP[op]<<12) | (rd<<8) | rs1

def enc_lw(rd, rs1, imm):
    return enc_rri('LW', rd, rs1, imm)

def enc_sw(data, base, imm):
    return ((imm & 0xFFFF) << 16) | (OP['SW']<<12) | (data<<4) | base

def halt():
    return (OP['HALT']<<12)

prog = []

# ---- Write A matrix (16 words) ----
prog.append( enc_rri('ADDI',1,0,0) )
for i in range(16):
    prog.append( enc_rri('ADDI',2,0,i+1) )
    prog.append( enc_sw(2,1,i) )

# ---- Write B matrix (64 words) ----
prog.append( enc_rri('ADDI',3,0,64) )
for i in range(64):
    prog.append( enc_rri('ADDI',4,0,i+1) )
    prog.append( enc_sw(4,3,i) )

# ---- Clear C (64 words) ----
prog.append( enc_rri('ADDI',5,0,128) )
prog.append( enc_rri('ADDI',6,0,0) )
for i in range(64):
    prog.append( enc_sw(6,5,i) )

# ---- Matrix multiply ----
mm_start = len(prog)
prog.append( enc_rri('ADDI',2,0,4) )         # r2 = K = 4
prog.append( enc_rrr('MUL',3,13,2) )         # r3 = i*4
prog.append( enc_rrr('MUL',4,13,14) )        # r4 = i*16
prog.append( enc_rri('ADDI',8,0,128) )       # r8 = 128
prog.append( enc_rrr('ADD',4,4,8) )          # r4 = 128 + i*16
prog.append( enc_rrr('ADD',4,4,15) )         # r4 = &C[i][j]
prog.append( enc_rri('ADDI',7,0,64) )        # r7 = 64
prog.append( enc_rri('ADDI',5,0,0) )         # acc = 0
prog.append( enc_rri('ADDI',6,0,0) )         # k = 0
# LOOP START
loop_pc = len(prog)
prog.append( enc_rrr('ADD',10,3,6) )         # r10 = &A[i][k]
prog.append( enc_lw(11,10,0) )               # r11 = A[i][k]
prog.append( enc_rrr('MUL',12,6,14) )        # r12 = k*16
prog.append( enc_rrr('ADD',12,12,7) )        # r12 = 64 + k*16
prog.append( enc_rrr('ADD',12,12,15) )       # r12 = &B[k][j]
prog.append( enc_lw(1,12,0) )                # r1  = B[k][j]
prog.append( enc_rrr('MUL',11,11,1) )        # r11 = A*B
prog.append( enc_rrr('ADD',5,5,11) )         # acc += product
prog.append( enc_rri('ADDI',6,6,1) )         # k++
blt_pc = len(prog)
offset = (loop_pc - blt_pc) & 0xFFFF
prog.append( ((offset << 16) | (OP['BLT'] << 12) | (2 << 4) | 6) )
prog.append( enc_sw(5,4,0) )                 # C[i][j] = acc
prog.append( halt() )

with open('memfile.hex','w') as f:
    f.write("// self-initialising matmul kernel\n@00\n")
    for w in prog:
        f.write(f"{w:08X}\n")