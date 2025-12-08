;Proyecto lector QR de Arquitectura de Computadores
;Andres Padilla y Marco Sandoval
;
;Objetivo: Programa que puede leer un codigo QR version 2 en formato PBM
;          y decodificar el texto contenido.
;Entrada: Archivo PBM con codigo QR
;Salida: Texto decodificado
;
;Nota: No se comprueban bits de corrección de errores

%include "io.mac"

.DATA

filename             db "qr_output.pbm",0

;==== Mensajes e interfaz ====
msg_loaded db 'Archivo QR cargado', 10, 0

msg_error db 'Error al abrir archivo', 10, 0

msg_bienvenida       db "==========================",0Ah
                     db "  Lector de codigos QR    ",0Ah
                     db "==========================",0Ah,0

msg_menu             db "1. Leer codigo QR",0Ah
                     db "2. Salir",0Ah,0

msg_resultado        db "Texto decodificado: ",0

msg_error_modo       db "Error: Modo no soportado (solo Byte mode)",0Ah,0

msg_debug_bits       db "Bits leidos: ",0


.UDATA

; ==== Entradas de usuario ====
opcion_menu          resb 1         ; Opcion del menu

; ==== Variables internas ====
file_buffer          resb 1536      ; Buffer para todo el archivo (PBM ~1261 bytes)
matrix               resb 625       ; 25x25 matriz sin saltos de línea
header_size          resd 1         ; Tamaño del encabezado PBM
fd                   resd 1         ; File descriptor
bytes_read           resd 1         ; Bytes leídos

; ==== Variables para decodificación ====
data_bits            resb 512       ; Bits de datos extraídos del QR
data_length          resd 1         ; Cantidad de bits extraídos
current_bit_idx      resd 1         ; Índice actual en data_bits
text_char_count      resd 1         ; Número de caracteres a decodificar

; ==== Buffer de texto de salida ====
texto_decodificado   resb 64        ; Buffer para el texto decodificado (max 32 chars + margen)

; ==== Variables para recorrido zigzag ====
zigzag_col           resd 1         ; Columna actual en zigzag
zigzag_row           resd 1         ; Fila actual en zigzag
zigzag_direction     resd 1         ; Dirección: 1=subiendo, 0=bajando
zigzag_idx           resd 1         ; Índice en data_bits


.CODE
.STARTUP
; Mostrar bienvenida
PutStr msg_bienvenida
nwln

menu:
   ; Mostrar menu
   PutStr msg_menu
   nwln
  
   ; Leer opcion
   GetCh [opcion_menu]
   nwln
  
   ; Verificar opcion
   mov al, [opcion_menu]
   cmp al, '1'
   je iniciar_lector
   cmp al, '2'
   je salir_programa
   jmp menu                    ;Opcion invalida, volver al menu


iniciar_lector:
   ; Leer y procesar el archivo QR
   call procesar_qr_lectura
  
   ; Mostrar resultado
   PutStr msg_resultado
   PutStr texto_decodificado
   nwln
   nwln
  
   jmp menu          

salir_programa:
   .EXIT

procesar_qr_lectura:
   ; ============================================
   ; 1. ABRIR ARCHIVO
   ; ============================================
    mov eax, 5              ; sys_open
    mov ebx, filename       ; Nombre del archivo
    mov ecx, 0              ; Modo: Solo lectura
    int 0x80
    cmp eax, 0
    js  error               ; Si error, salir
    mov [fd], eax           ; Guardar descriptor del archivo

   ; ============================================
   ; 2. LEER ARCHIVO
   ; ============================================
    mov eax, 3                  ; sys_read
    mov ebx, [fd]
    mov ecx, file_buffer
    mov edx, 1536
    int 0x80
    
    mov [bytes_read], eax
    
    ; Imprimir mensaje
    PutStr msg_loaded
    nwln
    
    ; Cerrar archivo
    mov eax, 6                  ; sys_close
    mov ebx, [fd]
    int 0x80
    
    ; ============================================
    ; 3. EXTRAER MATRIZ DEL BUFFER
    ; ============================================
    call extract_matrix
    
    ; ============================================
    ; 4. LEER BITS EN ORDEN ZIGZAG
    ; ============================================
    call zigzag_read_data_bits
    
    ; ============================================
    ; 5. DECODIFICAR BITS A TEXTO
    ; ============================================
    call decodificar_bits
    
    ret


; ============================================
; FUNCIONES
; ============================================

; ============================================
; EXTRACT_MATRIX
; Extrae la matriz 25x25 del buffer del archivo PBM
; ignorando el encabezado (P1, 25 25, etc.)
; Entrada: file_buffer contiene el archivo completo
; Salida: matrix contiene solo los 0s y 1s (625 bytes)
;         header_size contiene el tamaño del encabezado
; ============================================
extract_matrix:
    pusha
    
    mov esi, file_buffer        ; ESI apunta al inicio del buffer
    xor ecx, ecx                ; ECX = contador de posición en el buffer
    
    ; Saltar primera línea (P1)
