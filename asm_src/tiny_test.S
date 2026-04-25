BITS 16
ORG 0

jmp _start

section .data

value dw 0x1234

section .text

_start:
; mov ax, 0x0
; mov bx, 0x0

mov al, 0x1

mov ax, 0xff
mov bx, 0x1
add ax, bx

; jmp [value]

; mov al, 0x1
; mov bl, 0x1
; add al, bl

; mov cx, 0x1000
; ; add ax, cx
; add al, ch

; mov ax, 0x0
; mov bx, ax
; mov cx, ax
; mov dx, ax

; mov sp, ax
; mov bp, ax
; mov si, ax
; mov di, ax

; mov ax, 0x42
; mov al, 0x10

; mov ax, [bx + si + 10h]



; jmp 0h
; jmp _start
; end:
    ; jmp end

hlt