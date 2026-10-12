#import "Profile.h"

// Verbatim upstream `shyake init` template, so a profile copied to
// ~/.config/shyake/ is indistinguishable from one the CLI created.
static NSString *const kDefaultConfig =
    @"# shyake global configuration file\n\n"
     "INSTANCE=\n"
     "USERNAME=\n\n"
     "# Date & Time format (strftime format)\n"
     "# RECENT: less than 180 days old.\n"
     "# ISO 8601 format\n"
     "TIME_FORMAT=\"%Y-%m-%d %H:%M\"\n"
     "# POSIX format\n"
     "# TIME_FORMAT=\"%b %d  %Y\"\n"
     "# TIME_FORMAT_RECENT=\"%b %d %H:%M\"\n\n"
     "# Time zone (default: auto)\n"
     "# Integer offset in hours: 0=UTC, 8=UTC+8, -6=UTC-6\n"
     "TIME_ZONE=auto\n\n"
     "# Display columns for `check` command\n"
     "CHECK_COLUMNS=id,sender,subject,size,date\n\n"
     "# Disable colors (1 = disable)\n"
     "# NO_COLOR=0\n\n"
     "# Editor for 'shyake compose' (default: ed)\n"
     "# Falls back to $VISUAL, then $EDITOR\n"
     "# EDITOR=\"ed\"\n\n"
     "# Default action when running without arguments\n"
     "# 0 = man, 1 = check inbox, 2 = check inbox --count\n"
     "DEFAULT_ACTION=0\n";

// key of a `KEY=value` line, nil for comments and blanks
static NSString *config_key(NSString *line)
{
    NSCharacterSet *ws = NSCharacterSet.whitespaceCharacterSet;
    NSString *t = [line stringByTrimmingCharactersInSet:ws];
    if (t.length == 0 || [t hasPrefix:@"#"])
        return nil;
    NSRange eq = [t rangeOfString:@"="];
    if (eq.location == NSNotFound)
        return nil;
    return
        [[t substringToIndex:eq.location] stringByTrimmingCharactersInSet:ws];
}

@implementation CSProfile

+ (NSString *)rootPath
{
    NSString *support =
        NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                            NSUserDomainMask, YES)
            .firstObject;
    return [support stringByAppendingPathComponent:@"CocoaShyake/profiles"];
}

// The CLI resolves its directory as $HOME/.config/shyake; so do we,
// and use it in place: one account, two clients, no copy to drift.
+ (NSString *)cliPath
{
    return [NSHomeDirectory() stringByAppendingPathComponent:@".config/shyake"];
}

+ (NSArray<CSProfile *> *)all
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<CSProfile *> *out = [NSMutableArray array];
    BOOL dir = NO;
    if ([fm fileExistsAtPath:self.cliPath isDirectory:&dir] && dir)
        [out addObject:[[CSProfile alloc] initWithPath:self.cliPath
                                                  name:@"~/.config/shyake"]];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *n in [fm contentsOfDirectoryAtPath:self.rootPath
                                                error:NULL]) {
        NSString *p = [self.rootPath stringByAppendingPathComponent:n];
        if ([self isValidName:n] && [fm fileExistsAtPath:p isDirectory:&dir] &&
            dir)
            [names addObject:n];
    }
    [names sortUsingSelector:@selector(localizedStandardCompare:)];
    for (NSString *n in names)
        [out addObject:[[CSProfile alloc]
                           initWithPath:[self.rootPath
                                            stringByAppendingPathComponent:n]
                                   name:n]];
    return out;
}

