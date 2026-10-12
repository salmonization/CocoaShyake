#import "MainWindow.h"
#import "Profile.h"
#import "ui.h"

static NSString *const kMonospaceKey = @"MonospaceBody";
static const CGFloat kStatusHeight = 24;
static const CGFloat kSidebarWidth = 220;

// the four fixed mailboxes, in display order
static NSArray<NSString *> *boxes(void)
{
    return @[ @"inbox", @"sent", @"saved", @"drafts" ];
}

static NSString *box_title(NSString *box)
{
    NSDictionary *t = @{
        @"inbox" : NSLocalizedString(@"Inbox", nil),
        @"sent" : NSLocalizedString(@"Sent", nil),
        @"saved" : NSLocalizedString(@"Saved", nil),
        @"drafts" : NSLocalizedString(@"Drafts", nil),
    };
    return t[box];
}

// CHECK_COLUMNS ids the GUI knows; unknown ids are skipped, not fatal
static NSString *column_title(NSString *col)
{
    NSDictionary *t = @{
        @"id" : NSLocalizedString(@"ID", nil),
        @"sender" : NSLocalizedString(@"From", nil),
        @"subject" : NSLocalizedString(@"Subject", nil),
        @"size" : NSLocalizedString(@"Size", nil),
        @"date" : NSLocalizedString(@"Date", nil),
    };
    return t[col];
}

static NSScrollView *scrolled(NSView *doc, NSRect frame)
{
    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:frame];
    sv.documentView = doc;
    sv.hasVerticalScroller = YES;
    sv.autohidesScrollers = YES;
    sv.borderType = NSNoBorder;
    return sv;
}

// A tree row. NSOutlineView tracks rows by object identity, so the
// nodes are built once per setProfiles: and never recreated per call.
@interface CSNode : NSObject
@property(strong) CSProfile *profile;
@property(copy, nullable) NSString *box; // nil: the profile row
@property(strong) NSArray<CSNode *> *children;
@end

@implementation CSNode
@end

@implementation CSMainWindowController {
    NSOutlineView *_outline;
    NSTableView *_table;
    NSTextView *_reading;
    NSTextField *_status;
    NSArray<CSNode *> *_roots;
}

- (instancetype)init
{
    NSWindow *w =
        [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1000, 640)
                                    styleMask:NSWindowStyleMaskTitled |
                                              NSWindowStyleMaskClosable |
                                              NSWindowStyleMaskMiniaturizable |
                                              NSWindowStyleMaskResizable
                                      backing:NSBackingStoreBuffered
                                        defer:NO];
    self = [super initWithWindow:w];
    if (!self)
        return nil;
    w.title = @"CocoaShyake";
    w.minSize = NSMakeSize(720, 400);
    // State restoration would serialize window contents (decrypted
    // bodies) into Saved Application State, bypassing the rule that
    // Export is the only plaintext-to-disk path. Geometry still
    // persists through the frame autosave, which stores no content.
    w.restorable = NO;
    _roots = @[];
    [self buildContent];
    if (![w setFrameUsingName:@"Main"])
        [w center];
    w.frameAutosaveName = @"Main";
    return self;
}

