// Minimal pongoOS USB console: prints pending stdout, optionally runs one command.
// usage: pongo-shell ["command"]
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <libusb-1.0/libusb.h>

static void drain(libusb_device_handle *dev)
{
    unsigned char buf[0x1000];
    int r;
    while ((r = libusb_control_transfer(dev, 0xa1, 1, 0, 0, buf, sizeof(buf), 2000)) > 0) {
        fwrite(buf, 1, r, stdout);
        if (r < (int)sizeof(buf)) break;
    }
    fflush(stdout);
}

int main(int argc, char **argv)
{
    libusb_init(NULL);
    libusb_device_handle *dev = libusb_open_device_with_vid_pid(NULL, 0x05ac, 0x4141);
    if (!dev) { fprintf(stderr, "pongoOS not found\n"); return 1; }
    libusb_set_auto_detach_kernel_driver(dev, 1);
    libusb_claim_interface(dev, 0);
    drain(dev);
    if (argc > 1) {
        char cmd[512];
        snprintf(cmd, sizeof(cmd), "%s\n", argv[1]);
        libusb_control_transfer(dev, 0x21, 4, 1, 0, NULL, 0, 2000);
        libusb_control_transfer(dev, 0x21, 3, 0, 0, (unsigned char *)cmd, strlen(cmd), 2000);
        for (int i = 0; i < 20; i++) {
            unsigned char inprog = 1;
            if (libusb_control_transfer(dev, 0xa1, 2, 0, 0, &inprog, 1, 2000) < 0 || !inprog) break;
            usleep(250000);
        }
        drain(dev);
    }
    return 0;
}
