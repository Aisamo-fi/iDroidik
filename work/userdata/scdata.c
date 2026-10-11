/* Sandcastle persistent /data without APFS writes.
 * iOS creates /efs/userdata.img (Android APFS volume) filled with tagged 4K blocks:
 *   "SCUDATA1" | nonce u64 | file_index u64 | total u64 | zeros
 * scan:   read the raw container (read-only), locate every tagged block, require a complete unique map,
 *         then write the extent map into file blocks 0..15 (they belong to our file) and verify.
 * attach: read the map, verify magic/nonce and each extent's guard block (its first block, never mapped),
 *         print dmctl linear targets for the remaining blocks. Nothing outside our file is ever written. */
typedef unsigned long u64; typedef unsigned int u32; typedef long ssize_t; typedef unsigned long size_t;
int open(const char *, int, ...); int close(int);
ssize_t pread64(int, void *, size_t, long); ssize_t pwrite64(int, const void *, size_t, long);
void *malloc(size_t); void *calloc(size_t, size_t); void free(void *);
int memcmp(const void *, const void *, size_t); void *memcpy(void *, const void *, size_t);
int dprintf(int, const char *, ...); unsigned long strtoul(const char *, char **, int);
int fsync(int); void exit(int); int strcmp(const char *, const char *);
void qsort(void *, size_t, size_t, int (*)(const void *, const void *));

#define DEFDEV "/dev/block/nvme0n1p1"
static const char *DEV = DEFDEV;
char *getenv(const char *);
#define BS 4096
#define HDR_BLOCKS 16
#define MAXEXT ((HDR_BLOCKS * BS - 32) / 16)
struct ext { u64 phys; u32 fstart; u32 len; };
struct hit { u64 fidx; u64 phys; };

static void die(const char *m) { dprintf(2, "scdata: %s\n", m); exit(1); }
static u64 rd64(const unsigned char *p) { u64 v = 0; for (int i = 7; i >= 0; i--) v = v << 8 | p[i]; return v; }
static void wr64(unsigned char *p, u64 v) { for (int i = 0; i < 8; i++) { p[i] = v & 0xff; v >>= 8; } }
static int cmphit(const void *a, const void *b) {
    const struct hit *x = a, *y = b; return x->fidx < y->fidx ? -1 : x->fidx > y->fidx; }

static int scan(u64 nonce, u64 devblocks) {
    int fd = open(DEV, 0 /* O_RDONLY */);
    if (fd < 0) die("open ro");
    const size_t CH = 16384;                           /* blocks per read: 64 MiB */
    unsigned char *buf = malloc(CH * BS);
    struct hit *hits = 0; u64 nhits = 0, cap = 0, total = 0;
    for (u64 b = 0; b < devblocks; b += CH) {
        size_t n = devblocks - b < CH ? devblocks - b : CH;
        ssize_t r = pread64(fd, buf, n * BS, (long)(b * BS));
        if (r != (ssize_t)(n * BS)) die("short read");
        for (size_t i = 0; i < n; i++) {
            unsigned char *p = buf + i * BS;
            if (!memcmp(p, "SCUDHDR1", 8) && rd64(p + 8) == nonce) {   /* already initialised: just report it */
                dprintf(1, "%lu\n", b + i); dprintf(2, "existing header at block %lu\n", b + i); return 0; }
            if (memcmp(p, "SCUDATA1", 8) || rd64(p + 8) != nonce) continue;
            u64 t = rd64(p + 24);
            if (!total) total = t;
            if (t != total) die("inconsistent total");
            if (nhits == cap) { cap = cap ? cap * 2 : 1 << 20; struct hit *nh = malloc(cap * sizeof *nh);
                if (!nh) die("oom");
                if (hits) { memcpy(nh, hits, nhits * sizeof *nh); free(hits); } hits = nh; }
            hits[nhits].fidx = rd64(p + 16); hits[nhits].phys = b + i; nhits++;
        }
        if ((b / CH) % 64 == 0) dprintf(2, "scan %lu%%\n", b * 100 / devblocks);
    }
    free(buf);
    dprintf(2, "found %lu tagged blocks, file has %lu\n", nhits, total);
    if (!total || nhits != total) die("incomplete or duplicated map — refusing");
    qsort(hits, nhits, sizeof *hits, cmphit);
    struct ext *ex = calloc(MAXEXT, sizeof *ex); u32 nex = 0;
    for (u64 i = 0; i < nhits; i++) {
        if (hits[i].fidx != i) die("missing/duplicate file index — refusing");
        if (nex && ex[nex-1].phys + ex[nex-1].len == hits[i].phys) { ex[nex-1].len++; continue; }
        if (nex == MAXEXT) die("too fragmented");
        ex[nex].phys = hits[i].phys; ex[nex].fstart = (u32)i; ex[nex].len = 1; nex++;
    }
    if (ex[0].len < HDR_BLOCKS) die("first extent shorter than header area");
    unsigned char *hdr = calloc(HDR_BLOCKS, BS);
    memcpy(hdr, "SCUDHDR1", 8); wr64(hdr + 8, nonce); wr64(hdr + 16, total); wr64(hdr + 24, nex);
    for (u32 i = 0; i < nex; i++) {
        unsigned char *e = hdr + 32 + i * 16;
        wr64(e, ex[i].phys); wr64(e + 8, (u64)ex[i].fstart | (u64)ex[i].len << 32);
    }
    close(fd);
    fd = open(DEV, 2 /* O_RDWR */);
    if (fd < 0) die("open rw");
    long off = (long)(ex[0].phys * BS);
    if (pwrite64(fd, hdr, HDR_BLOCKS * BS, off) != HDR_BLOCKS * BS) die("header write");
    fsync(fd);
    unsigned char *chk = malloc(HDR_BLOCKS * BS);
    if (pread64(fd, chk, HDR_BLOCKS * BS, off) != HDR_BLOCKS * BS || memcmp(chk, hdr, HDR_BLOCKS * BS)) die("header verify");
    close(fd);
    dprintf(1, "%lu\n", ex[0].phys);                  /* header block: pass as androidboot.sc_userdata=<nonce>:<block> */
    dprintf(2, "OK: %u extents, header at block %lu\n", nex, ex[0].phys);
    return 0;
}