.skip_first_line:
    lodsb                       ; Cargar byte en AL
    inc ecx
    cmp al, 0x0A                ; Buscar newline
    jne .skip_first_line
    
    ; Saltar segunda línea (25 25)
.skip_second_line:
    lodsb
    inc ecx
    cmp al, 0x0A                ; Buscar newline
    jne .skip_second_line
    
    ; ECX ahora tiene el tamaño del encabezado
    mov [header_size], ecx
    
    ; Ahora extraer solo los 0s y 1s, ignorando espacios y saltos de línea
    mov edi, matrix             ; EDI apunta a matrix
    xor edx, edx                ; EDX = contador de bits extraídos
    
.extract_loop:
    cmp edx, 625                ; ¿Ya tenemos 625 bits?
    jge .extract_done
    
    lodsb                       ; Cargar siguiente byte
    
    ; Verificar si es '0' o '1'
    cmp al, '0'
    je .is_valid_bit
    cmp al, '1'
    je .is_valid_bit
    
    ; Si no es 0 o 1, ignorar (espacios, newlines, etc.)
    jmp .extract_loop
    
.is_valid_bit:
    mov [edi], al               ; Guardar el bit en matrix
    inc edi
    inc edx
    jmp .extract_loop
    
.extract_done:
    popa
    ret

; ============================================
; GET_BIT_FROM_MATRIX_XY
; Obtiene un bit de la matriz usando coordenadas (fila, columna)
; Entrada: EAX = fila (0-24), EBX = columna (0-24)
; Salida: AL = '0' o '1'
; ============================================
get_bit_from_matrix_xy:
    push edx
    push esi
    
    ; Calcular índice: fila * 25 + columna
    push ebx
    mov edx, 25
    mul edx                     ; EAX = fila * 25
    pop ebx
    add eax, ebx                ; EAX = fila * 25 + columna
    
    ; Obtener el bit
    mov esi, matrix
    add esi, eax
    mov al, [esi]
    
    pop esi
    pop edx
    ret

; ============================================
; IS_FIXED_POSITION
; Verifica si una posición (fila, columna) es una zona fija del QR
; que NO debe ser leída para datos (patrones de posición, timing, etc.)
; 
; Entrada: EAX = fila (0-24), EBX = columna (0-24)
; Salida: AL = 1 si es zona fija, 0 si contiene datos
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
    ; Patrón superior derecho: [0-8][17-24]
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
    ; Dark module: [17, 8] para version 2
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
    ; Format information
    ; Horizontal: fila 8, columnas [0-8] y [17-24]
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


; ============================================
; ZIGZAG_CORE
; Recorre la matriz QR en patrón zigzag, de derecha a izquierda.
; 
; Patrón de recorrido:
;   - Empieza en columna 24, procesa pares (col, col-1)
;   - Alterna entre subir (fila 24→0) y bajar (fila 0→24)
;   - Avanza 2 columnas a la izquierda en cada iteración
;   - El callback decide qué hacer con cada posición
; 
; Parámetros:
;   EDI -> dirección de la función callback
;          Callback recibe: EAX=fila, EBX=columna
; ============================================
zigzag_core:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi                         ; Guardar callback
    
    ; Iniciar en esquina inferior derecha
    mov dword [zigzag_col], 24       ; Columna inicial: 24 (derecha)
    mov dword [zigzag_direction], 1  ; 1 = subiendo, 0 = bajando
    
.column_loop:
    cmp dword [zigzag_col], 0
    jl .done
    
    ; Determinar fila inicial según dirección
    cmp dword [zigzag_direction], 1
    je .init_up
    mov dword [zigzag_row], 0
    jmp .process_pair
.init_up:
    mov dword [zigzag_row], 24
    
.process_pair:
    ; Todas las columnas procesan 25 filas
    mov ecx, 25
    
.row_loop:
    push ecx                         ; Guardar contador
    
    ; Procesar columna actual
    mov eax, [zigzag_row]
    mov ebx, [zigzag_col]
    
    ; Verificar límites de fila
    cmp eax, 0
    jl .skip_col1
    cmp eax, 24
    jg .skip_col1
.process_col1:
    
    ; Llamar callback con EAX=fila, EBX=columna
    mov esi, [esp + 4]               ; Recuperar callback desde stack
    call esi
    
.skip_col1:
    ; Procesar columna-1
    mov edx, [zigzag_col]
    dec edx
    cmp edx, 0
    jl .skip_col2
    
    mov eax, [zigzag_row]
    cmp eax, 0
    jl .skip_col2
    cmp eax, 24
    jg .skip_col2
.process_col2:
    
    mov ebx, edx
    mov esi, [esp + 4]               ; Recuperar callback
    call esi
    
.skip_col2:
    ; Avanzar fila según dirección
    cmp dword [zigzag_direction], 1
    je .dec_row
    inc dword [zigzag_row]
    jmp .next_row
.dec_row:
    dec dword [zigzag_row]
    
