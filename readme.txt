nasm -f elf qr.asm -o qr.o
ld -m elf_i386 -o qr qr.o io.o
./qr