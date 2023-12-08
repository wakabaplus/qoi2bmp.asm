bits 64

%define QOI_MAGIC "qoif"
%define BMP_MAGIC "BM"

%define sys_read 0
%define sys_write 1
%define sys_open 2
%define sys_close 3
%define sys_newfstat 5
%define sys_mmap 9
%define sys_exit 60

%define QOI_OP_INDEX 0x00
%define QOI_OP_DIFF 0x40
%define QOI_OP_LUMA 0x80
%define QOI_OP_RUN 0xc0
%define QOI_OP_RGB 0xfe
%define QOI_OP_RGBA 0xff

%define stderr 2

struc qoi_header
    .magic: resd 1
    .width: resd 1
    .height: resd 1
    .channels: resb 1
    .colorspace: resb 1
endstruc

struc bmp_header
    .magic: resw 1
    .bfSize: resd 1
    .bfReserved: resd 1
    .bfOffBits: resd 1
    .bV5Size: resd 1
    .bV5Width: resd 1
    .bV5Height: resd 1
    .bV5Planes: resw 1
    .bV5BitCount: resw 1
    .bV5Compression: resd 1
    .bV5SizeImage: resd 1
    .bV5XPelsPerMeter: resd 1
    .bV5YPelsPerMeter: resd 1
    .bV5ClrUsed: resd 1
    .bV5ClrImportant: resd 1
    .bV5RedMask: resd 1
    .bV5GreenMask: resd 1
    .bV5BlueMask: resd 1
    .bV5AlphaMask: resd 1
    .bV5CSType: resd 1
    .bV5Endpoints: resb 36
    .bV5GammaRed: resd 1
    .bV5GammaGreen: resd 1
    .bV5GammaBlue: resd 1
    .bV5Intent: resd 1
    .bV5ProfileData: resd 1
    .bV5ProfileSize: resd 1
    .bV5Reserved: resd 1
endstruc

struc rgba
    .r: resb 1
    .g: resb 1
    .b: resb 1
    .a: resb 1
endstruc

struc finfo
    .fd resq 1
    .size resq 1
    .buf resq 1
endstruc

section .bss
    stat resb 144
    qoi resb finfo_size
    bmp resb finfo_size
    px resb rgba_size
    qoi_wb resq 1
    index resb rgba_size*64
    run resd 1
    tmp resq 1

section .text
global _start

