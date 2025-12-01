;Proyecto escaner QR de Arquitectura de Computadores
;Andres Padilla y Marco Sandoval

;Objetivo:
;Programa que puede leer un texto y convertirlo en
;un codigo QR version 2.

;Entrada: texto

;Salida: Imagen pbm

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
texto_usuario        resb 33         ; Buffer para el texto del usuario (32 + null terminator)
opcion_menu          resb 1          ; Opcion del menu

; ==== Variables internas ====
file_buffer          resb 1024      ; Buffer para todo el archivo
matrix               resb 625       ; 25x25 matriz sin saltos de línea
fd                   resd 1         ; File descriptor
bytes_read           resd 1         ; Bytes leídos

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
   jmp menu                ; Opcion invalida, volver al menu


iniciar_generador:
   ; Solicitar texto
   PutStr msg_ingreso_texto
   GetStr texto_usuario, 33
   nwln
  
   ; Aquí iría la lógica de generación del QR
   ; Por ahora, solo cargamos y modificamos el archivo existente
   call procesar_qr
  
   ; Mostrar mensaje de exito
   PutStr msg_salida_archivo
   nwln
  
   jmp menu          

salir_programa:
   .EXIT

procesar_qr:
   ;Proceso para abrir nuestro archivo
    mov eax, 5          ; sys_open
    mov ebx, filename   ; Nombre del archivo
    mov ecx, 2          ; Modo: Leer y escribir
    int 0x80            ; Se llama a la interrupción
    cmp eax, 0          ; El resultado fue guardado en EAX: si este dió 0, hubo un error
    js  error           ; Si error, salir
    mov [fd], eax       ; Guardar descriptor del archivo en fd
   ; ============================================
   ; 2. LEER ARCHIVO COMPLETO
   ; ============================================
    mov eax, 3               ; sys_read
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
    ; 4. MODIFICAR LA MATRIZ
    ; ============================================
    ; Ejemplo 1: Cambiar posición [10, 10] a '1'
    mov eax, 13              ; fila
    mov ebx, 15              ; columna
    mov cl, '1'              ; nuevo valor
    call set_bit

   ; ============================================
    ; 5. RECONSTRUIR BUFFER CON MATRIZ MODIFICADA
    ; ============================================
    call rebuild_buffer
    
    ; ============================================
    ; 6. SOBREESCRIBIR ARCHIVO
    ; ============================================
    ; Volver al inicio del archivo
    mov eax, 19              ; sys_lseek
    mov ebx, [fd]
    xor ecx, ecx             ; offset 0
    xor edx, edx             ; SEEK_SET
    int 0x80
    
    ; Escribir buffer modificado
    mov eax, 4               ; sys_write
    mov ebx, [fd]
    mov ecx, file_buffer
    mov edx, [bytes_read]
    int 0x80
    
    ; Cerrar archivo
    mov eax, 6               ; sys_close
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


; Extraer matriz del buffer (ignorar header PBM)
extract_matrix:
    pusha
    mov esi, file_buffer
    mov edi, matrix
    
    ; Saltar "P1\n"
    add esi, 3
    
    ; Saltar dimensiones "25 25\n"
    .skip_dimensions:
        lodsb
        cmp al, 10               ; newline
        jne .skip_dimensions
    
    ; Copiar matriz eliminando saltos de línea
    xor ecx, ecx                 ; contador
    .copy_loop:
        lodsb
        cmp al, 10               ; si es newline, ignorar
        je .skip_newline
        cmp al, 0                ; fin de buffer
        je .done
        
        mov [edi], al
        inc edi
        inc ecx
        
        cmp ecx, 625             ; 25x25
        jge .done
        jmp .copy_loop
        
    .skip_newline:
        jmp .copy_loop
        
    .done:
        popa
        ret


; Reconstruir buffer con matriz modificada
rebuild_buffer:
    pusha
    mov esi, file_buffer
    mov edi, matrix
    
    ; Saltar header hasta después de dimensiones
    add esi, 3                   ; "P1\n"
    .skip_dims:
        lodsb
        cmp al, 10
        jne .skip_dims
    
    ; Ahora ESI apunta al inicio de la matriz en file_buffer
    ; Reconstruir con saltos de línea
    xor ecx, ecx                 ; contador de columna
    xor edx, edx                 ; contador total
    
    .rebuild_loop:
        cmp edx, 625
        jge .done
        
        mov al, [edi]            ; obtener bit de matrix
        mov [esi], al            ; escribir en file_buffer
        inc esi
        inc edi
        inc ecx
        inc edx
        
        ; Cada 25 caracteres, agregar newline
        cmp ecx, 25
        jne .rebuild_loop
        
        mov byte [esi], 10       ; agregar newline
        inc esi
        xor ecx, ecx             ; reset contador columna
        jmp .rebuild_loop
        
    .done:
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

