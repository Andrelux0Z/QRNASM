; ============================================
; IS_FIXED_POSITION
; Verifica si una posición (fila, columna) es una zona fija del QR
; que NO debe ser modificada (patrones de posición, timing, etc.)
; 
; Entrada: EAX = fila (0-24), EBX = columna (0-24)
; Salida: AL = 1 si es zona fija, 0 si es modificable
; ============================================
is_fixed_position:
    push ebx
    push ecx
    push edx
    
    ; Patrones de posición (7x7) en las esquinas
    ; Patrón superior izquierdo: [0-8][0-8] (incluye separador blanco)
    cmp eax, 8
    jg .check_top_right
    cmp ebx, 8
    jg .check_top_right
    mov al, 1                        ; Es zona fija
    jmp .done
    
.check_top_right:
    ; Patrón superior derecho: [0-8][17-24] (columna 16 es separador modificable)
    cmp eax, 8
    jg .check_bottom_left
    cmp ebx, 17
    jl .check_bottom_left
    mov al, 1
    jmp .done
    
.check_bottom_left:
    ; Patrón inferior izquierdo: [16-24][0-8]
    cmp eax, 16
    jl .check_timing_horizontal
    cmp ebx, 8
    jg .check_timing_horizontal
    mov al, 1
    jmp .done
    
.check_timing_horizontal:
    ; Timing pattern horizontal: fila 6, columnas [8-16]
    cmp eax, 6
    jne .check_timing_vertical
    cmp ebx, 8
    jl .check_timing_vertical
    cmp ebx, 16
    jg .check_timing_vertical
    mov al, 1
    jmp .done
    
.check_timing_vertical:
    ; Timing pattern vertical: columna 6, filas [8-16]
    cmp ebx, 6
    jne .check_dark_module
    cmp eax, 8
    jl .check_dark_module
    cmp eax, 16
    jg .check_dark_module
    mov al, 1
    jmp .done
    
.check_dark_module:
    ; Dark module (siempre oscuro): [4*version + 9, 8] = [17, 8] para version 2
    cmp eax, 17
    jne .check_alignment_pattern
    cmp ebx, 8
    jne .check_alignment_pattern
    mov al, 1
    jmp .done
    
.check_alignment_pattern:
    ; Patrón de alineación 5x5 centrado en (18, 18)
    ; Rango: filas [16-20], columnas [16-20]
    cmp eax, 16
    jl .check_format_info
    cmp eax, 20
    jg .check_format_info
    cmp ebx, 16
    jl .check_format_info
    cmp ebx, 20
    jg .check_format_info
    mov al, 1
    jmp .done
    
.check_format_info:
    ; Format information (alrededor de los patrones de posición)
    ; Horizontal: fila 8, columnas [0-8] y [17-24] (columna 16 no es fija)
    cmp eax, 8
    jne .check_format_vertical
    cmp ebx, 17
    jl .is_format_h1
    mov al, 1                        ; columnas 17-24
    jmp .done
.is_format_h1:
    cmp ebx, 8
    jg .check_format_vertical
    mov al, 1                        ; columnas 0-8
    jmp .done
    
.check_format_vertical:
    ; Vertical: columna 8, filas [0-8] y [16-24]
    cmp ebx, 8
    jne .not_fixed
    cmp eax, 16
    jl .is_format_v1
    mov al, 1                        ; filas 16-24
    jmp .done
.is_format_v1:
    cmp eax, 8
    jg .not_fixed
    mov al, 1                        ; filas 0-8
    jmp .done
    
.not_fixed:
    mov al, 0                        ; No es zona fija
    
.done:
    pop edx
    pop ecx
    pop ebx
    ret