- (void)buildContent
{
    NSView *content = self.window.contentView;
    CGFloat w = NSWidth(content.bounds);
    CGFloat h = NSHeight(content.bounds) - kStatusHeight;
    CGFloat rw = w - kSidebarWidth - 1;
    CGFloat listH = floor(h * 0.4);

    // profile/mailbox tree, source-list styled like Mail's sidebar
    _outline = [[NSOutlineView alloc]
        initWithFrame:NSMakeRect(0, 0, kSidebarWidth, h)];
    NSTableColumn *oc = [[NSTableColumn alloc] initWithIdentifier:@"tree"];
    oc.resizingMask = NSTableColumnAutoresizingMask;
    [_outline addTableColumn:oc];
    _outline.outlineTableColumn = oc;
    _outline.headerView = nil;
    // the one column tracks the sidebar width; left at its default
    // 100pt it truncated every account address
    _outline.columnAutoresizingStyle =
        NSTableViewFirstColumnOnlyAutoresizingStyle;
    _outline.selectionHighlightStyle =
        NSTableViewSelectionHighlightStyleSourceList;
    _outline.floatsGroupRows = NO;
    _outline.autosaveName = @"Tree";
    _outline.autosaveExpandedItems = YES;
    _outline.dataSource = self;
    _outline.delegate = self;

    _table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, rw, listH)];
    _table.usesAlternatingRowBackgroundColors = YES;
    // edge-to-edge rows, as in Claws Mail or classic Outlook, not the
    // rounded inset rows macOS 11 defaults to
    if (@available(macOS 11.0, *))
        _table.style = NSTableViewStyleFullWidth;
    _table.allowsMultipleSelection = NO;
    _table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    _table.dataSource = self;
    _table.delegate = self;

    _reading =
        [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, rw, h - listH - 1)];
    _reading.editable = NO;
    _reading.selectable = YES;
    _reading.textContainerInset = NSMakeSize(10, 10);
    _reading.minSize = NSMakeSize(0, 0);
    _reading.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    _reading.verticallyResizable = YES;
    _reading.horizontallyResizable = NO;
    _reading.autoresizingMask = NSViewWidthSizable;
    _reading.textContainer.widthTracksTextView = YES;
    CSHardenTextView(_reading);
    [self applyBodyFont];

    // Every pane gets a real frame up front. Split views given
    // zero-sized panes saved an empty layout under their autosave
    // names, which then collapsed the right side on every launch.
    NSSplitView *right = [[NSSplitView alloc]
        initWithFrame:NSMakeRect(kSidebarWidth + 1, 0, rw, h)];
    right.vertical = NO;
    right.dividerStyle = NSSplitViewDividerStyleThin;
    [right addSubview:scrolled(_table, NSMakeRect(0, 0, rw, listH))];
    [right addSubview:scrolled(_reading,
                               NSMakeRect(0, listH + 1, rw, h - listH - 1))];

    NSSplitView *outer =
        [[NSSplitView alloc] initWithFrame:NSMakeRect(0, kStatusHeight, w, h)];
    outer.vertical = YES;
    outer.dividerStyle = NSSplitViewDividerStyleThin;
    outer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [outer addSubview:scrolled(_outline, NSMakeRect(0, 0, kSidebarWidth, h))];
    [outer addSubview:right];
    // window resizes go to the mail panes, not the sidebar or list
    [outer setHoldingPriority:NSLayoutPriorityDefaultLow + 10
            forSubviewAtIndex:0];
    [right setHoldingPriority:NSLayoutPriorityDefaultLow + 10
            forSubviewAtIndex:0];
    [content addSubview:outer];
    [outer adjustSubviews];
    [right adjustSubviews];
    // new names on purpose: the old ones hold the empty layout
    outer.autosaveName = @"Sidebar";
    right.autosaveName = @"MailPane";
    [_outline sizeLastColumnToFit];

    // status line in the window's bottom border, centred vertically
    [self.window setAutorecalculatesContentBorderThickness:NO
                                                   forEdge:NSMinYEdge];
    [self.window setContentBorderThickness:kStatusHeight forEdge:NSMinYEdge];
    _status = [NSTextField labelWithString:@" "];
    _status.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _status.textColor = NSColor.secondaryLabelColor;
    _status.lineBreakMode = NSLineBreakByTruncatingTail;
    [_status sizeToFit];
    CGFloat sh = NSHeight(_status.frame);
    _status.frame = NSMakeRect(12, floor((kStatusHeight - sh) / 2), w - 24, sh);
    _status.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [content addSubview:_status];

    [self setColumns:nil];
}

// --- tree ---

- (void)setProfiles:(NSArray<CSProfile *> *)profiles
{
    NSMutableArray<CSNode *> *roots = [NSMutableArray array];
    for (CSProfile *p in profiles) {
        CSNode *root = [CSNode new];
        root.profile = p;
        NSMutableArray<CSNode *> *kids = [NSMutableArray array];
        for (NSString *b in boxes()) {
            CSNode *n = [CSNode new];
            n.profile = p;
            n.box = b;
            n.children = @[];
            [kids addObject:n];
        }
        root.children = kids;
        [roots addObject:root];
    }
    _roots = roots;
    [_outline reloadData];
    // first sight of a profile: open it; afterwards the user's own
    // expand/collapse choice is restored by autosaveExpandedItems
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSMutableArray *seen = [[d stringArrayForKey:@"TreeSeen"] mutableCopy]
                               ?: [NSMutableArray array];
    for (CSNode *r in _roots)
        if (![seen containsObject:r.profile.path]) {
            [_outline expandItem:r];
            [seen addObject:r.profile.path];
        }
    [d setObject:seen forKey:@"TreeSeen"];
}

- (void)selectProfile:(CSProfile *)profile box:(NSString *)box
{
    for (CSNode *r in _roots) {
        if (![r.profile isEqual:profile])
            continue;
        [_outline expandItem:r];
        for (CSNode *n in r.children)
            if ([n.box isEqualToString:box]) {
                NSInteger row = [_outline rowForItem:n];
                [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:row]
                      byExtendingSelection:NO];
                [_outline scrollRowToVisible:row];
            }
    }
}

