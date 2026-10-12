// Three-pane main window in the Sylpheed / Claws Mail / classic
// Outlook shape: a profile-and-mailbox tree on the left, the mail list
// over the reading pane on the right, a status line along the bottom.

#import <Cocoa/Cocoa.h>

@class CSProfile;

NS_ASSUME_NONNULL_BEGIN

@interface CSMainWindowController
    : NSWindowController <NSOutlineViewDataSource, NSOutlineViewDelegate,
                          NSTableViewDataSource, NSTableViewDelegate>

// called when the user selects a row; box is nil for a profile row
@property(copy, nullable) void (^onSelect)
    (CSProfile *profile, NSString *_Nullable box);

// "inbox", "sent", "saved", "drafts", or nil on a profile row
@property(readonly, copy, nullable) NSString *selectedBox;

// one root per profile, its four mailboxes beneath; rebuilt from
// scratch, keeping expansion state
- (void)setProfiles:(NSArray<CSProfile *> *)profiles;
- (void)selectProfile:(CSProfile *)profile box:(NSString *)box;

- (void)setColumns:(nullable NSString *)checkColumns;
- (void)setStatusProfile:(NSString *)profile
                identity:(NSString *)identity
                    lock:(NSString *)lock;
// drop everything shown; the reading pane may hold plaintext
- (void)clearMail;

- (IBAction)toggleMonospace:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
