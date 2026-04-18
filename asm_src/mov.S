BITS 16
ORG 0

section .text

mov ax, 0x100
mov ds, ax

mov bx, 0x200
mov es, bx

mov ax, 0x0
mov si, ax
mov di, ax

; set direction flag 
cld
and al, 1

loop:
    mov [si], si
    movsb

    cmp si, 0x40
    jnp loop

lahf

or al, al

mov al, 0b0010_1000
sahf

hlt