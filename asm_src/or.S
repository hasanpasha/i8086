BITS 16
ORG 0

mov al, 0b1001_0110
mov ah, 0b0110_1001
or al, ah

hlt