.next_row:
    pop ecx
    dec ecx
    jnz .row_loop
    
    ; Al terminar todas las filas del par de columnas:
    ; 1. Invertir dirección (subiendo↔bajando)
    xor dword [zigzag_direction], 1
    
    ; 2. Mover al siguiente par de columnas (2 a la izquierda)
    sub dword [zigzag_col], 2
    jmp .column_loop
    
.done:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret


; ============================================
; Callbacks para zigzag_core
; ============================================

; Callback: leer bit de datos (ignorando zonas fijas)
; Entrada: EAX=fila, EBX=columna
zigzag_callback_read_data:
    push ecx
    push edx
    push edi
    
    ; Guardar fila y columna en registros seguros
    mov ecx, eax                      ; ECX = fila
    mov edx, ebx                      ; EDX = columna
    
    ; Verificar si es zona fija (modifica AL)
    call is_fixed_position
    cmp al, 1
    je .skip                          ; Si es fija, no leer
    
    ; Restaurar fila y columna para get_bit_from_matrix_xy
    mov eax, ecx
    mov ebx, edx
    
    call get_bit_from_matrix_xy
    
    ; Guardar en buffer de datos
    mov edi, data_bits
    add edi, [zigzag_idx]
    mov [edi], al
    inc dword [zigzag_idx]
    
.skip:
    pop edi
    pop edx
    pop ecx
    ret


; ============================================
; ZIGZAG_READ_DATA_BITS
; Lee los bits de datos del QR en orden zigzag
; (ignorando zonas fijas) y los almacena en data_bits
; 
; Salida: data_bits contiene los bits de datos ('0' y '1')
;         zigzag_idx contiene la cantidad de bits leídos
; ============================================
zigzag_read_data_bits:
    push eax
    push edi
    
    mov dword [zigzag_idx], 0
    mov edi, zigzag_callback_read_data
    call zigzag_core
    
    ; Guardar cantidad de bits leídos
    mov eax, [zigzag_idx]
    mov [data_length], eax
    
    pop edi
    pop eax
    ret


; ============================================
; DECODIFICAR_BITS
; Decodifica los bits leídos del QR a texto
; 
; Formato esperado: [4 bits modo][8 bits contador][datos]
; Modo 0100 = Byte mode (8 bits por carácter)
; 
; Entrada: data_bits contiene los bits ('0' y '1' como caracteres)
; Salida: texto_decodificado contiene el texto decodificado
; ============================================
decodificar_bits:
    pusha
    
    mov esi, data_bits           ; Fuente: bits leídos
    mov edi, texto_decodificado  ; Destino: texto decodificado
    
    ; ===== LEER 4 BITS DE MODO =====
    ; Verificar que sea 0100 (Byte mode)
    ; Bit 0
    lodsb
    cmp al, '0'
    jne .error_modo
    ; Bit 1
    lodsb
    cmp al, '1'
    jne .error_modo
    ; Bit 2
    lodsb
    cmp al, '0'
    jne .error_modo
    ; Bit 3
    lodsb
    cmp al, '0'
    jne .error_modo
    
    ; ===== LEER 8 BITS DEL CONTADOR (LSB primero) =====
    xor eax, eax                     ; EAX = 0 (acumulador del contador)
    mov ecx, 8                       ; 8 bits
    mov edx, 1                       ; Valor del bit actual (1, 2, 4, 8...)
    
.read_counter_loop:
    push eax
    lodsb                            ; Leer bit
    cmp al, '1'
    pop eax
    jne .counter_bit_zero
    
    ; Es '1', sumar el valor del bit
    add eax, edx
    
.counter_bit_zero:
    shl edx, 1                       ; Siguiente valor de bit (2, 4, 8...)
    dec ecx
    jnz .read_counter_loop
    
    ; EAX = número de caracteres
    mov [text_char_count], eax
    mov ecx, eax                     ; ECX = contador de caracteres
    
    ; ===== LEER CARACTERES (8 bits cada uno, MSB primero) =====
.char_decode_loop:
    test ecx, ecx
    jz .decode_done
    
    ; Leer 8 bits para formar un carácter
    push ecx
    xor eax, eax                     ; EAX = 0 (acumulador del carácter)
    mov ecx, 8                       ; 8 bits por carácter
    
.bit_decode_loop:
    shl al, 1                        ; Desplazar a la izquierda
    push eax
    lodsb                            ; Leer bit
    cmp al, '1'
    pop eax
    jne .bit_is_zero_decode
    
    ; Es '1', setear el bit
    or al, 1
    
.bit_is_zero_decode:
    dec ecx
    jnz .bit_decode_loop
    
    ; AL tiene el carácter decodificado
    stosb                            ; Guardar en texto_decodificado
    
    pop ecx
    dec ecx
    jmp .char_decode_loop
    
.decode_done:
    ; Agregar null terminator
    mov byte [edi], 0
    
    popa
    ret
    
.error_modo:
    PutStr msg_error_modo
    popa
    ret


error:
   PutStr msg_error
   nwln
   jmp salir_programa
