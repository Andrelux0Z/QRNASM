;Proyecto escaner QR de Arquitectura de Computadores
;Andres Padilla y Marco Sandoval
;
;Objetivo: Programa que puede leer un texto y convertirlo en un codigo QR version 2.
;Entrada: texto (max 32 caracteres)
;Salida: Imagen pbm
;
;Ver readme.txt para documentación completa de funciones

%include "io.mac"

.DATA

filename             db "qr.pbm",0
output_filename      db "qr_output.pbm",0

;==== Mensajes e interfaz ====
msg_loaded db 'Archivo cargado', 10, 0

msg_saved db 'Archivo modificado y guardado', 10, 0

msg_error db 'Error al abrir archivo', 10, 0

msg_bienvenida       db "===========================",0Ah
                     db "  Generador de codigos QR  ",0Ah
                     db "===========================",0Ah,0

msg_menu             db "1. Iniciar generador",0Ah
                     db "2. Salir",0Ah,0

msg_ingreso_texto    db "Ingrese el texto a codificar (max 32 caracteres): ",0

msg_error_longitud   db "Error: El texto excede el maximo de 32 caracteres.",0Ah,0

msg_salida_archivo   db "El codigo QR ha sido generado en qr_output.pbm",0Ah,0

msg_debug_zigzag     db "Bits en orden zigzag: ",0


.UDATA

; ==== Entradas de usuario ====
texto_usuario        resb 33        ; Buffer para el texto del usuario (32 + null terminator)
opcion_menu          resb 1         ; Opcion del menu

; ==== Variables internas ====
file_buffer          resb 1024      ; Buffer para todo el archivo
matrix               resb 625       ; 25x25 matriz sin saltos de línea
matrix_line          resb 625       ; Línea de 625 caracteres (0s y 1s)
header_size          resd 1         ; Tamaño del encabezado PBM
fd                   resd 1         ; File descriptor
fd_output            resd 1         ; File descriptor para archivo de salida
bytes_read           resd 1         ; Bytes leídos

data_bits            resb 512       ; Bits de datos + mode + count indicators
data_length          resd 1         ; Cantidad total de bits (incluyendo mode y count)
current_bit_idx      resd 1         ; Índice actual en data_bits
text_char_count      resd 1         ; Número de caracteres del texto

; ==== Variables para recorrido zigzag ====
zigzag_buffer        resb 625       ; Buffer para almacenar bits en orden zigzag
zigzag_col           resd 1         ; Columna actual en zigzag
zigzag_row           resd 1         ; Fila actual en zigzag
zigzag_direction     resd 1         ; Dirección: 1=subiendo, 0=bajando
zigzag_idx           resd 1         ; Índice en zigzag_buffer


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
   je iniciar_generador
   cmp al, '2'
   je salir_programa
   jmp menu                    ;Opcion invalida, volver al menu




; Convertir texto a binario (ASCII de 8 bits)
; Entrada: texto_usuario contiene el texto
; Salida: data_bits contiene los bits ('0' y '1' como caracteres)
;         data_length contiene la cantidad de bits
;         EAX = número de bits, o -1 si error
texto_a_binario:
    pusha
    
    ; Calcular longitud del texto
    mov esi, texto_usuario
    xor ecx, ecx             ; contador de caracteres
    
.count_loop:
    lodsb                    ; cargar byte de [ESI] en AL
    test al, al              ; verificar si es null terminator
    jz .count_done
    cmp al, 0x0A             ; verificar si es newline
    je .count_done
    cmp al, 0x0D             ; verificar si es carriage return
    je .count_done
    inc ecx
    cmp ecx, 32              ; máximo 32 caracteres
    jg .error_length
    jmp .count_loop
    
.count_done:
    ; ECX = número de caracteres
    ; Calcular bits totales: caracteres * 8
    push ecx
    shl ecx, 3               ; multiplicar por 8 (ECX = ECX * 8)
    mov [data_length], ecx
    pop ecx
    
    ; Convertir cada carácter a 8 bits
    mov esi, texto_usuario   ; puntero al texto
    mov edi, data_bits       ; puntero al buffer de bits
    
