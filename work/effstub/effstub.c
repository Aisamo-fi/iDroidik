/* Sandcastle: empty AIDL android.hardware.audio.effect.IFactory (V3) so Android 16 audioserver can start.
   No NDK: hand-written libbinder_ndk transactions, linked against libs pulled from the phone. */
typedef struct AIBinder AIBinder; typedef struct AIBinder_Class AIBinder_Class;
typedef struct AParcel AParcel; typedef struct AStatus AStatus;
typedef int binder_status_t; typedef unsigned int transaction_code_t;
typedef void *(*onCreate_t)(void *); typedef void (*onDestroy_t)(void *);
typedef binder_status_t (*onTransact_t)(AIBinder *, transaction_code_t, const AParcel *, AParcel *);
AIBinder_Class *AIBinder_Class_define(const char *, onCreate_t, onDestroy_t, onTransact_t);
AIBinder *AIBinder_new(const AIBinder_Class *, void *);
void AIBinder_markVintfStability(AIBinder *);
int AServiceManager_addService(AIBinder *, const char *);
int ABinderProcess_setThreadPoolMaxThreadCount(unsigned);
void ABinderProcess_joinThreadPool(void);
AStatus *AStatus_newOk(void); AStatus *AStatus_fromExceptionCode(int); void AStatus_delete(AStatus *);
binder_status_t AParcel_writeStatusHeader(AParcel *, const AStatus *);
binder_status_t AParcel_writeInt32(AParcel *, int);
binder_status_t AParcel_writeString(AParcel *, const char *, int);
int __android_log_print(int, const char *, const char *, ...);

#define TAG "sc-effstub"
#define DESC "android.hardware.audio.effect.IFactory"
#define HASH "bfeb16c941085370dc6b68bcd7aec2dbb9435f49"

static void *on_create(void *a) { return a; }
static void on_destroy(void *u) { (void)u; }

static binder_status_t reply(AParcel *out, int exception) {
    AStatus *st = exception ? AStatus_fromExceptionCode(exception) : AStatus_newOk();
    binder_status_t r = AParcel_writeStatusHeader(out, st);
    AStatus_delete(st);
    return r;
}

static binder_status_t on_transact(AIBinder *b, transaction_code_t code, const AParcel *in, AParcel *out) {
    binder_status_t r;
    (void)b; (void)in;
    __android_log_print(4, TAG, "transaction %u", code);
    switch (code) {
    case 1: /* queryEffects -> Descriptor[] */
    case 2: /* queryProcessing -> Processing[] */
        if ((r = reply(out, 0))) return r;
        return AParcel_writeInt32(out, 0);
    case 3: /* createEffect */
    case 4: /* destroyEffect */
        return reply(out, -7 /* EX_UNSUPPORTED_OPERATION */);
    case 0xffffff: /* getInterfaceVersion */
        if ((r = reply(out, 0))) return r;
        return AParcel_writeInt32(out, 3);
    case 0xfffffe: /* getInterfaceHash */
        if ((r = reply(out, 0))) return r;
        return AParcel_writeString(out, HASH, sizeof(HASH) - 1);
    }
    return -74; /* STATUS_UNKNOWN_TRANSACTION */
}

int main(void) {
    AIBinder_Class *cls = AIBinder_Class_define(DESC, on_create, on_destroy, on_transact);
    AIBinder *binder = AIBinder_new(cls, 0);
    AIBinder_markVintfStability(binder);
    int ex = AServiceManager_addService(binder, DESC "/default");
    __android_log_print(ex ? 6 : 4, TAG, "addService " DESC "/default -> %d", ex);
    if (ex) return 1;
    ABinderProcess_setThreadPoolMaxThreadCount(0);
    ABinderProcess_joinThreadPool();
    return 0;
}
