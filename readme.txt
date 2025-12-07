========================================
Generador de Códigos QR - Versión 2
========================================
Proyecto de Arquitectura de Computadores
Andres Padilla y Marco Sandoval

Objetivo:
Programa que puede leer un texto y convertirlo en un código QR versión 2.

Entrada: texto (máximo 32 caracteres)
Salida: Imagen PBM (qr.pbm)

========================================
COMPILACIÓN Y EJECUCIÓN
========================================
nasm -f elf qr.asm -o qr.o
ld -m elf_i386 -o qr qr.o io.o
./qr

========================================
FUNCIONES PARA MANIPULACIÓN DE MATRIZ
========================================

1. extract_matrix
   - Extrae la matriz 25x25 del archivo PBM (ignora encabezado)
   - Entrada: file_buffer con el contenido del archivo
   - Salida: matrix con 625 bytes (solo 0s y 1s)

2. matrix_to_line
   - Convierte la matriz en una línea modificable
   - Entrada: matrix (625 bytes)
   - Salida: matrix_line (625 bytes) - copia modificable

3. line_to_matrix
   - Reconstruye la matriz desde la línea modificada
   - Entrada: matrix_line (625 bytes modificados)
   - Salida: matrix (625 bytes actualizados)

4. rebuild_buffer
   - Reconstruye el buffer del archivo PBM con formato correcto
   - Entrada: matrix con la matriz modificada
   - Salida: file_buffer reconstruido con espacios y saltos de línea

5. get_bit_from_line
   - Obtiene un bit de la línea por índice (0-624)
   - Entrada: EAX = índice
   - Salida: AL = '0' o '1'

6. set_bit_in_line
   - Modifica un bit en la línea por índice (0-624)
   - Entrada: EAX = índice, CL = valor ('0' o '1')

7. get_bit_from_matrix_xy
   - Obtiene un bit usando coordenadas (fila, columna)
   - Entrada: EAX = fila (0-24), EBX = columna (0-24)
   - Salida: AL = '0' o '1'

8. set_bit
   - Modifica un bit en la matriz usando coordenadas
   - Entrada: EAX = fila (0-24), EBX = columna (0-24), CL = valor ('0' o '1')

========================================
FUNCIONES DE RECORRIDO ZIGZAG
========================================

9. zigzag_core
   - Función core que ejecuta el recorrido zigzag genérico
   - Entrada: EDI = puntero a función callback
   - El callback recibe: EAX=fila, EBX=columna
   - Recorre desde esquina inferior derecha en patrón zigzag

10. zigzag_read_sequence
    - Lee la secuencia de bits en orden zigzag
    - Salida: zigzag_buffer contendrá los bits en orden de lectura (con null terminator)

11. zigzag_modify_to_ones
    - Recorre la matriz en zigzag y modifica bits modificables a '1'
    - Ignora zonas fijas del QR (patrones de posición, timing, format info, etc.)

12. is_fixed_position
    - Verifica si una posición es zona fija del QR
    - Entrada: EAX = fila (0-24), EBX = columna (0-24)
    - Salida: AL = 1 si es zona fija, 0 si es modificable
    - Zonas fijas: patrones de posición, timing patterns, dark module, 
      format information, patrón de alineación

13. print_zigzag_buffer
    - Imprime el contenido del zigzag_buffer
    - Usa PutStr para mostrar la secuencia completa

========================================
FLUJO DE TRABAJO TÍPICO
========================================
1. Leer archivo PBM -> file_buffer
2. extract_matrix -> matrix (625 bytes sin formato)
3. matrix_to_line -> matrix_line (copia para modificar)
4. Modificar usando:
   - set_bit_in_line (modificación por índice), o
   - set_bit (modificación por coordenadas), o
   - zigzag_modify_to_ones (modificación en recorrido zigzag)
5. line_to_matrix -> matrix (aplicar cambios si se usó matrix_line)
6. rebuild_buffer -> file_buffer (reconstruir con formato PBM)
7. Escribir file_buffer al archivo

========================================
CALLBACKS PARA ZIGZAG_CORE
========================================
- zigzag_callback_read: Lee bit y lo guarda en zigzag_buffer
- zigzag_callback_set_ones: Modifica bit a '1' si no es zona fija

Puedes crear callbacks personalizados que reciban EAX=fila, EBX=columna
