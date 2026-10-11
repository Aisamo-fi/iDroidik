// Probe which setsockopt calls the Sandcastle kernel rejects under Android 16.
#include <errno.h>
#include <linux/netlink.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>

static void try_int(const char *what, int fd, int level, int opt, int val) {
    int r = setsockopt(fd, level, opt, &val, sizeof(val));
    printf("%-40s -> %s\n", what, r == 0 ? "OK" : strerror(errno));
}
static void try_tv(const char *what, int fd, int opt) {
    struct timeval tv = { .tv_sec = 1, .tv_usec = 0 };
    int r = setsockopt(fd, SOL_SOCKET, opt, &tv, sizeof(tv));
    printf("%-40s -> %s\n", what, r == 0 ? "OK" : strerror(errno));
}
int main(void) {
    int nl = socket(AF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC, NETLINK_KOBJECT_UEVENT);
    printf("netlink uevent socket fd=%d %s\n", nl, nl < 0 ? strerror(errno) : "");
    if (nl >= 0) {
        try_int("netlink SO_RCVBUF 64k", nl, SOL_SOCKET, SO_RCVBUF, 64 * 1024);
        try_int("netlink SO_RCVBUFFORCE 64k", nl, SOL_SOCKET, SO_RCVBUFFORCE, 64 * 1024);
        try_int("netlink SO_PASSCRED 1", nl, SOL_SOCKET, SO_PASSCRED, 1);
    }
    int un = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
    printf("unix seqpacket fd=%d\n", un);
    try_int("unix SO_SNDBUF 64k", un, SOL_SOCKET, SO_SNDBUF, 64 * 1024);
    try_tv("unix SO_SNDTIMEO (20/21 old)", un, SO_SNDTIMEO);
    try_tv("unix SO_RCVTIMEO (old)", un, SO_RCVTIMEO);
    try_tv("unix SO_SNDTIMEO_NEW (67)", un, 67);
    try_tv("unix SO_RCVTIMEO_NEW (66)", un, 66);
    int in = socket(AF_INET, SOCK_DGRAM, 0);
    try_int("inet SO_RCVBUF 64k", in, SOL_SOCKET, SO_RCVBUF, 64 * 1024);
    return 0;
}
