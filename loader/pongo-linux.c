// Sandcastle kernel uploader for modern pongoOS (2.x, as shipped in palera1n).
// Differences from Corellium's load-linux.c:
//  - announces the upload size (bRequest 1, wLength 4) so pongo grows its USB buffer;
//  - sets linux_cmdline explicitly, because new pongo overwrites the dtbpack bootargs
//    with gLinuxCmdLine (empty by default), which leaves the kernel hanging.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <libusb-1.0/libusb.h>

#define DEFAULT_CMDLINE "earlycon=hx_uart,0x20a0c0000 console=tty0 console=ttyHX0 selinux=1 enforcing=0 " \
                        "androidboot.selinux=permissive printk.devkmsg=on androidboot.hardware=ranchu"

static libusb_device_handle *dev;

static unsigned char *slurp(const char *path, uint32_t *size)
{
    struct stat st;
    if (stat(path, &st)) { perror(path); exit(1); }
    FILE *fp = fopen(path, "rb");
    if (!fp) { perror(path); exit(1); }
    unsigned char *buf = malloc(st.st_size);
    if (fread(buf, 1, st.st_size, fp) != (size_t)st.st_size) { fprintf(stderr, "short read %s\n", path); exit(1); }
    fclose(fp);
    *size = (uint32_t)st.st_size;
    return buf;
}

static int ctrl(uint8_t req, uint16_t val, unsigned char *data, uint16_t len)
{
    int r = libusb_control_transfer(dev, 0x21, req, val, 0, data, len, 5000);
    if (r < 0) fprintf(stderr, "ctrl %u failed: %s\n", req, libusb_error_name(r));
    return r;
}

static int command(const char *cmd)
{
    printf("> %s", cmd);
    if (ctrl(4, 0, NULL, 0) < 0) return -1;
    return ctrl(3, 0, (unsigned char *)cmd, (uint16_t)strlen(cmd));
}

static int upload(unsigned char *buf, uint32_t size, int announce)
{
    if (ctrl(2, 0, NULL, 0) < 0) return -1;
    if (announce) {
        if (ctrl(1, 0, (unsigned char *)&size, 4) < 0) return -1;
    } else if (ctrl(1, 0, NULL, 0) < 0) return -1;

    uint32_t done = 0;
    int stalls = 0;
    while (done < size) {
        int chunk = size - done > 1048576 ? 1048576 : (int)(size - done), sent = 0;
        int r = libusb_bulk_transfer(dev, 2, buf + done, chunk, &sent, 20000);
        if (r == LIBUSB_ERROR_PIPE && ++stalls < 5) { libusb_clear_halt(dev, 2); continue; }
        if (r < 0) { fprintf(stderr, "bulk failed at %u/%u: %s\n", done, size, libusb_error_name(r)); return -1; }
        done += sent;
    }
    printf("uploaded %u bytes\n", done);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr, "usage: %s kernel.lzma dtbpack [cmdline]\n", argv[0]);
        return 1;
    }
    const char *cmdline = argc > 3 ? argv[3] : DEFAULT_CMDLINE;
    uint32_t ksize, dsize;
    unsigned char *kernel = slurp(argv[1], &ksize);
    unsigned char *dtb = slurp(argv[2], &dsize);

    libusb_init(NULL);
    for (int i = 0; i < 60 && !(dev = libusb_open_device_with_vid_pid(NULL, 0x05ac, 0x4141)); i++) {
        if (!i) printf("waiting for pongoOS...\n");
        sleep(1);
    }
    if (!dev) { fprintf(stderr, "pongoOS device not found\n"); return 1; }
    libusb_set_auto_detach_kernel_driver(dev, 1);
    libusb_claim_interface(dev, 0);

    char buf[1024];
    snprintf(buf, sizeof(buf), "linux_cmdline %s\n", cmdline);
    if (command(buf) < 0) return 1;

    const char *initrd = getenv("INITRD");
    if (initrd) {
        uint32_t rsize;
        unsigned char *rd = slurp(initrd, &rsize);
        if (upload(rd, rsize, 1) < 0 || command("ramdisk\n") < 0) return 1;
    }

    if (upload(dtb, dsize, 0) < 0 || command("fdt\n") < 0) return 1;
    if (upload(kernel, ksize, 1) < 0) return 1;

    if (ctrl(4, 0, NULL, 0) < 0) return 1;
    printf("> bootl\n");
    libusb_control_transfer(dev, 0x21, 3, 0, 0, (unsigned char *)"bootl\n", 6, 5000);
    printf("boot command sent\n");
    return 0;
}
