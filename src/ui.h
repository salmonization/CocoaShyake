// Code-built UI helpers shared by every window (no XIBs exist).

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Turn off the AppKit text "helpers" that would silently rewrite mail
// (smart quotes and dashes mangle base64 and code). PLAN §5.
void CSHardenTextView(NSTextView *tv);

// A sheet with a message, labelled fields, a status line and
// Cancel/OK. OK does not close it: the handler validates, may run
// async work with the form busy, and calls -end itself on success.
@interface CSForm : NSObject

- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message;
- (NSTextField *)addField:(NSString *)label secure:(BOOL)secure;
- (NSButton *)addCheckbox:(NSString *)title;

- (void)setStatus:(nullable NSString *)text;
- (void)setBusy:(BOOL)busy;
- (void)focus:(NSView *)view;

- (void)beginOn:(NSWindow *)window
             ok:(NSString *)okTitle
         submit:(void (^)(CSForm *form))submit
         cancel:(nullable dispatch_block_t)cancel;
- (void)end;

@end

NS_ASSUME_NONNULL_END
