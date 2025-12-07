;Proyecto escaner QR de Arquitectura de Computadores
;Andres Padilla y Marco Sandoval

;Objetivo:
;Programa que puede leer un texto y convertirlo en
;un codigo QR version 2.

;Entrada: texto

;Salida: Imagen pbm

;==== FUNCIONES PARA MANIPULACIÓN DE MATRIZ ====
;
; 1. extract_matrix
;    - Extrae la matriz 25x25 del archivo PBM (ignora encabezado)
;    - Entrada: file_buffer con el contenido del archivo
;    - Salida: matrix con 625 bytes (solo 0s y 1s)
;
; 2. matrix_to_line
;    - Convierte la matriz en una línea modificable
;    - Entrada: matrix (625 bytes)
;    - Salida: matrix_line (625 bytes) - copia modificable
;
; 3. line_to_matrix
;    - Reconstruye la matriz desde la línea modificada
;    - Entrada: matrix_line (625 bytes modificados)
;    - Salida: matrix (625 bytes actualizados)
;
; 4. rebuild_buffer
;    - Reconstruye el buffer del archivo PBM con formato correcto
;    - Entrada: matrix con la matriz modificada
;    - Salida: file_buffer reconstruido con espacios y saltos de línea
;
; 5. get_bit_from_line
;    - Obtiene un bit de la línea por índice (0-624)
;    - Entrada: EAX = índice
;    - Salida: AL = '0' o '1'
;
; 6. set_bit_in_line
;    - Modifica un bit en la línea por índice (0-624)
;    - Entrada: EAX = índice, CL = valor ('0' o '1')
;
; 7. get_bit_from_matrix_xy
;    - Obtiene un bit usando coordenadas (fila, columna)
;    - Entrada: EAX = fila (0-24), EBX = columna (0-24)
;    - Salida: AL = '0' o '1'
;
; FLUJO DE TRABAJO:
; 1. Leer archivo PBM -> file_buffer
; 2. extract_matrix -> matrix (625 bytes sin formato)
; 3. matrix_to_line -> matrix_line (copia para modificar)
; 4. Modificar matrix_line usando set_bit_in_line o directamente
; 5. line_to_matrix -> matrix (aplicar cambios)
; 6. rebuild_buffer -> file_buffer (reconstruir con formato PBM)
; 7. Escribir file_buffer al archivo
;
;================================================

%include "io.mac"

.DATA

filename             db "qr.pbm",0

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

msg_salida_archivo   db "El codigo QR ha sido generado",0Ah,0


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
bytes_read           resd 1         ; Bytes leídos

data_bits            resb 512       ; Bits de datos + mode + count indicators
data_length          resd 1         ; Cantidad total de bits (incluyendo mode y count)
current_bit_idx      resd 1         ; Índice actual en data_bits
text_char_count      resd 1         ; Número de caracteres del texto


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
    mov eax, 100                ; índice en la línea
    mov cl, '1'                 ; nuevo valor
    call set_bit_in_line
    
    ; Ejemplo 2: Cambiar bit en índice 200 a '0'
    mov eax, 200
    mov cl, '0'
    call set_bit_in_line
    
    ; Ejemplo 3: Modificar usando coordenadas [13, 15]
    ; Primero calcular índice: 13 * 25 + 15 = 340
    mov eax, 13                 ; fila
    mov ebx, 25
    mul ebx                     ; EAX = 13 * 25 = 325
    add eax, 15                 ; EAX = 340
    mov cl, '1'
    call set_bit_in_line
    
    ; ============================================
    ; 6. RECONSTRUIR MATRIZ DESDE LÍNEA MODIFICADA
    ; ============================================
    call line_to_matrix

   ; ============================================
    ; 5. RECONSTRUIR BUFFER CON MATRIZ MODIFICADA
    ; ============================================
    call rebuild_buffer
    
    ; ============================================
    ; 6. SOBREESCRIBIR ARCHIVO
    ; ============================================
    ; Volver al inicio del archivo
    mov eax, 19                 ; sys_lseek
    mov ebx, [fd]
    xor ecx, ecx                ; offset 0
    xor edx, edx                ; SEEK_SET
    int 0x80
    
    ; Escribir buffer modificado
    mov eax, 4                  ; sys_write
    mov ebx, [fd]
    mov ecx, file_buffer
    mov edx, [bytes_read]
    int 0x80
    
    ; Cerrar archivo
    mov eax, 6                  ; sys_close
    mov ebx, [fd]
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