_start:
    mov rcx, [rsp]
    test rcx, rcx
    cmp rcx, 3
    jnz .usage

    mov rdi, [rsp+16]
    xor rsi, rsi
    xor rdx, rdx
    mov rax, sys_open
    syscall
    ; if the retval is negative, the number is errno.
    test rax, rax
    js .error
    mov [qoi+finfo.fd], rax

    mov rdi, rax
    mov rsi, stat
    mov rax, sys_newfstat
    syscall
    test rax, rax
    jnz .error

    xor rdi, rdi
    ; __off_t is 32 or 64bit, but the alignment is 64bit.
    mov rsi, [rsi+0x30] ; st_size
    mov [qoi+finfo.size], rsi
    shr rsi, 0xc ; Assuming pagesize is 4K(0x1000).
    inc rsi
    shl rsi, 0xc
    mov rdx, 1 ; PROT_READ
    mov r10, 2 ; MAP_PRIVATE
    mov r8, [qoi+finfo.fd]
    xor r9, r9
    mov rax, sys_mmap
    syscall
    test rax, rax
    js .error
    mov [qoi+finfo.buf], rax
    lea rbx, [rax+qoi_header_size]
    mov [qoi_wb], rbx

    mov ebx, [rax+qoi_header.magic]
    cmp ebx, QOI_MAGIC
    jnz .error

    mov esi, [rax+qoi_header.width]
    bswap esi
    mov ebx, [rax+qoi_header.height]
    bswap ebx
    imul rsi, rbx
    imul rsi, 4 ; output bmp's channel is 4
    lea rsi, [rsi+bmp_header_size]
    mov [bmp+finfo.size], rsi

    xor rdi, rdi
    shr rsi, 0xc
    inc rsi
    shl rsi, 0xc
    mov rdx, 2 ; PROT_WRITE
    mov r10, 34 ; MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9, r9
    mov rax, sys_mmap
    syscall
    test rax, rax
    js .error
    mov [tmp], rax

    mov rsi, [bmp+finfo.size]
    xor rdi, rdi
    shr rsi, 0xc
    inc rsi
    shl rsi, 0xc
    mov rdx, 2 ; PROT_WRITE
    mov r10, 34 ; MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9, r9
    mov rax, sys_mmap
    syscall
    test rax, rax
    js .error
    mov [bmp+finfo.buf], rax
    mov [rax+bmp_header.magic], word BMP_MAGIC
    mov edi, [bmp+finfo.size]
    mov [rax+bmp_header.bfSize], edi
    mov [rax+bmp_header.bfOffBits], dword 0x8A
    mov [rax+bmp_header.bV5Size], dword 0x7C ; BITMAPV5HEADER
    mov rdi, [qoi+finfo.buf]
    mov edi, [rdi+qoi_header.width]
    bswap edi
    mov [rax+bmp_header.bV5Width], edi
    mov rdi, [qoi+finfo.buf]
    mov edi, [rdi+qoi_header.height]
    bswap edi
    mov [rax+bmp_header.bV5Height], edi
    mov [rax+bmp_header.bV5Planes], word 1
    mov [rax+bmp_header.bV5BitCount], word 32
    mov [rax+bmp_header.bV5XPelsPerMeter], dword 11811 ; 300dpi
    mov [rax+bmp_header.bV5YPelsPerMeter], dword 11811 ; 300dpi
    mov [rax+bmp_header.bV5CSType], dword 'sRGB'
    mov [rax+bmp_header.bV5Intent], dword 2

    xor r8, r8
    mov rbx, [qoi_wb]

    lea rdi, px
    mov [rdi+rgba.r], byte 0
    mov [rdi+rgba.g], byte 0
    mov [rdi+rgba.b], byte 0
    mov [rdi+rgba.a], byte 0xFF

    .loop:
        cmp dword [run], 0
        ja .run_loop
        mov al, [rbx]
        inc rbx
        cmp al, QOI_OP_RGB
        jz .rgb
        cmp al, QOI_OP_RGBA
        jz .rgba
        mov ah, al
        and ah, 0b11000000
        test ah, ah; QOI_OP_INDEX
        jz .index
        cmp ah, QOI_OP_DIFF
        jz .diff
        cmp ah, QOI_OP_LUMA
        jz .luma
        cmp ah, QOI_OP_RUN
        jz .run
        jmp .add_index

        .rgb:
            lea rdi, px
            mov sil, byte [rbx+rgba.r]
            mov [rdi+rgba.r], sil
            mov sil, byte [rbx+rgba.g]
            mov [rdi+rgba.g], sil
            mov sil, byte [rbx+rgba.b]
            mov [rdi+rgba.b], sil
            add rbx, rgba_size-1
            jmp .add_index

        .rgba:
            lea rdi, px
            mov sil, byte [rbx+rgba.r]
            mov [rdi+rgba.r], sil
            mov sil, byte [rbx+rgba.g]
            mov [rdi+rgba.g], sil
            mov sil, byte [rbx+rgba.b]
            mov [rdi+rgba.b], sil
            mov sil, byte [rbx+rgba.a]
            mov [rdi+rgba.a], sil
            add rbx, rgba_size
            jmp .add_index

        .index:
            movzx rax, al
            lea rsi, [index+rgba_size*rax]
            lea rdi, px
            movsd
            jmp .add_index

        .diff:
            lea rdi, px
            mov sil, al
            sar sil, 0x4
            and sil, 0x3
            sub sil, 0x2
            mov dl, [rdi+rgba.r]
            add dl, sil
            mov [rdi+rgba.r], dl
            mov sil, al
            sar sil, 0x2
            and sil, 0x3
            sub sil, 0x2
            mov dl, [rdi+rgba.g]
            add dl, sil
            mov [rdi+rgba.g], dl
            mov sil, al
            and sil, 0x3
            sub sil, 0x2
            mov dl, [rdi+rgba.b]
            add dl, sil
            mov [rdi+rgba.b], dl
            jmp .add_index

        .luma:
            lea rdi, px
            and al, 0x3f
            sub al, 32

            mov cl, [rdi+rgba.g]
            add cl, al
            mov [rdi+rgba.g], cl

            sub al, 8
            mov dl, [rbx]
            shr dl, 4
            and dl, 0xf
            mov cl, [rdi+rgba.r]
            add cl, al
            add cl, dl
            mov [rdi+rgba.r], cl

            mov dl, [rbx]
            and dl, 0xf
            mov cl, [rdi+rgba.b]
            add cl, al
            add cl, dl
            mov [rdi+rgba.b], cl

            inc rbx
            jmp .add_index

        .run:
            and al, 0x3f
            mov byte [run], al
            jmp .add_index

        .add_index:
            movzx rdx, byte [px+rgba.r]
            lea rdi, [rdx*3]
            movzx rdx, byte [px+rgba.g]
            lea rax, [rdx*5]
            add rdi, rax
            movzx rdx, byte [px+rgba.b]
            lea rax, [rdx*5]
            lea rax, [rax+rdx*2]
            add rdi, rax
            movzx rdx, byte [px+rgba.a]
            lea rax, [rdx*5]
            lea rax, [rax+rdx*4]
            lea rax, [rax+rdx*2]
            add rdi, rax
            and rdi, 63 ; rdi % 64
            lea rsi, [px]
            lea rdi, [index+rgba_size*rdi]
            movsd
            jmp .next

        .run_loop:
            mov edi, dword [run]
            dec edi
            mov dword [run], edi
            jmp .next

        .next:
            mov rax, [tmp]
            mov edx, [px]
            mov ecx, edx
            shr edx, 16
            xchg dl, cl
            shl edx, 16
            mov dx, cx
            mov [rax+r8], edx
            add r8, rgba_size
            mov rcx, [bmp+finfo.size]
            lea rcx, [rcx-bmp_header_size]
            cmp r8, rcx
            jbe .loop
            xor r9, r9

        .upside:
            mov rdi, [qoi+finfo.buf]
            mov ecx, [rdi+qoi_header.width]
            bswap ecx
            lea ecx, [ecx*rgba_size]
            sub r8, rcx
            lea rsi, [rax+r8]
            mov rdi, [bmp+finfo.buf]
            lea rdi, [rdi+bmp_header_size+r9]
            add r9, rcx
            rep movsb
            test r8, r8
            jns .upside

    mov rdi, [rsp+24]
    mov rsi, 577 ; O_CREAT | O_WRONLY | O_TRUNC (creat)
    mov rdx, 0o644 ; rw-, r--, r--
    mov rax, sys_open
    syscall
    test rax, rax
    js .error

    mov rdi, rax
    mov rsi, [bmp+finfo.buf]
    mov rdx, [bmp+finfo.size] ; finfo.size
    mov rax, sys_write
    syscall

    mov rax, sys_close
    syscall

    jmp exit

    .error:
        mov rsi, errstr
        mov rdx, errstr_len+usage_len
        push rax
        call write
        pop rax
        ; remove the sign
        neg rax
        jmp exit

    .usage:
        mov rsi, usage
        mov rdx, usage_len
        call write
        jmp exit

write:
    mov rax, sys_write
    mov rdi, stderr
    syscall
    ret

exit:
    mov rdi, rax
    mov rax, sys_exit
    syscall

section .data
    errstr db "An error happened. Type `errno $?` for details. (require moreutils)", 0x0a
    usage db "Usage: <input_qoi> <output_bmp>", 0x0a
    usage_len equ $ - usage
    errstr_len equ $ - errstr - usage_len