.char_loop:
    test ecx, ecx
    jz .done
    
    lodsb                    ; cargar carácter en AL
    cmp al, 0x0A             ; verificar newline
    je .done
    cmp al, 0x0D             ; verificar carriage return
    je .done
    
    ; Convertir este byte a 8 bits
    push ecx
    mov ecx, 8               ; 8 bits por byte
    
.bit_loop:
    shl al, 1                ; desplazar bit más significativo a CF
    jc .bit_is_one
    
.bit_is_zero:
    mov byte [edi], '0'
    jmp .next_bit
    
.bit_is_one:
    mov byte [edi], '1'
    
.next_bit:
    inc edi
    dec ecx
    jnz .bit_loop
    
    pop ecx
    dec ecx
    jmp .char_loop
    
.done:
    popa
    mov eax, [data_length]   ; retornar número de bits
    ret
    
.error_length:
    jmp error






iniciar_generador:
   ; Solicitar texto
   PutStr msg_ingreso_texto
   GetStr texto_usuario, 33
   nwln
  
   ; Aquí iría la lógica de generación del QR
   call procesar_qr
  
   ; Mostrar mensaje de exito
   PutStr msg_salida_archivo
   nwln
  
   jmp menu          

salir_programa:
   .EXIT

procesar_qr:
   ; ============================================
   ; 2. ABRIRI ARCHIVO
   ; ============================================
    mov eax, 5              ; sys_open
    mov ebx, filename       ; Nombre del archivo
    mov ecx, 2              ; Modo: Leer y escribir
    int 0x80                ; Se llama a la interrupción
    cmp eax, 0              ; El resultado fue guardado en EAX: si este dió 0, hubo un error
    js  error               ; Si error, salir
    mov [fd], eax           ; Guardar descriptor del archivo en fd
   ; ============================================
   ; 2. LEER ARCHIVO
   ; ============================================
    mov eax, 3                  ; sys_read
    mov ebx, [fd]
    mov ecx, file_buffer
    mov edx, 1024
    int 0x80
    
    mov [bytes_read], eax
    
    ; Imprimir mensaje
    PutStr msg_loaded
    nwln
    
    ; Cerrar archivo original (solo lectura)
    mov eax, 6                  ; sys_close
    mov ebx, [fd]
    int 0x80
    
    ; ============================================
    ; 3. EXTRAER MATRIZ DEL BUFFER
    ; ============================================
    call extract_matrix
    
    ; ============================================
    ; 4. CONVERTIR MATRIZ A LÍNEA MODIFICABLE
    ; ============================================
    call matrix_to_line
    
    ; ============================================
    ; 5. MODIFICAR LA LÍNEA (EJEMPLO)
    ; ============================================
    ; Ejemplo 1: Cambiar bit en índice 100 a '1'
    ;mov eax, 100                ; índice en la línea
    ;mov cl, '1'                 ; nuevo valor
    ;call set_bit_in_line
    
    ; Ejemplo 2: Cambiar bit en índice 200 a '0'
    ;mov eax, 200
    ;mov cl, '0'
    ;call set_bit_in_line
    
    ; Ejemplo 3: Modificar usando coordenadas [13, 15]
    ; Primero calcular índice: 13 * 25 + 15 = 340
    ;mov eax, 13                 ; fila
    ;mov ebx, 25
    ;mul ebx                     ; EAX = 13 * 25 = 325
    ;add eax, 15                 ; EAX = 340
    ;mov cl, '1'
    ;call set_bit_in_line
    
    ; ============================================
    ; 5.5. CONVERTIR TEXTO A BINARIO Y ESCRIBIR EN ZIGZAG
    ; ============================================
    call texto_a_binario         ; Convertir texto del usuario a bits en data_bits
    call zigzag_write_data_bits  ; Escribir los bits en la matriz siguiendo zigzag
    
    ; ============================================
    ; 5.6. RECONSTRUIR BUFFER CON MATRIZ MODIFICADA
    ; ============================================
    call rebuild_buffer          ; Reconstruir file_buffer desde matrix
    
    ; ============================================
    ; 5.7. LEER Y MOSTRAR RECORRIDO ZIGZAG (PARA DEPURACIÓN)
    ; ============================================
    call zigzag_read_sequence    ; Llenar zigzag_buffer con los bits leídos
    PutStr msg_debug_zigzag      ; Mensaje de depuración

    ; ============================================
    ; 6. CREAR Y ESCRIBIR NUEVO ARCHIVO
    ; ============================================
    ; Crear nuevo archivo de salida
    mov eax, 8                  ; sys_creat
    mov ebx, output_filename    ; Nombre del archivo de salida
    mov ecx, 0644o              ; Permisos: rw-r--r--
    int 0x80
    cmp eax, 0
    js error                    ; Si error, salir
    mov [fd_output], eax        ; Guardar descriptor del archivo de salida
    
    ; Escribir buffer en el nuevo archivo
    mov eax, 4                  ; sys_write
    mov ebx, [fd_output]
    mov ecx, file_buffer
    mov edx, [bytes_read]
    int 0x80
    
    ; Cerrar archivo de salida
    mov eax, 6                  ; sys_close
    mov ebx, [fd_output]
    int 0x80
    
    ; Imprimir mensaje
    PutStr msg_saved
    nwln
    
    ; ============================================
    ; 7. RETORNAR AL MENU
    ; ============================================
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
; MATRIX_TO_LINE
; Convierte la matriz en una línea continua de 0s y 1s
; Entrada: matrix contiene la matriz (625 bytes)
; Salida: matrix_line contiene la línea (625 bytes)
; Nota: En realidad, matrix ya es una línea, pero esta función
;       permite hacer una copia para modificaciones
; ============================================
matrix_to_line:
    pusha
    
    mov esi, matrix             ; Fuente: matrix
    mov edi, matrix_line        ; Destino: matrix_line
    mov ecx, 625                ; 625 bytes a copiar
    rep movsb                   ; Copiar bytes
    
    popa
    ret

