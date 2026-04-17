BITS 16
ORG 0

mov ax, 0b0000_0000_0010_1001
mov bx, 0b0000_0100_1110_1101
add ax, bx

hlt