- (NSString *)selectedBox
{
    CSNode *n = [_outline itemAtRow:_outline.selectedRow];
    return n.box;
}

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item
{
    return item ? (NSInteger)((CSNode *)item).children.count
                : (NSInteger)_roots.count;
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)i ofItem:(id)item
{
    return item ? ((CSNode *)item).children[i] : _roots[i];
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item
{
    return ((CSNode *)item).box == nil;
}

// expansion state is stored by profile path, stable across launches
- (id)outlineView:(NSOutlineView *)ov persistentObjectForItem:(id)item
{
    return ((CSNode *)item).profile.path;
}

- (id)outlineView:(NSOutlineView *)ov itemForPersistentObject:(id)object
{
    for (CSNode *r in _roots)
        if ([r.profile.path isEqual:object])
            return r;
    return nil;
}

- (NSView *)outlineView:(NSOutlineView *)ov
     viewForTableColumn:(NSTableColumn *)tc
                   item:(id)item
{
    CSNode *node = item;
    NSTableCellView *cell = [ov makeViewWithIdentifier:@"cell" owner:self];
    if (!cell) {
        cell = [NSTableCellView new];
        cell.identifier = @"cell";
        NSTextField *t = [NSTextField labelWithString:@""];
        t.translatesAutoresizingMaskIntoConstraints = NO;
        t.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:t];
        cell.textField = t;
        [t.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2]
            .active = YES;
        [t.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor
                                         constant:-2]
            .active = YES;
        [t.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor].active =
            YES;
    }
    if (node.box) {
        cell.textField.stringValue = box_title(node.box);
        cell.textField.font = [NSFont systemFontOfSize:0];
        cell.toolTip = nil;
    } else {
        // an account reads as its address, like a mail client's
        // account list; the folder it lives in is one hover away
        cell.textField.stringValue = node.profile.identity ?: node.profile.name;
        cell.textField.font = [NSFont boldSystemFontOfSize:0];
        cell.toolTip = node.profile.path;
    }
    return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)note
{
    // switching boxes forgets the shown list and any decrypted body
    [self clearMail];
    CSNode *n = [_outline itemAtRow:_outline.selectedRow];
    if (n && self.onSelect)
        self.onSelect(n.profile, n.box);
}

// --- mail list and reading pane ---

- (void)setColumns:(NSString *)checkColumns
{
    NSString *spec = checkColumns ?: @"id,sender,subject,size,date";
    while (_table.tableColumns.count)
        [_table removeTableColumn:_table.tableColumns.lastObject];
    for (NSString *raw in [spec componentsSeparatedByString:@","]) {
        NSString *col =
            [raw stringByTrimmingCharactersInSet:NSCharacterSet
                                                     .whitespaceCharacterSet];
        NSString *title = column_title(col);
        if (!title)
            continue;
        NSTableColumn *tc = [[NSTableColumn alloc] initWithIdentifier:col];
        tc.title = title;
        tc.width = [col isEqualToString:@"subject"] ? 320 : 100;
        tc.minWidth = 40;
        [_table addTableColumn:tc];
    }
    // autosave keys on the column ids, so each layout keeps its widths
    _table.autosaveName = [@"MailColumns-" stringByAppendingString:spec];
    _table.autosaveTableColumns = YES;
    [_table reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv
{
    return 0; // filled from M2 on
}

- (void)setStatusProfile:(NSString *)profile
                identity:(NSString *)identity
                    lock:(NSString *)lock
{
    NSMutableArray *parts = [NSMutableArray arrayWithObject:profile];
    if (identity.length)
        [parts addObject:identity];
    if (lock.length)
        [parts addObject:lock];
    _status.stringValue = [parts componentsJoinedByString:@"    "];
}

- (void)clearMail
{
    [_table reloadData];
    _reading.string = @"";
}

- (void)applyBodyFont
{
    BOOL mono = [NSUserDefaults.standardUserDefaults boolForKey:kMonospaceKey];
    _reading.font =
        mono ? [NSFont userFixedPitchFontOfSize:0] : [NSFont userFontOfSize:0];
}

- (IBAction)toggleMonospace:(id)sender
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setBool:![d boolForKey:kMonospaceKey] forKey:kMonospaceKey];
    [self applyBodyFont];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if (item.action == @selector(toggleMonospace:))
        item.state =
            [NSUserDefaults.standardUserDefaults boolForKey:kMonospaceKey]
                ? NSControlStateValueOn
                : NSControlStateValueOff;
    return YES;
}

@end