; ============================================
; LINE_TO_MATRIX
; Reconstruye la matriz desde la línea modificada
; Entrada: matrix_line contiene la línea modificada (625 bytes)
; Salida: matrix contiene la matriz actualizada (625 bytes)
; ============================================
line_to_matrix:
    pusha
    
    mov esi, matrix_line        ; Fuente: matrix_line
    mov edi, matrix              ; Destino: matrix
    mov ecx, 625                ; 625 bytes a copiar
    rep movsb                   ; Copiar bytes
    
    popa
    ret

; ============================================
; REBUILD_BUFFER
; Reconstruye el buffer del archivo con la matriz modificada
; manteniendo el formato PBM (con espacios y saltos de línea)
; Entrada: matrix contiene la matriz modificada (625 bytes)
;          file_buffer contiene el buffer original
;          header_size contiene el tamaño del encabezado
; Salida: file_buffer contiene el archivo reconstruido
;         bytes_read contiene el nuevo tamaño del buffer
; ============================================
rebuild_buffer:
    pusha
    
    ; Preservar el encabezado (ya está en file_buffer)
    mov esi, matrix             ; ESI apunta a la matriz
    mov edi, file_buffer        ; EDI apunta al buffer
    add edi, [header_size]      ; Saltar el encabezado
    
    xor ecx, ecx                ; ECX = contador de bits procesados
    xor edx, edx                ; EDX = columna actual (0-24)
    
.rebuild_loop:
    cmp ecx, 625                ; ¿Ya procesamos todos los bits?
    jge .rebuild_done
    
    ; Copiar el bit
    lodsb                       ; Cargar bit de matrix en AL
    stosb                       ; Escribir bit en buffer
    
    inc ecx
    inc edx
    
    ; Verificar si necesitamos añadir un espacio o salto de línea
    cmp edx, 25                 ; ¿Fin de fila?
    jl .add_space
    
    ; Fin de fila: añadir salto de línea
    mov byte [edi], 0x0A        ; Newline
    inc edi
    xor edx, edx                ; Reiniciar contador de columna
    jmp .rebuild_loop
    
