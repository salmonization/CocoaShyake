// CocoaShyake entry point and application delegate: menus, and the
// profile lifecycle (first-run wizard, open, unlock, switch, close).
//
// There is no Xcode project and no XIB; every window and menu is
// built in code so the whole app compiles with clang alone.

#import <Cocoa/Cocoa.h>
#include <sys/resource.h>

#import "MainWindow.h"
#import "Profile.h"
#import "Session.h"
#import "ui.h"

static NSString *const kDefaultProfileKey = @"DefaultProfile";

static NSString *trimmed(NSTextField *f)
{
    return [f.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet
                                            .whitespaceAndNewlineCharacterSet];
}

static BOOL valid_instance(NSString *s)
{
    NSURL *u = [NSURL URLWithString:s];
    return u.host.length && ([u.scheme isEqualToString:@"https"] ||
                             [u.scheme isEqualToString:@"http"]);
}

// Same layout as the CLI's fingerprint output, so two people reading
// it aloud over another channel see identical groups.
static NSString *format_fp(const unsigned char *fp)
{
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < 16; i++) {
        [s appendFormat:@"%02X%02X", fp[i * 2], fp[i * 2 + 1]];
        if (i == 7)
            [s appendString:@"\n"];
        else if (i == 3 || i == 11)
            [s appendString:@"  "];
        else if (i != 15)
            [s appendString:@" "];
    }
    return s;
}

static NSMenuItem *item(NSString *title, SEL action, NSString *key)
{
    return [[NSMenuItem alloc] initWithTitle:title
                                      action:action
                               keyEquivalent:key];
}

