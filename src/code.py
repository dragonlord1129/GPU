# generate_hex.py – creates instruction and data memory initialization files

# Instruction memory: 32768 words (32-bit each)
INSTR_DEPTH = 32768
instr_mem = [0] * INSTR_DEPTH

# Test program (warp 0)
instr_mem[0x0000] = 0x04000805   # LW r1, 0x0805(r0)
instr_mem[0x0001] = 0x04000806   # LW r2, 0x0806(r0)
instr_mem[0x0002] = 0x00221800   # ADD r3, r1, r2
instr_mem[0x0003] = 0x08030807   # SW r3, 0x0807(r0)
instr_mem[0x0004] = 0xFC000000   # HALT (warp 0)

# Warp 1 starts at 0x10
instr_mem[0x0010] = 0xFC000000   # HALT

# Warp 2 starts at 0x20
instr_mem[0x0020] = 0xFC000000   # HALT

# Warp 3 starts at 0x30
instr_mem[0x0030] = 0xFC000000   # HALT

# All other locations remain 0x00000000

# Write memfile.hex
with open("memfile.hex", "w") as f:
    for word in instr_mem:
        f.write(f"{word:08X}\n")
print("Generated memfile.hex")

# Data memory bank 5: 256 words, value at address 0x80 = 0x0000000A
BANK_DEPTH = 256
bank5 = [0] * BANK_DEPTH
bank5[0x80] = 0x0000000A

with open("bank5.hex", "w") as f:
    for word in bank5:
        f.write(f"{word:08X}\n")
print("Generated bank5.hex")

# Data memory bank 6: 256 words, value at address 0x80 = 0x00000005
bank6 = [0] * BANK_DEPTH
bank6[0x80] = 0x00000005

with open("bank6.hex", "w") as f:
    for word in bank6:
        f.write(f"{word:08X}\n")
print("Generated bank6.hex")