.add_space:
    ; No es fin de fila: añadir espacio
    mov byte [edi], ' '         ; Espacio
    inc edi
    jmp .rebuild_loop
    
.rebuild_done:
    ; Calcular el nuevo tamaño del buffer
    ; Tamaño = header_size + 625 bits + 24 espacios por fila + 25 newlines
    ; = header_size + 625 + 24*25 + 25 = header_size + 625 + 600 + 25 = header_size + 1250
    mov eax, [header_size]
    add eax, 1250
    mov [bytes_read], eax
    
    popa
    ret

; ============================================
; GET_BIT_FROM_LINE
; Obtiene un bit específico de la línea
; Entrada: EAX = índice (0-624)
; Salida: AL = '0' o '1'
; ============================================
get_bit_from_line:
    push esi
    push ebx
    
    mov esi, matrix_line
    add esi, eax                ; ESI apunta al bit en el índice
    mov al, [esi]               ; Cargar el bit en AL
    
    pop ebx
    pop esi
    ret

; ============================================
; SET_BIT_IN_LINE
; Establece un bit específico en la línea
; Entrada: EAX = índice (0-624), CL = valor ('0' o '1')
; ============================================
set_bit_in_line:
    push edi
    push ebx
    
    mov edi, matrix_line
    add edi, eax                ; EDI apunta al bit en el índice
    mov [edi], cl               ; Escribir el nuevo valor
    
    pop ebx
    pop edi
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
; PRINT_MATRIX_LINE
; Imprime la línea de matriz para depuración
; (imprime los primeros 50 caracteres)
; ============================================
print_matrix_line:
    pusha
    
    mov esi, matrix_line
    mov ecx, 50                 ; Imprimir solo 50 caracteres
    
.print_loop:
    lodsb
    PutCh al
    dec ecx
    jnz .print_loop
    
    nwln
    
    popa
    ret

; ============================================
; PRINT_ZIGZAG_BUFFER
; Imprime el contenido del zigzag_buffer usando PutStr
; ============================================
print_zigzag_buffer:
    pusha
    
    PutStr zigzag_buffer
    nwln
    
    popa
    ret

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





; Cambiar un bit específico
; Entrada: EAX = fila (0-24), EBX = columna (0-24), CL = valor ('0' o '1')
set_bit:
   pusha
  
   ; Calcular offset: fila * 25 + columna
   push edx
   mov edx, 25
   mul edx                     ; EAX = fila * 25
   add eax, ebx                ; EAX = fila * 25 + columna
   pop edx
  
   ; Escribir valor
   mov edi, matrix
   add edi, eax
   mov [edi], cl
  
   popa
   ret

error:
   PutStr msg_error
   nwln
   jmp salir_programa






; ============================================
; ZIGZAG_CORE
; Función core que ejecuta el recorrido zigzag y llama
; a un callback para cada posición (fila, columna)
; 
; Parámetros:
;   EDI -> dirección de la función callback
;          Callback recibe: EAX=fila, EBX=columna
;          Callback debe preservar EDI y variables zigzag_*
; ============================================
zigzag_core:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi                         ; Guardar callback
    
    mov dword [zigzag_col], 24
    mov dword [zigzag_direction], 1
    
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
    
    ; Llamar callback con EAX=fila, EBX=columna
    mov esi, [esp + 4]               ; Recuperar callback desde stack (después del push ecx)
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
    
    ; Cambiar dirección
    xor dword [zigzag_direction], 1
    
    ; Mover 2 columnas a la izquierda
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

; Callback: leer bit y guardar en buffer
; Entrada: EAX=fila, EBX=columna
zigzag_callback_read:
    push eax
    push ebx
    push edi
    
    call get_bit_from_matrix_xy
    
    ; Guardar en buffer
    mov edi, zigzag_buffer
    add edi, [zigzag_idx]
    mov [edi], al
    inc dword [zigzag_idx]
    
    pop edi
    pop ebx
    pop eax
    ret