/* the same file block read through the APFS driver must match the raw block: proves the file still owns it */
static void same_via_apfs(int ffd, u64 fidx, const unsigned char *raw) {
    unsigned char viafs[BS];
    if (ffd < 0) return;
    if (pread64(ffd, viafs, BS, (long)(fidx * BS)) != BS || memcmp(viafs, raw, BS))
        die("raw block differs from userdata.img via APFS — file deleted or moved, not mounting");
}

static int attach(u64 nonce, u64 hdrblk) {
    int fd = open(DEV, 0);
    if (fd < 0) die("open ro");
    const char *file = getenv("SCDATA_FILE") ? getenv("SCDATA_FILE") : "/efs/userdata.img";
    int ffd = strcmp(file, "none") ? open(file, 0) : -1;
    if (ffd < 0 && strcmp(file, "none")) die("cannot open userdata.img via APFS");
    unsigned char *hdr = malloc(HDR_BLOCKS * BS), blk[BS];
    if (pread64(fd, hdr, HDR_BLOCKS * BS, (long)(hdrblk * BS)) != HDR_BLOCKS * BS) die("header read");
    for (u64 i = 0; i < HDR_BLOCKS; i++) same_via_apfs(ffd, i, hdr + i * BS);
    if (memcmp(hdr, "SCUDHDR1", 8) || rd64(hdr + 8) != nonce) die("header magic/nonce mismatch — not mounting");
    u64 total = rd64(hdr + 16), nex = rd64(hdr + 24), next = 0, sector = 0;
    if (!nex || nex > MAXEXT) die("bad extent count");
    for (u64 i = 0; i < nex; i++) {
        unsigned char *e = hdr + 32 + i * 16;
        u64 phys = rd64(e), fl = rd64(e + 8); u32 fstart = (u32)fl, len = (u32)(fl >> 32);
        if (fstart != next || !len) die("extent map not contiguous");
        if (i == 0) { if (phys != hdrblk || len < HDR_BLOCKS) die("header extent mismatch"); }
        else {
            if (pread64(fd, blk, BS, (long)(phys * BS)) != BS) die("guard read");
            if (memcmp(blk, "SCUDATA1", 8) || rd64(blk + 8) != nonce || rd64(blk + 16) != fstart)
                die("guard block mismatch — file moved? not mounting");
            same_via_apfs(ffd, fstart, blk);
        }
        next += len;
        u64 skip = i == 0 ? HDR_BLOCKS : 1;          /* header area / guard block stay untouched */
        if (len > skip) {
            u64 n = (len - skip) * 8;
            dprintf(1, "linear %lu %lu %s %lu\n", sector, n, DEV, (phys + skip) * 8);
            sector += n;
        }
    }
    if (next != total) die("extent map size mismatch");
    close(fd); if (ffd >= 0) close(ffd);
    return 0;
}

int main(int argc, char **argv) {
    if (getenv("SCDATA_DEV")) DEV = getenv("SCDATA_DEV");
    if (argc == 4 && !strcmp(argv[1], "scan")) return scan(strtoul(argv[2], 0, 16), strtoul(argv[3], 0, 10));
    if (argc == 4 && !strcmp(argv[1], "attach")) return attach(strtoul(argv[2], 0, 16), strtoul(argv[3], 0, 10));
    dprintf(2, "usage: scdata scan <nonce-hex> <device-blocks> | attach <nonce-hex> <header-block>\n");
    return 2;
}
