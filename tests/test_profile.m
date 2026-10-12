// Headless checks for the profile store and session locking.
// Run through `make test`, which points CFFIXED_USER_HOME at a temp
// directory so nothing touches the real Application Support.

#import <Foundation/Foundation.h>
#include <sys/stat.h>

#import "Profile.h"
#import "Session.h"

static int failures;

#define CHECK(cond)                                                            \
    do {                                                                       \
        if (!(cond)) {                                                         \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);    \
            failures++;                                                        \
        }                                                                      \
    } while (0)

// session callbacks land on the main queue; pump it until done
static void wait_for(BOOL *done)
{
    while (!*done)
        [NSRunLoop.mainRunLoop
               runMode:NSDefaultRunLoopMode
            beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

static NSUInteger count_lines(CSProfile *p, NSString *prefix)
{
    NSString *text = [NSString
        stringWithContentsOfFile:[p.path stringByAppendingPathComponent:@"config"]
                        encoding:NSUTF8StringEncoding
                           error:NULL];
    NSUInteger n = 0;
    for (NSString *l in [text componentsSeparatedByString:@"\n"])
        if ([l hasPrefix:prefix])
            n++;
    return n;
}

static void test_store(void)
{
    CHECK([CSProfile isValidName:@"default"]);
    CHECK([CSProfile isValidName:@"work-2_b"]);
    CHECK(![CSProfile isValidName:@""]);
    CHECK(![CSProfile isValidName:@"a b"]);
    CHECK(![CSProfile isValidName:@"../x"]);

    CSProfile *p = [CSProfile createNamed:@"t"];
    CHECK(p != nil);
    CHECK(![CSProfile createNamed:@"t"]);
    CHECK([CSProfile.all containsObject:p]);

    // the CLI's directory is listed first, in place, under its own name
    CHECK(![CSProfile.all.firstObject.path isEqualToString:CSProfile.cliPath]);
    [NSFileManager.defaultManager createDirectoryAtPath:CSProfile.cliPath
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
    CSProfile *cli = CSProfile.all.firstObject;
    CHECK([cli.path isEqualToString:CSProfile.cliPath]);
    CHECK([cli.name isEqualToString:@"~/.config/shyake"]);
    CHECK([cli isEqual:[[CSProfile alloc] initWithPath:CSProfile.cliPath
                                                  name:@"x"]]);

    struct stat st;
    CHECK(stat(p.path.fileSystemRepresentation, &st) == 0 &&
          (st.st_mode & 0777) == 0700);

    // the CLI template, with its quoted strftime value unquoted
    CHECK([[p configValue:@"TIME_FORMAT"] isEqualToString:@"%Y-%m-%d %H:%M"]);
    CHECK([[p configValue:@"CHECK_COLUMNS"]
        isEqualToString:@"id,sender,subject,size,date"]);
    CHECK([p configValue:@"INSTANCE"] == nil);
    NSUInteger comments = count_lines(p, @"#");

    // INSTANCE without USERNAME: the state before registration
    CHECK([p setInstance:@"http://127.0.0.1:8787" username:@""]);
    CHECK([[p configValue:@"INSTANCE"] isEqualToString:@"http://127.0.0.1:8787"]);
    CHECK([p configValue:@"USERNAME"] == nil);
    CHECK(p.identity == nil);

    // registered; rewriting twice must not duplicate lines
    CHECK([p setInstance:@"http://127.0.0.1:8787" username:@"alice"]);
    CHECK([p setInstance:@"http://127.0.0.1:8787" username:@"alice"]);
    CHECK([p.identity isEqualToString:@"alice@127.0.0.1:8787"]);
    CHECK(count_lines(p, @"INSTANCE=") == 1);
    CHECK(count_lines(p, @"USERNAME=") == 1);
    CHECK(count_lines(p, @"#") == comments);
    CHECK([[p configValue:@"TIME_ZONE"] isEqualToString:@"auto"]);
}

static void test_session(void)
{
    CSProfile *p = [CSProfile createNamed:@"s"];
    CSSession *s = [[CSSession alloc] initWithProfile:p];
    CHECK(s != nil && !s.unlocked);

    __block BOOL done = NO;
    __block NSString *why = @"unset";
    [s generateKeysWith:@"pw"
                   then:^(NSString *w) {
                     why = w;
                     done = YES;
                   }];
    wait_for(&done);
    CHECK(why == nil);
    CHECK(s.unlocked && p.hasKeys && p.keysEncrypted);
    [s closeAndWait];

    // a fresh context starts locked and opens only with the right one
    s = [[CSSession alloc] initWithProfile:p];
    CHECK(!s.unlocked);
    __block BOOL ok = YES;
    done = NO;
    [s unlockWith:@"nope"
             then:^(BOOL r) {
               ok = r;
               done = YES;
             }];
    wait_for(&done);
    CHECK(!ok && !s.unlocked);
    done = NO;
    [s unlockWith:@"pw"
             then:^(BOOL r) {
               ok = r;
               done = YES;
             }];
    wait_for(&done);
    CHECK(ok && s.unlocked);
    [s closeAndWait];

    // empty passphrase: plain keys, unlocked from the start
    CSProfile *q = [CSProfile createNamed:@"plain"];
    s = [[CSSession alloc] initWithProfile:q];
    done = NO;
    why = @"unset";
    [s generateKeysWith:@""
                   then:^(NSString *w) {
                     why = w;
                     done = YES;
                   }];
    wait_for(&done);
    [s closeAndWait];
    CHECK(why == nil && q.hasKeys && !q.keysEncrypted);
    s = [[CSSession alloc] initWithProfile:q];
    CHECK(s.unlocked);
    [s closeAndWait];
}

int main(void)
{
    @autoreleasepool {
        if (!getenv("CFFIXED_USER_HOME")) {
            fprintf(stderr, "refusing to run without CFFIXED_USER_HOME\n");
            return 2;
        }
        test_store();
        test_session();
    }
    if (failures)
        return 1;
    printf("profile/session tests passed\n");
    return 0;
}
