set -e
mk() { so=$1; shift; : > s.c; for f in "$@"; do echo "void $f(void){}" >> s.c; done; gcc -w -shared -fPIC -nostdlib -Wl,-soname,$so s.c -o $so; }
mk libc.so __libc_init open close pread64 pwrite64 malloc calloc free memcmp memcpy dprintf strtoul fsync exit strcmp qsort getenv
gcc -O2 -fPIE -fno-stack-protector -ffreestanding -nostdinc -fno-builtin -Wall -Wno-builtin-declaration-mismatch -c scdata.c -o scdata.o
gcc -c start.S -o start.o
gcc -nostdlib -pie -Wl,-dynamic-linker,/system/bin/linker64 -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 \
  -Wl,--hash-style=gnu -Wl,-z,now -Wl,-z,noexecstack start.o scdata.o libc.so -o scdata
strip scdata
