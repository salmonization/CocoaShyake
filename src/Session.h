// One open profile: its libshyake context plus the single serial
// queue every library call runs on (ctx is not thread-safe, and
// libcurl blocks).

#import <Foundation/Foundation.h>

#include "shyake.h"

@class CSProfile;

NS_ASSUME_NONNULL_BEGIN

@interface CSSession : NSObject

@property(readonly) CSProfile *profile;
@property(readonly, getter=isUnlocked) BOOL unlocked;

- (nullable instancetype)initWithProfile:(CSProfile *)profile;

// work runs on the library queue, done on the main queue
- (void)run:(void (^)(shyake_ctx *ctx))work
       then:(nullable dispatch_block_t)done;

// set the passphrase and prove it opens the KEM secret key
- (void)unlockWith:(NSString *)passphrase then:(void (^)(BOOL ok))done;

// generate both key pairs under passphrase ("" = none);
// why is nil on success
- (void)generateKeysWith:(NSString *)passphrase
                    then:(void (^)(NSString *_Nullable why))done;

// release the context; its passphrase is zeroized by libshyake
- (void)close;
// same, but wait for the queue (used at quit)
- (void)closeAndWait;

@end

// the action-first error sentence: "Send failed. <reason>"
NSString *CSFailure(NSString *action, NSString *_Nullable reason);

NS_ASSUME_NONNULL_END
