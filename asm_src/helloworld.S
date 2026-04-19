CPU 8086
BITS 16
ORG 0

jmp setup

stack_bottom: times 0xFF db 0
stack_top:

setup:
    mov ax, stack_top
    mov ss, ax
    mov sp, stack_top-stack_bottom

    jmp main

main:
    push bp
    mov bp, sp

    mov ax, 0x1
    push ax
    push ax
    call addTwo
    sub sp, 4
    add ax, 4

    cmp ax, 6
    jne main

    pop bp
    jmp halt

addTwo:
    push bp
    mov bp, sp

    push bx

    mov bx, [bp+4]
    mov ax, [bp+6]

    add ax, bx

    pop bx

    pop bp
    ret

halt:
    hlt
    jmp halt