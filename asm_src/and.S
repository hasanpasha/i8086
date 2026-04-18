BITS 16
ORG 0

; mov bx, 0

; mov byte [bx], 0b1000_0110
; or byte [bx], 0b1111_0011

mov al, 0b1000_0110
mov ah, 0b1000_1001
; or al, ah

hlt