; Callback: modificar bit a '1' si no es zona fija
; Entrada: EAX=fila, EBX=columna
zigzag_callback_set_ones:
    push eax
    push ebx
    push ecx
    
    call is_fixed_position
    cmp al, 1
    je .skip
    
    ; No es fija, modificar a '1'
    pop ecx
    pop ebx
    pop eax
    push eax
    push ebx
    push ecx
    
    mov cl, '1'
    call set_bit
    
.skip:
    pop ecx
    pop ebx
    pop eax
    ret

; Callback: escribir bits del usuario en orden zigzag
; Entrada: EAX=fila, EBX=columna
; Usa: current_bit_idx para rastrear posición en data_bits
;      data_length para saber cuántos bits escribir
zigzag_callback_write_data:
    push eax
    push ebx
    push ecx
    push esi
    
    ; Verificar si es zona fija
    call is_fixed_position
    cmp al, 1
    je .skip                          ; Si es fija, no modificar
    
    ; Verificar si aún tenemos bits por escribir
    mov esi, [current_bit_idx]
    cmp esi, [data_length]
    jge .write_zero                   ; Si ya terminamos, escribir '0'
    
    ; Obtener el bit del buffer de datos
    push edi
    mov edi, data_bits
    add edi, esi                      ; EDI apunta al bit actual
    mov cl, [edi]                     ; CL = '0' o '1'
    pop edi
    
    ; Incrementar índice para el próximo bit
    inc dword [current_bit_idx]
    
    jmp .write_bit
    
.write_zero:
    ; Escribir '0' si ya no hay más datos
    mov cl, '0'
    
.write_bit:
    ; Guardar el bit a escribir temporalmente
    push ecx                          ; Guardar el bit actual
    
    ; Restaurar registros para set_bit
    pop edx                           ; EDX = bit a escribir (en DL)
    pop esi
    pop ecx                           ; Restaurar ECX original
    pop ebx
    pop eax
    
    ; Preparar para set_bit: EAX=fila, EBX=columna, CL=bit
    mov cl, dl                        ; CL = bit a escribir
    
    ; Escribir el bit en la posición (EAX, EBX)
    call set_bit
    jmp .done
    
.skip:
    pop esi
    pop ecx
    pop ebx
    pop eax
    
.done:
    ret

; ============================================
; ZIGZAG_TRAVERSAL (obsoleta - mantener por compatibilidad)
; ============================================
zigzag_traversal:
    pusha
    
    mov edi, zigzag_callback_read
    call zigzag_core
    
    popa
    ret

; ============================================
; ZIGZAG_READ_SEQUENCE
; Lee la secuencia de bits en orden zigzag y los almacena
; en un buffer lineal
; 
; Salida: zigzag_buffer contendrá los bits en orden de lectura
; ============================================
zigzag_read_sequence:
    push eax
    push edi
    
    mov dword [zigzag_idx], 0
    mov edi, zigzag_callback_read
    call zigzag_core
    
    ; Agregar null terminator
    mov edi, zigzag_buffer
    add edi, [zigzag_idx]
    mov byte [edi], 0
    
    pop edi
    pop eax
    ret

; ============================================
; ZIGZAG_MODIFY_TO_ONES
; Recorre la matriz en zigzag y modifica todos los bits
; modificables a '1' (ignora zonas fijas)
; ============================================
zigzag_modify_to_ones:
    push edi
    
    mov edi, zigzag_callback_set_ones
    call zigzag_core
    
    pop edi
    ret

; ============================================
; ZIGZAG_WRITE_DATA_BITS
; Escribe los bits del usuario en la matriz siguiendo el
; orden zigzag, respetando las zonas fijas del QR
; 
; Entrada: data_bits contiene los bits a escribir ('0' y '1')
;          data_length contiene el número de bits
; Salida: matriz modificada con los bits del usuario
; ============================================
zigzag_write_data_bits:
    push eax
    push edi
    
    ; Inicializar el índice de bits
    mov dword [current_bit_idx], 0
    
    ; Llamar zigzag_core con el callback de escritura
    mov edi, zigzag_callback_write_data
    call zigzag_core
    
    pop edi
    pop eax
    ret
