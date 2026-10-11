set -e
mk() { so=$1; shift; : > s.c; for f in "$@"; do echo "void $f(void){}" >> s.c; done
  gcc -shared -fPIC -nostdlib -Wl,-soname,$so s.c -o $so; }
mk libbinder_ndk.so AIBinder_Class_define AIBinder_new AIBinder_markVintfStability AServiceManager_addService ABinderProcess_setThreadPoolMaxThreadCount ABinderProcess_joinThreadPool AStatus_newOk AStatus_fromExceptionCode AStatus_delete AParcel_writeStatusHeader AParcel_writeInt32 AParcel_writeString
mk liblog.so __android_log_print
mk libc.so __libc_init
gcc -O2 -fPIE -fno-stack-protector -ffreestanding -nostdinc -c effstub.c -o effstub.o
gcc -c start.S -o start.o
gcc -nostdlib -pie -Wl,-dynamic-linker,/system/bin/linker64 -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 \
  -Wl,--hash-style=gnu -Wl,-z,now -Wl,-z,noexecstack start.o effstub.o libbinder_ndk.so liblog.so libc.so -o effstub
strip effstub
readelf -lhd effstub | grep -E "Type:|LOAD|INTERP|NEEDED|interpreter|FLAGS|TEXTREL"