static NSMenuItem *submenu(NSMenu *bar, NSString *title)
{
    NSMenuItem *top = [bar addItemWithTitle:title action:nil keyEquivalent:@""];
    top.submenu = [[NSMenu alloc] initWithTitle:title];
    return top;
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property(strong) CSMainWindowController *main;
// the profile shown now; every opened profile keeps its session (and
// so its unlocked keys) until quit, so moving around the tree never
// asks for a passphrase twice
@property(strong, nullable) CSSession *session;
@property(strong) NSMutableDictionary<NSString *, CSSession *> *sessions;
@property(strong) NSMenu *profileMenu;
@end

@implementation AppDelegate

// --- menus ---

- (NSMenu *)buildMenu
{
    NSString *app = @"CocoaShyake";
    NSMenu *bar = [NSMenu new];
    NSMenuItem *it;

    NSMenu *m = submenu(bar, app).submenu;
    [m addItem:item([NSString
                        stringWithFormat:NSLocalizedString(@"About %@", nil),
                                         app],
                    @selector(orderFrontStandardAboutPanel:), @"")];
    [m addItem:NSMenuItem.separatorItem];
    [m addItem:item([NSString
                        stringWithFormat:NSLocalizedString(@"Hide %@", nil),
                                         app],
                    @selector(hide:), @"h")];
    it = item(NSLocalizedString(@"Hide Others", nil),
              @selector(hideOtherApplications:), @"h");
    it.keyEquivalentModifierMask =
        NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [m addItem:it];
    [m addItem:item(NSLocalizedString(@"Show All", nil),
                    @selector(unhideAllApplications:), @"")];
    [m addItem:NSMenuItem.separatorItem];
    [m addItem:item([NSString
                        stringWithFormat:NSLocalizedString(@"Quit %@", nil),
                                         app],
                    @selector(terminate:), @"q")];

    // Items whose action is nil stay disabled until their milestone
    // wires them up; the menu shape is final from M1 on.
    m = submenu(bar, NSLocalizedString(@"File", nil)).submenu;
    [m addItem:item(NSLocalizedString(@"New Message", nil), nil, @"n")];
    [m addItem:NSMenuItem.separatorItem];
    [m addItem:item(NSLocalizedString(@"Close", nil), @selector(performClose:),
                    @"w")];

    // standard Edit menu: text fields only get ⌘C/⌘V through it
    m = submenu(bar, NSLocalizedString(@"Edit", nil)).submenu;
    [m addItem:item(NSLocalizedString(@"Undo", nil), @selector(undo:), @"z")];
    [m addItem:item(NSLocalizedString(@"Redo", nil), @selector(redo:), @"Z")];
    [m addItem:NSMenuItem.separatorItem];
    [m addItem:item(NSLocalizedString(@"Cut", nil), @selector(cut:), @"x")];
    [m addItem:item(NSLocalizedString(@"Copy", nil), @selector(copy:), @"c")];
    [m addItem:item(NSLocalizedString(@"Paste", nil), @selector(paste:), @"v")];
    [m addItem:item(NSLocalizedString(@"Select All", nil),
                    @selector(selectAll:), @"a")];

    m = submenu(bar, NSLocalizedString(@"Mail", nil)).submenu;
    [m addItem:item(NSLocalizedString(@"Get New Mail", nil), nil, @"N")];
    [m addItem:item(NSLocalizedString(@"Reply", nil), nil, @"r")];
    [m addItem:NSMenuItem.separatorItem];
    [m addItem:item(NSLocalizedString(@"Save", nil), nil, @"s")];
    [m addItem:item(NSLocalizedString(@"Export…", nil), nil, @"")];
    [m addItem:NSMenuItem.separatorItem];
    [m addItem:item(NSLocalizedString(@"Burn…", nil), nil, @"\b")];

    m = submenu(bar, NSLocalizedString(@"View", nil)).submenu;
    [m addItem:item(NSLocalizedString(@"Monospaced Body", nil),
                    @selector(toggleMonospace:), @"")];

    self.profileMenu = submenu(bar, NSLocalizedString(@"Profile", nil)).submenu;
    self.profileMenu.delegate = self;

    m = submenu(bar, NSLocalizedString(@"Window", nil)).submenu;
    [m addItem:item(NSLocalizedString(@"Minimize", nil),
                    @selector(performMiniaturize:), @"m")];
    [m addItem:item(NSLocalizedString(@"Zoom", nil), @selector(performZoom:),
                    @"")];
    NSApp.windowsMenu = m;

    NSApp.helpMenu = submenu(bar, NSLocalizedString(@"Help", nil)).submenu;
    return bar;
}

// the Profile menu lists the profiles, rebuilt each time it opens
- (void)menuNeedsUpdate:(NSMenu *)menu
{
    [menu removeAllItems];
    for (CSProfile *p in CSProfile.all) {
        NSString *title =
            p.identity
                ? [NSString stringWithFormat:@"%@  (%@)", p.identity, p.name]
                : p.name;
        NSMenuItem *it = item(title, @selector(switchProfile:), @"");
        it.representedObject = p;
        [menu addItem:it];
    }
    if (menu.numberOfItems)
        [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:item(NSLocalizedString(@"New Profile…", nil),
                       @selector(newProfile:), @"")];
    [menu addItem:item(NSLocalizedString(@"Profile Details…", nil),
                       @selector(showProfileDetails:), @"i")];
}

- (BOOL)validateMenuItem:(NSMenuItem *)it
{
    // a sheet owns the window: no switching profiles underneath it
    BOOL free = self.main.window.attachedSheet == nil;
    if (it.action == @selector(switchProfile:)) {
        it.state = [it.representedObject isEqual:self.session.profile]
                       ? NSControlStateValueOn
                       : NSControlStateValueOff;
        return free;
    }
    if (it.action == @selector(showProfileDetails:))
        return free && self.session != nil;
    if (it.action == @selector(newProfile:))
        return free;
    return YES;
}

// --- profile lifecycle ---

- (void)updateStatus
{
    CSSession *s = self.session;
    NSWindow *w = self.main.window;
    if (!s) {
        w.title = @"CocoaShyake";
        [self.main setStatusProfile:NSLocalizedString(@"Profile: (none)", nil)
                           identity:@""
                               lock:@""];
        return;
    }
    CSProfile *p = s.profile;
    NSString *lock = !p.hasKeys   ? NSLocalizedString(@"No keys", nil)
                     : s.unlocked ? @""
                                  : NSLocalizedString(@"Locked", nil);
    w.title = [NSString stringWithFormat:@"CocoaShyake — %@", p.name];
    [self.main
        setStatusProfile:[NSString stringWithFormat:NSLocalizedString(
                                                        @"Profile: %@", nil),
                                                    p.name]
                identity:p.identity ?: NSLocalizedString(@"Not registered", nil)
                    lock:lock];
}

// rebuild the tree (labels follow registration) and show p's inbox,
// which in turn opens p through the tree's selection callback
- (void)showProfile:(CSProfile *)p
{
    [self.main setProfiles:CSProfile.all];
    [self.main selectProfile:p box:@"inbox"];
}

- (void)openProfile:(CSProfile *)p
{
    if ([p isEqual:self.session.profile])
        return;
    CSSession *s = self.sessions[p.path];
    if (!s) {
        s = [[CSSession alloc] initWithProfile:p];
        if (!s) {
            NSAlert *a = [NSAlert new];
            a.messageText = CSFailure(
                NSLocalizedString(@"Open failed.", nil),
                NSLocalizedString(@"The library context could not be created.",
                                  nil));
            [a beginSheetModalForWindow:self.main.window completionHandler:nil];
            return;
        }
        self.sessions[p.path] = s;
    }
    self.session = s;
    [NSUserDefaults.standardUserDefaults setObject:p.path
                                            forKey:kDefaultProfileKey];
    [self.main setColumns:[p configValue:@"CHECK_COLUMNS"]];
    [self updateStatus];
    if (p.hasKeys && !s.unlocked)
        [self askUnlock];
}

- (void)askUnlock
{
    CSSession *s = self.session;
    CSForm *f = [[CSForm alloc]
        initWithTitle:[NSString
                          stringWithFormat:NSLocalizedString(@"Unlock “%@”",
                                                             nil),
                                           s.profile.identity ?: s.profile.name]
              message:NSLocalizedString(@"Enter the passphrase that "
                                        @"protects this profile's keys. "
                                        @"Without it you can still browse "
                                        @"mail headers.",
                                        nil)];
    NSTextField *pass = [f addField:NSLocalizedString(@"Passphrase:", nil)
                             secure:YES];
    [f beginOn:self.main.window
        ok:NSLocalizedString(@"Unlock", nil)
        submit:^(CSForm *form) {
            NSString *p = pass.stringValue;
            pass.stringValue = @"";
            [form setBusy:YES];
            [s unlockWith:p
                     then:^(BOOL ok) {
                         [form setBusy:NO];
                         if (ok) {
                             [form end];
                             [self updateStatus];
                             return;
                         }
                         [form
                             setStatus:CSFailure(
                                           NSLocalizedString(@"Unlock failed.",
                                                             nil),
                                           NSLocalizedString(
                                               @"The passphrase is incorrect.",
                                               nil))];
                         [form focus:pass];
                     }];
        }
        cancel:^{
            [self updateStatus];
        }];
}

// One form for first run and Profile > New Profile. A profile, once
// created by this run, is reused on retry (only the instance and
// username stay editable), so a failed registration never strands a
// second half-made profile.
- (void)runWizard:(BOOL)firstRun
{
    CSForm *f = [[CSForm alloc]
        initWithTitle:firstRun
                          ? NSLocalizedString(@"Welcome to CocoaShyake", nil)
                          : NSLocalizedString(@"New Profile", nil)
              message:NSLocalizedString(
                          @"A profile holds one account's keys and local "
                          @"mail. The passphrase encrypts the keys on "
                          @"disk; leave it empty to store them "
                          @"unencrypted.",
                          nil)];
    NSTextField *name = [f addField:NSLocalizedString(@"Profile name:", nil)
                             secure:NO];
    NSTextField *inst = [f addField:NSLocalizedString(@"Instance URL:", nil)
                             secure:NO];
    NSTextField *pass = [f addField:NSLocalizedString(@"Passphrase:", nil)
                             secure:YES];
    NSTextField *pass2 = [f addField:NSLocalizedString(@"Confirm:", nil)
                              secure:YES];
    NSTextField *user = [f addField:NSLocalizedString(@"Username:", nil)
                             secure:NO];
    NSButton *reg =
        [f addCheckbox:NSLocalizedString(@"Register on the instance now", nil)];
    reg.state = NSControlStateValueOn;
    if (![CSProfile existsNamed:@"default"])
        name.stringValue = @"default";
    inst.placeholderString = @"https://shyake.eee.coffee";

    __block CSProfile *made = nil;
    __block CSSession *sess = nil;

    // hand the wizard's own session over, so no second unlock
    void (^adopt)(void) = ^{
        self.sessions[made.path] = sess;
        [self showProfile:made];
    };
    void (^finish)(CSForm *) = ^(CSForm *form) {
        pass.stringValue = pass2.stringValue = @"";
        [form end];
        adopt();
    };

    [f beginOn:self.main.window
        ok:NSLocalizedString(@"Create", nil)
        submit:^(CSForm *form) {
            NSString *n = trimmed(name), *i = trimmed(inst), *u = trimmed(user);
            BOOL doReg = reg.state == NSControlStateValueOn;
            if (!made && ![CSProfile isValidName:n]) {
                [form setStatus:NSLocalizedString(
                                    @"Use letters, digits, - and _ for the "
                                    @"profile name.",
                                    nil)];
                return;
            }
            if (!made && [CSProfile existsNamed:n]) {
                [form
                    setStatus:[NSString
                                  stringWithFormat:NSLocalizedString(
                                                       @"A profile named “%@” "
                                                       @"already exists.",
                                                       nil),
                                                   n]];
                return;
            }
            if (!made &&
                ![pass.stringValue isEqualToString:pass2.stringValue]) {
                [form setStatus:NSLocalizedString(
                                    @"The passphrases do not match.", nil)];
                return;
            }
            if (i.length && !valid_instance(i)) {
                [form setStatus:NSLocalizedString(
                                    @"Enter the instance as a URL, such as "
                                    @"https://shyake.eee.coffee.",
                                    nil)];
                return;
            }
            if (doReg && (!i.length || !u.length)) {
                [form setStatus:NSLocalizedString(
                                    @"To register, enter the instance URL "
                                    @"and a username.",
                                    nil)];
                return;
            }

            if (!made) {
                made = [CSProfile createNamed:n];
                if (!made) {
                    [form setStatus:CSFailure(
                                        NSLocalizedString(
                                            @"Profile creation failed.", nil),
                                        NSLocalizedString(
                                            @"The profile folder could not be "
                                            @"written.",
                                            nil))];
                    return;
                }
                name.enabled = NO;
                name.tag = 1;
            }
            // INSTANCE now, so the new context sees it; USERNAME only
            // after the server has accepted the registration
            [made setInstance:i username:@""];
            [sess close];
            sess = [[CSSession alloc] initWithProfile:made];
            [form setBusy:YES];

            void (^registerStep)(void) = ^{
                if (!doReg) {
                    finish(form);
                    return;
                }
                __block shyake_err rc = SHYAKE_OK;
                __block NSString *why = nil;
                [sess
                    run:^(shyake_ctx *ctx) {
                        rc = shyake_register(ctx, u.UTF8String);
                        if (rc != SHYAKE_OK)
                            why = @(shyake_last_error(ctx));
                    }
                    then:^{
                        [form setBusy:NO];
                        if (rc == SHYAKE_OK) {
                            [made setInstance:i username:u];
                            finish(form);
                        } else {
                            [form
                                setStatus:CSFailure(
                                              NSLocalizedString(
                                                  @"Registration failed.", nil),
                                              why)];
                        }
                    }];
            };

            if (made.hasKeys) {
                // retry after a failed registration: keys exist already
                [sess unlockWith:pass.stringValue
                            then:^(BOOL ok) {
                                if (ok) {
                                    registerStep();
                                    return;
                                }
                                [form setBusy:NO];
                                [form setStatus:CSFailure(
                                                    NSLocalizedString(
                                                        @"Unlock failed.", nil),
                                                    NSLocalizedString(
                                                        @"The passphrase is "
                                                        @"incorrect.",
                                                        nil))];
                            }];
                return;
            }
            [sess generateKeysWith:pass.stringValue
                              then:^(NSString *why) {
                                  if (why) {
                                      [form setBusy:NO];
                                      [form setStatus:CSFailure(
                                                          NSLocalizedString(
                                                              @"Key generation "
                                                              @"failed.",
                                                              nil),
                                                          why)];
                                      return;
                                  }
                                  // the keys are bound to this passphrase now
                                  pass.enabled = pass2.enabled = NO;
                                  pass.tag = pass2.tag = 1;
                                  registerStep();
                              }];
        }
        cancel:^{
            pass.stringValue = pass2.stringValue = @"";
            // keep what this run created; it opens unregistered
            if (made && sess)
                adopt();
            else if (made)
                [self showProfile:made];
            else
                [self updateStatus];
        }];
}

// --- actions ---

- (IBAction)switchProfile:(NSMenuItem *)sender
{
    [self.main selectProfile:sender.representedObject box:@"inbox"];
}

- (IBAction)newProfile:(id)sender
{
    [self runWizard:NO];
}

- (IBAction)showProfileDetails:(id)sender
{
    CSSession *s = self.session;
    __block NSString *fp = nil;
    // self fingerprint reads kem_pk.bin only: no network, no unlock
    [s
        run:^(shyake_ctx *ctx) {
            shyake_fp_result *r = shyake_fingerprint(ctx, NULL, 0);
            if (r)
                fp = format_fp(r->remote_fp);
            shyake_free_fp_result(r);
        }
        then:^{
            CSProfile *p = s.profile;
            NSAlert *a = [NSAlert new];
            a.messageText =
                p.identity ?: NSLocalizedString(@"Not registered", nil);
            a.informativeText = [NSString
                stringWithFormat:NSLocalizedString(
                                     @"Profile: %@\nInstance: %@\nFolder: %@",
                                     nil),
                                 p.name,
                                 [p configValue:@"INSTANCE"]
                                     ?: NSLocalizedString(@"(none)", nil),
                                 p.path];
            if (fp) {
                NSTextField *t = [NSTextField
                    labelWithString:[NSString stringWithFormat:
                                                  @"%@\n%@",
                                                  NSLocalizedString(
                                                      @"Key fingerprint:", nil),
                                                  fp]];
                t.font = [NSFont userFixedPitchFontOfSize:0];
                t.selectable = YES;
                [t sizeToFit];
                a.accessoryView = t;
            }
            [a beginSheetModalForWindow:self.main.window completionHandler:nil];
        }];
}

// --- application ---

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
    NSApp.mainMenu = [self buildMenu];
    self.main = [CSMainWindowController new];
    [self.main showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];

    self.sessions = [NSMutableDictionary dictionary];
    __weak AppDelegate *weak = self;
    self.main.onSelect = ^(CSProfile *p, NSString *box) {
        (void)box; // which mailbox to list matters from M2 on
        [weak openProfile:p];
    };

    // an existing CLI setup is a profile already: no wizard for it
    NSArray<CSProfile *> *all = CSProfile.all;
    if (!all.count) {
        [self updateStatus];
        [self runWizard:YES];
        return;
    }
    NSString *last =
        [NSUserDefaults.standardUserDefaults stringForKey:kDefaultProfileKey];
    CSProfile *open = all.firstObject;
    for (CSProfile *p in all)
        if ([p.path isEqualToString:last])
            open = p;
    [self showProfile:open];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
    return YES;
}

// zeroize the passphrase before the process goes away
- (void)applicationWillTerminate:(NSNotification *)note
{
    for (CSSession *s in self.sessions.allValues)
        [s closeAndWait];
}

@end

int main(void)
{
    // A crash must not leave a core file holding the passphrase.
    struct rlimit nocore = {0, 0};
    setrlimit(RLIMIT_CORE, &nocore);

    @autoreleasepool {
        AppDelegate *delegate = [AppDelegate new];
        NSApplication *app = [NSApplication sharedApplication];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
