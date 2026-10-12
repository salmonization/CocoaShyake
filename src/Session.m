// memset_s is C11 Annex K; it must be requested before string.h
#define __STDC_WANT_LIB_EXT1__ 1
#include <stdlib.h>
#include <string.h>

#import "Profile.h"
#import "Session.h"

static dispatch_queue_t lib_queue(void)
{
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("shyake.lib", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

// Copy a secret into our own malloc buffer. Going through UTF8String
// would leave a second, autoreleased copy we could never zero.
static char *secret_dup(NSString *s)
{
    NSUInteger max =
        [s maximumLengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 1;
    char *buf = calloc(1, max);
    if (buf && ![s getCString:buf
                    maxLength:max
                     encoding:NSUTF8StringEncoding]) {
        free(buf);
        buf = NULL;
    }
    return buf;
}

static void secret_free(char *buf)
{
    if (!buf)
        return;
    size_t n = strlen(buf);
    memset_s(buf, n, 0, n);
    free(buf);
}

NSString *CSFailure(NSString *action, NSString *reason)
{
    return reason.length ? [NSString stringWithFormat:@"%@ %@", action, reason]
                         : action;
}

@implementation CSSession {
    shyake_ctx *_ctx;
}

- (instancetype)initWithProfile:(CSProfile *)profile
{
    self = [super init];
    if (!self)
        return nil;
    _profile = profile;
    // init_ctx strdup()s every string, so the transient C strings
    // from these NSStrings may die right after the call
    shyake_config cfg = {
        .config_dir = profile.path.fileSystemRepresentation,
        .instance_url = [profile configValue:@"INSTANCE"].UTF8String,
        .username = [profile configValue:@"USERNAME"].UTF8String,
    };
    _ctx = shyake_init_ctx(&cfg);
    if (!_ctx)
        return nil;
    _unlocked = profile.hasKeys && !profile.keysEncrypted;
    return self;
}

- (void)dealloc
{
    [self close];
}

- (void)run:(void (^)(shyake_ctx *ctx))work then:(dispatch_block_t)done
{
    shyake_ctx *ctx = _ctx;
    if (!ctx)
        return;
    dispatch_async(lib_queue(), ^{
        work(ctx);
        if (done)
            dispatch_async(dispatch_get_main_queue(), done);
    });
}

- (void)unlockWith:(NSString *)passphrase then:(void (^)(BOOL ok))done
{
    char *pass = _ctx ? secret_dup(passphrase) : NULL;
    if (!pass) {
        done(NO);
        return;
    }
    __block BOOL ok = NO;
    [self
        run:^(shyake_ctx *ctx) {
            shyake_set_passphrase(ctx, pass);
            secret_free(pass);
            // loading the KEM secret key is the cheapest call that
            // fails exactly when the passphrase is wrong
            shyake_selfdec *sd = shyake_selfdec_new(ctx);
            ok = sd != NULL;
            shyake_selfdec_free(sd);
            if (!ok)
                shyake_set_passphrase(ctx, "");
        }
        then:^{
            self->_unlocked = ok;
            done(ok);
        }];
}

- (void)generateKeysWith:(NSString *)passphrase
                    then:(void (^)(NSString *why))done
{
    char *pass = _ctx ? secret_dup(passphrase) : NULL;
    if (!pass) {
        done(@"");
        return;
    }
    __block NSString *why = nil;
    [self
        run:^(shyake_ctx *ctx) {
            shyake_set_passphrase(ctx, pass);
            secret_free(pass);
            if (shyake_generate_keys(ctx) != 0)
                why = @(shyake_last_error(ctx));
        }
        then:^{
            self->_unlocked = why == nil;
            done(why);
        }];
}

- (void)close
{
    shyake_ctx *ctx = _ctx;
    _ctx = NULL;
    _unlocked = NO;
    // queued behind any running call, so nothing frees ctx under it
    if (ctx)
        dispatch_async(lib_queue(), ^{
            shyake_free_ctx(ctx);
        });
}

- (void)closeAndWait
{
    [self close];
    dispatch_sync(lib_queue(), ^{
                  });
}

@end