// Same alphabet as NTShyake: the name is a directory name that must
// survive copying between Windows, macOS and Unix unchanged.
+ (BOOL)isValidName:(NSString *)name
{
    if (name.length == 0 || name.length >= 64)
        return NO;
    NSCharacterSet *bad = [[NSCharacterSet
        characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz"
                                            "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                                            "0123456789-_"] invertedSet];
    return [name rangeOfCharacterFromSet:bad].location == NSNotFound;
}

+ (BOOL)existsNamed:(NSString *)name
{
    NSString *p = [self.rootPath stringByAppendingPathComponent:name];
    return [NSFileManager.defaultManager fileExistsAtPath:p];
}

+ (CSProfile *)createNamed:(NSString *)name
{
    if (![self isValidName:name] || [self existsNamed:name])
        return nil;
    CSProfile *p = [[CSProfile alloc]
        initWithPath:[self.rootPath stringByAppendingPathComponent:name]
                name:name];
    // 0700 applies to the intermediate directories too: the keys
    // directory tree is private, as ~/.config/shyake is upstream
    if (![NSFileManager.defaultManager
                  createDirectoryAtPath:p.path
            withIntermediateDirectories:YES
                             attributes:@{NSFilePosixPermissions : @0700}
                                  error:NULL])
        return nil;
    NSString *cfg = [p.path stringByAppendingPathComponent:@"config"];
    if (![kDefaultConfig writeToFile:cfg
                          atomically:YES
                            encoding:NSUTF8StringEncoding
                               error:NULL])
        return nil;
    return p;
}

- (instancetype)initWithPath:(NSString *)path name:(NSString *)name
{
    self = [super init];
    if (self) {
        _name = [name copy];
        _path = [path copy];
    }
    return self;
}

// a profile is its directory; two objects for one path are one profile
- (BOOL)isEqual:(id)other
{
    return [other isKindOfClass:CSProfile.class] &&
           [((CSProfile *)other).path isEqualToString:_path];
}

- (NSUInteger)hash
{
    return _path.hash;
}

- (NSString *)configFile
{
    return [self.path stringByAppendingPathComponent:@"config"];
}

- (NSString *)configValue:(NSString *)key
{
    NSString *text = [NSString stringWithContentsOfFile:self.configFile
                                               encoding:NSUTF8StringEncoding
                                                  error:NULL];
    NSString *found = nil;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (![config_key(line) isEqualToString:key])
            continue;
        NSRange eq = [line rangeOfString:@"="];
        NSString *v = [[line substringFromIndex:eq.location + 1]
            stringByTrimmingCharactersInSet:NSCharacterSet
                                                .whitespaceCharacterSet];
        if (v.length >= 2 && [v hasPrefix:@"\""] && [v hasSuffix:@"\""])
            v = [v substringWithRange:NSMakeRange(1, v.length - 2)];
        found = v; // last assignment wins, like a shell
    }
    return found.length ? found : nil;
}

// Mirrors update_config_user_and_instance() in the upstream CLI: the
// INSTANCE line becomes the INSTANCE/USERNAME pair, stray USERNAME
// lines go, and every other line (comments, CLI-only keys) survives.
- (BOOL)setInstance:(NSString *)instance username:(NSString *)username
{
    NSString *text = [NSString stringWithContentsOfFile:self.configFile
                                               encoding:NSUTF8StringEncoding
                                                  error:NULL]
                         ?: @"";
    NSString *pair = [NSString
        stringWithFormat:@"INSTANCE=%@\nUSERNAME=%@", instance, username];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    BOOL placed = NO;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSString *key = config_key(line);
        if ([key isEqualToString:@"INSTANCE"]) {
            if (!placed)
                [out addObject:pair];
            placed = YES;
        } else if (![key isEqualToString:@"USERNAME"]) {
            [out addObject:line];
        }
    }
    if (!placed)
        [out insertObject:pair atIndex:0];
    return
        [[out componentsJoinedByString:@"\n"] writeToFile:self.configFile
                                               atomically:YES
                                                 encoding:NSUTF8StringEncoding
                                                    error:NULL];
}

- (BOOL)hasKeys
{
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *f in @[ @"kem_sk.bin", @"sig_sk.bin" ])
        if (![fm fileExistsAtPath:[self.path stringByAppendingPathComponent:f]])
            return NO;
    return YES;
}

// "SHYK" magic marks a passphrase-encrypted key (SPEC §3.7)
- (BOOL)keysEncrypted
{
    NSFileHandle *fh = [NSFileHandle
        fileHandleForReadingAtPath:
            [self.path stringByAppendingPathComponent:@"kem_sk.bin"]];
    NSData *magic = [fh readDataOfLength:4];
    [fh closeFile];
    return
        [magic isEqualToData:[@"SHYK" dataUsingEncoding:NSASCIIStringEncoding]];
}

// Domain is everything between "://" and the first "/", port
// included: the same string libshyake puts in a federated sender.
- (NSString *)identity
{
    NSString *user = [self configValue:@"USERNAME"];
    NSString *inst = [self configValue:@"INSTANCE"];
    if (!user || !inst)
        return nil;
    NSRange scheme = [inst rangeOfString:@"://"];
    NSString *d = scheme.location == NSNotFound
                      ? inst
                      : [inst substringFromIndex:NSMaxRange(scheme)];
    NSRange slash = [d rangeOfString:@"/"];
    if (slash.location != NSNotFound)
        d = [d substringToIndex:slash.location];
    return [NSString stringWithFormat:@"%@@%@", user, d];
}

@end
