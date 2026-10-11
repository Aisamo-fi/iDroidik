#!/bin/sh

CHECKRA1N=/Applications/checkra1n.app/Contents/MacOS/checkra1n
export DYLD_LIBRARY_PATH=./

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"
export CHECKRA1N_LOG_PATH=$PWD/out.log
rm -rf "$CHECKRA1N_LOG_PATH"

killall -9 checkra1n > /dev/null 2>&1

BOOT=0
FOUND=0
if [ ! -f ${CHECKRA1N} ]; then 
	echo "Checkra1n not found at : ${CHECKRA1N}"
	exit 1
fi
${CHECKRA1N} -cp > /dev/null 2>&1 &
disown
echo "Please put your device into DFU"
sleep 1;
while true; do
    grep "Booting..." ${CHECKRA1N_LOG_PATH} > /dev/null 2>&1
    if [ $? -eq 0 ]; then
	BOOT=1
	echo "Pongo loaded. Give it a second"
	sleep 2;
	break
    fi
    grep "DFU mode device found" ${CHECKRA1N_LOG_PATH} > /dev/null 2>&1
    if [ $? -eq 0 ] && [ ${FOUND} -eq 0 ]; then
        echo "Found DFU device. Starting"
	FOUND=1
    fi
    sleep 1
done
if [ ${BOOT} -eq 1 ]; then
	sleep 5;
	echo "Starting Android"
	./load-linux.mac Android.lzma dtbpack
fi
killall -9 checkra1n
