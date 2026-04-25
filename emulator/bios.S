CPU 8086
BITS 16
ORG 0xF0000


; -------------------------------------------------
; BIOS MAIN ENTRY
; -------------------------------------------------

boot_entry:
    cli
    cld


    ; set up segment registers
    ; mov ax, 0x0
    mov ax, 0xB800
    mov es, ax
    mov ds, ax

    xor di, di

    ; write "HI" to VGA text memory
    mov al, 'H'
    mov ah, 0x07
    stosw

    mov al, 'I'
    mov ah, 0x07
    stosw

    lodsw

halt:
    hlt
    jmp halt

; -------------------------------------------------
; RESET VECTOR (0xFFFF0 physical = 0xFFF0 offset)
; -------------------------------------------------

times 0xFFF0 - ($ - $$) db 0x0

reset_vector:
    jmp 0xF000:boot_entry

times 0xFFFF - ($ - $$) db 0x00