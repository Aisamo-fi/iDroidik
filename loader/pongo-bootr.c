// Upload a raw image to pongoOS and issue bootr (chainload a newer/older pongo).
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <libusb-1.0/libusb.h>
int main(int argc, char **argv)
{
    if (argc < 2) { fprintf(stderr, "usage: %s image.bin\n", argv[0]); return 1; }
    struct stat st; stat(argv[1], &st);
    FILE *fp = fopen(argv[1], "rb"); if (!fp) { perror("open"); return 1; }
    uint32_t size = st.st_size; unsigned char *buf = malloc(size);
    fread(buf, 1, size, fp); fclose(fp);
    libusb_init(NULL);
    libusb_device_handle *dev = libusb_open_device_with_vid_pid(NULL, 0x05ac, 0x4141);
    if (!dev) { fprintf(stderr, "pongoOS not found\n"); return 1; }
    libusb_set_auto_detach_kernel_driver(dev, 1);
    libusb_claim_interface(dev, 0);
    libusb_control_transfer(dev, 0x21, 2, 0, 0, NULL, 0, 5000);
    libusb_control_transfer(dev, 0x21, 1, 0, 0, (unsigned char *)&size, 4, 5000);
    int sent = 0, r = libusb_bulk_transfer(dev, 2, buf, size, &sent, 20000);
    printf("upload r=%d sent=%d/%u\n", r, sent, size);
    libusb_control_transfer(dev, 0x21, 4, 0, 0, NULL, 0, 5000);
    r = libusb_control_transfer(dev, 0x21, 3, 0, 0, (unsigned char *)"bootr\n", 6, 5000);
    printf("bootr sent r=%d\n", r);
    return 0;
}
