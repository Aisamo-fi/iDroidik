    .text
    .globl _start
_start:
    mov x0, sp
    mov x1, xzr
    adrp x2, main
    add x2, x2, :lo12:main
    adrp x3, structors
    add x3, x3, :lo12:structors
    b __libc_init
    .data
structors: .quad 0,0,0,0,0,0
