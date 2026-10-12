// Profile store. The CLI's ~/.config/shyake is a profile used in
// place; new ones live under Application Support. Every profile
// directory is byte-compatible with upstream ~/.config/shyake/.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CSProfile : NSObject

// display name: the directory name, or "~/.config/shyake"
@property(readonly, copy) NSString *name;
@property(readonly, copy) NSString *path;

// where profiles created by this app live
+ (NSString *)rootPath;
// the upstream CLI's own profile, used in place
+ (NSString *)cliPath;
// the CLI profile (when it exists) first, then ours by name
+ (NSArray<CSProfile *> *)all;
+ (BOOL)isValidName:(NSString *)name;
+ (BOOL)existsNamed:(NSString *)name;
// new directory (0700) seeded with the CLI's config template
+ (nullable CSProfile *)createNamed:(NSString *)name;

- (instancetype)initWithPath:(NSString *)path name:(NSString *)name;

// value of a config key, nil when absent or empty
- (nullable NSString *)configValue:(NSString *)key;
// rewrite INSTANCE/USERNAME the way the CLI does, other lines kept
- (BOOL)setInstance:(NSString *)instance username:(NSString *)username;

- (BOOL)hasKeys;
- (BOOL)keysEncrypted;
// user@domain, nil before registration
- (nullable NSString *)identity;

@end

NS_ASSUME_NONNULL_END
