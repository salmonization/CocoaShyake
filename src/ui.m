#import "ui.h"

void CSHardenTextView(NSTextView *tv)
{
    tv.richText = NO;
    tv.importsGraphics = NO;
    tv.automaticQuoteSubstitutionEnabled = NO;
    tv.automaticDashSubstitutionEnabled = NO;
    tv.automaticTextReplacementEnabled = NO;
    tv.automaticSpellingCorrectionEnabled = NO;
    tv.automaticTextCompletionEnabled = NO;
    tv.continuousSpellCheckingEnabled = NO;
    tv.grammarCheckingEnabled = NO;
    tv.automaticDataDetectionEnabled = NO;
    tv.automaticLinkDetectionEnabled = NO;
    tv.smartInsertDeleteEnabled = NO;
}

@implementation CSForm {
    NSPanel *_panel;
    NSGridView *_grid;
    NSTextField *_status;
    NSProgressIndicator *_spinner;
    NSButton *_ok, *_cancel;
    NSMutableArray<NSControl *> *_inputs;
    NSWindow *_parent;
    void (^_submit)(CSForm *);
    dispatch_block_t _onCancel;
}

- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message
{
    self = [super init];
    if (!self)
        return nil;
    _inputs = [NSMutableArray array];

    NSTextField *head = [NSTextField labelWithString:title];
    head.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    NSTextField *msg = [NSTextField wrappingLabelWithString:message];
    msg.preferredMaxLayoutWidth = 400;

    _grid = [NSGridView gridViewWithNumberOfColumns:2 rows:0];
    _grid.rowAlignment = NSGridRowAlignmentFirstBaseline;
    _grid.rowSpacing = 8;

    _status = [NSTextField wrappingLabelWithString:@""];
    _status.preferredMaxLayoutWidth = 400;
    _status.textColor = NSColor.systemRedColor;
    _status.hidden = YES;

    _spinner = [NSProgressIndicator new];
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.controlSize = NSControlSizeSmall;
    _spinner.displayedWhenStopped = NO;

    _cancel = [NSButton buttonWithTitle:NSLocalizedString(@"Cancel", nil)
                                 target:self
                                 action:@selector(cancelPressed:)];
    _cancel.keyEquivalent = @"\033";
    _ok = [NSButton buttonWithTitle:@"OK"
                             target:self
                             action:@selector(okPressed:)];
    _ok.keyEquivalent = @"\r";
    // spinner on the left, Cancel/OK packed right at their natural
    // size (a plain stack stretched Cancel across the whole row)
    NSStackView *buttons = [NSStackView new];
    [buttons addView:_spinner inGravity:NSStackViewGravityLeading];
    [buttons addView:_cancel inGravity:NSStackViewGravityTrailing];
    [buttons addView:_ok inGravity:NSStackViewGravityTrailing];
    for (NSButton *b in @[ _cancel, _ok ])
        [b.widthAnchor constraintGreaterThanOrEqualToConstant:84].active = YES;

    NSStackView *stack = [NSStackView
        stackViewWithViews:@[ head, msg, _grid, _status, buttons ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    stack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    [stack setCustomSpacing:6 afterView:head];
    // Wrapping labels report a fitting width of zero, so the sheet
    // would shrink to its narrowest row; pin one width for all forms.
    [stack.widthAnchor constraintEqualToConstant:440].active = YES;
    [buttons.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor
                                          constant:20]
        .active = YES;
    [buttons.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor
                                           constant:-20]
        .active = YES;

    _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 420, 200)
                                        styleMask:NSWindowStyleMaskTitled
                                          backing:NSBackingStoreBuffered
                                            defer:YES];
    _panel.restorable = NO;
    _panel.contentView = stack;
    return self;
}

- (NSTextField *)addField:(NSString *)label secure:(BOOL)secure
{
    NSTextField *f = secure ? [NSSecureTextField new] : [NSTextField new];
    [f.widthAnchor constraintEqualToConstant:240].active = YES;
    [_grid addRowWithViews:@[ [NSTextField labelWithString:label], f ]];
    [_grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    if (!_inputs.count)
        _panel.initialFirstResponder = f;
    [_inputs addObject:f];
    return f;
}

- (void)focus:(NSView *)view
{
    [_panel makeFirstResponder:view];
}

- (NSButton *)addCheckbox:(NSString *)title
{
    NSButton *b = [NSButton checkboxWithTitle:title target:nil action:nil];
    [_grid addRowWithViews:@[ NSGridCell.emptyContentView, b ]];
    [_inputs addObject:b];
    return b;
}

- (void)setStatus:(NSString *)text
{
    _status.stringValue = text ?: @"";
    _status.hidden = text.length == 0;
    [_panel setContentSize:_panel.contentView.fittingSize];
}

- (void)setBusy:(BOOL)busy
{
    for (NSControl *c in _inputs)
        if (!c.tag) // tag 1 = locked by the caller, stays disabled
            c.enabled = !busy;
    _ok.enabled = _cancel.enabled = !busy;
    if (busy)
        [_spinner startAnimation:nil];
    else
        [_spinner stopAnimation:nil];
}

- (void)beginOn:(NSWindow *)window
             ok:(NSString *)okTitle
         submit:(void (^)(CSForm *))submit
         cancel:(dispatch_block_t)cancel
{
    _ok.title = okTitle;
    _submit = submit;
    _onCancel = cancel;
    _parent = window;
    [_panel setContentSize:_panel.contentView.fittingSize];
    // the sheet holds the only strong reference to self while shown
    [window beginSheet:_panel
        completionHandler:^(NSModalResponse r) {
            (void)r;
            (void)self;
        }];
}

- (void)end
{
    [_parent endSheet:_panel];
    _submit = nil;
    _onCancel = nil;
}

- (void)okPressed:(id)sender
{
    [self setStatus:nil];
    if (_submit)
        _submit(self);
}

- (void)cancelPressed:(id)sender
{
    dispatch_block_t cancel = _onCancel;
    [self end];
    if (cancel)
        cancel();
}

@end
