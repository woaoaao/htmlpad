//
//  viewer.m — 「HTML」本地 HTML 查看器（Objective-C 版，功能对齐 SwiftUI 版）
//  Ubuntu 交叉编译（clang + ld64.lld + iPhoneOS SDK）→ 未签名 ipa
//
//  三个 Tab：我的 HTML / 收藏夹 / 设置
//  预览页：关闭 / 文件名 / 查找 / ⋯ 菜单（收藏、源码、重载、显示、网络、外链、分享）
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface RootTabController : UITabBarController
- (void)setOverrideColorScheme;
@end

#pragma mark - 设置读写

static NSUserDefaults *UD(void) { return [NSUserDefaults standardUserDefaults]; }

static BOOL PrefAllowJS(void) {
    id value = [UD() objectForKey:@"allowJS"];
    return value ? [value boolValue] : YES;
}
static BOOL PrefAllowNetwork(void) {
    id value = [UD() objectForKey:@"allowNetwork"];
    return value ? [value boolValue] : YES;
}
static BOOL PrefExternalSafari(void) {
    id value = [UD() objectForKey:@"openExternalInSafari"];
    return value ? [value boolValue] : YES;
}
static NSInteger PrefAppearance(void) {
    id value = [UD() objectForKey:@"appearance"];
    return value ? [value integerValue] : 0;
}
static UIUserInterfaceStyle StyleFromMode(NSInteger mode) {
    switch (mode) {
        case 1: return UIUserInterfaceStyleLight;
        case 2: return UIUserInterfaceStyleDark;
        default: return UIUserInterfaceStyleUnspecified;
    }
}

#pragma mark - 工具

static NSString *FormatSize(long long bytes) {
    return [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
}

static NSString *FormatDate(NSDate *date) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"MM-dd HH:mm";
    });
    return [formatter stringFromDate:date ?: [NSDate date]];
}

static NSString *ReadTextFile(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) { return @""; }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text) { return text; }
    NSStringEncoding gb = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    text = [[NSString alloc] initWithData:data encoding:gb];
    if (text) { return text; }
    text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    return text ?: @"";
}



#pragma mark - 现场日志（点一下就知道走到哪一步）

static NSMutableArray<NSString *> *gLogLines = nil;
static __weak UILabel *gLogLabel = nil;

static void LogEvent(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *text = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[HTML] %@", text);

    if (!gLogLines) { gLogLines = [NSMutableArray array]; }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    [gLogLines addObject:[NSString stringWithFormat:@"%@ %@", [formatter stringFromDate:[NSDate date]], text]];
    while (gLogLines.count > 40) { [gLogLines removeObjectAtIndex:0]; }

    UILabel *label = gLogLabel;
    if (label) {
        NSUInteger count = gLogLines.count;
        NSUInteger from = count > 2 ? count - 2 : 0;
        NSArray *tail = [gLogLines subarrayWithRange:NSMakeRange(from, count - from)];
        label.text = [NSString stringWithFormat:@"日志(点我复制)：%@", [tail componentsJoinedByString:@" | "]];
    }
}

static NSString *LogText(void) {
    return gLogLines ? [gLogLines componentsJoinedByString:@"\n"] : @"(空)";
}

/// 统一的弹出入口：
/// 从 UIMenu / UIContextualAction 的回调里同步 present 会被 UIKit 静默丢弃，
/// 这里延到下一个 runloop，并在失败时给出可见提示，方便定位问题。
static void PresentSafely(UIViewController *presenter, UIViewController *target, NSString *debugName) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIViewController *top = presenter;
        while (top.presentedViewController) {
            top = top.presentedViewController;
        }
        LogEvent(@"准备弹出 %@", debugName);
        [top presentViewController:target animated:YES completion:nil];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (top.presentedViewController != target) {
                LogEvent(@"%@ 弹不出来", debugName);
                UIAlertController *alert =
                    [UIAlertController alertControllerWithTitle:@"无法打开"
                                                        message:[NSString stringWithFormat:@"%@ 没有弹出来", debugName]
                                                 preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [top presentViewController:alert animated:YES completion:nil];
            }
        });
    });
}

#pragma mark - 数据层

@interface VStore : NSObject
@property (nonatomic, copy) NSString *rootPath;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *files;
@property (nonatomic, strong) NSMutableArray<NSString *> *favorites;
+ (instancetype)shared;
- (void)reload;
- (BOOL)importFromURL:(NSURL *)url;
- (BOOL)createFileNamed:(NSString *)name content:(NSString *)content;
- (void)deleteFile:(NSDictionary *)file;
- (void)clearAll;
- (BOOL)isFavorite:(NSDictionary *)file;
- (void)toggleFavorite:(NSDictionary *)file;
- (NSArray<NSDictionary *> *)favoriteFiles;
- (NSString *)totalBytesText;
@end

@implementation VStore

+ (instancetype)shared {
    static VStore *store = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[VStore alloc] init];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        _rootPath = [documents stringByAppendingPathComponent:@"HTML"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_rootPath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
        NSArray *stored = [UD() arrayForKey:@"html.favorites.v1"];
        _favorites = stored ? [stored mutableCopy] : [NSMutableArray array];
        _files = [NSMutableArray array];
        [self reload];
    }
    return self;
}

- (void)reload {
    NSMutableArray *result = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSSet *allowed = [NSSet setWithArray:@[@"html", @"htm", @"xhtml", @"shtml", @"css", @"js", @"mjs",
                                           @"json", @"txt", @"md", @"markdown", @"xml", @"svg"]];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:self.rootPath];
    for (NSString *relative in enumerator) {
        NSString *fullPath = [self.rootPath stringByAppendingPathComponent:relative];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:fullPath isDirectory:&isDir] || isDir) { continue; }
        if (![allowed containsObject:fullPath.pathExtension.lowercaseString]) { continue; }

        NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:NULL];
        [result addObject:@{
            @"name": fullPath.lastPathComponent,
            @"path": fullPath,
            @"rel": relative,
            @"size": attrs[NSFileSize] ?: @0,
            @"modified": attrs[NSFileModificationDate] ?: [NSDate distantPast],
        }];
    }
    [result sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"modified"] compare:a[@"modified"]];
    }];
    self.files = result;
}

- (NSString *)uniquePathForName:(NSString *)name {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *candidate = [self.rootPath stringByAppendingPathComponent:name];
    if (![fm fileExistsAtPath:candidate]) { return candidate; }
    NSString *base = name.stringByDeletingPathExtension;
    NSString *ext = name.pathExtension;
    NSInteger index = 2;
    while ([fm fileExistsAtPath:candidate]) {
        NSString *next = ext.length ? [NSString stringWithFormat:@"%@-%ld.%@", base, (long)index, ext]
                                    : [NSString stringWithFormat:@"%@-%ld", base, (long)index];
        candidate = [self.rootPath stringByAppendingPathComponent:next];
        index += 1;
    }
    return candidate;
}

- (BOOL)importFromURL:(NSURL *)url {
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSString *name = url.lastPathComponent.length ? url.lastPathComponent : @"导入文件";
    NSString *target = [self uniquePathForName:name];
    BOOL ok = [[NSFileManager defaultManager] copyItemAtPath:url.path toPath:target error:NULL];
    if (scoped) { [url stopAccessingSecurityScopedResource]; }
    if (ok) { [self reload]; }
    return ok;
}

- (BOOL)createFileNamed:(NSString *)rawName content:(NSString *)content {
    NSString *name = [rawName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0) { name = @"未命名.html"; }
    if (name.pathExtension.length == 0) { name = [name stringByAppendingString:@".html"]; }
    NSString *target = [self uniquePathForName:name];
    BOOL ok = [content writeToFile:target atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    if (ok) { [self reload]; }
    return ok;
}

- (void)deleteFile:(NSDictionary *)file {
    [[NSFileManager defaultManager] removeItemAtPath:file[@"path"] error:NULL];
    if (file[@"rel"]) { [self.favorites removeObject:file[@"rel"]]; }
    [UD() setObject:self.favorites forKey:@"html.favorites.v1"];
    [self reload];
}

- (BOOL)isFavorite:(NSDictionary *)file {
    NSString *rel = file[@"rel"];
    return rel ? [self.favorites containsObject:rel] : NO;
}

- (void)toggleFavorite:(NSDictionary *)file {
    NSString *rel = file[@"rel"];
    if (!rel) { return; }
    if ([self.favorites containsObject:rel]) {
        [self.favorites removeObject:rel];
    } else {
        [self.favorites addObject:rel];
    }
    [UD() setObject:self.favorites forKey:@"html.favorites.v1"];
}

- (NSArray<NSDictionary *> *)favoriteFiles {
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *file in self.files) {
        NSString *rel = file[@"rel"];
        if (rel && [self.favorites containsObject:rel]) { [result addObject:file]; }
    }
    return result;
}

- (void)clearAll {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *name in [fm contentsOfDirectoryAtPath:self.rootPath error:NULL]) {
        [fm removeItemAtPath:[self.rootPath stringByAppendingPathComponent:name] error:NULL];
    }
    [self.favorites removeAllObjects];
    [UD() setObject:self.favorites forKey:@"html.favorites.v1"];
    [self reload];
}

- (NSString *)totalBytesText {
    long long total = 0;
    for (NSDictionary *file in self.files) { total += [file[@"size"] longLongValue]; }
    return [NSByteCountFormatter stringFromByteCount:total countStyle:NSByteCountFormatterCountStyleFile];
}

@end

#pragma mark - 前置声明（实现放在后面）

@interface PreviewController : UIViewController <WKNavigationDelegate, WKUIDelegate>
@property (nonatomic, strong) NSDictionary *file;
@end

@interface SourceController : UIViewController <UISearchResultsUpdating>
- (instancetype)initWithFile:(NSDictionary *)file;
@end

#pragma mark - 粘贴代码（半屏）

@interface PasteController : UIViewController
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, copy) void (^onSave)(NSString *name, NSString *code);
@end

@implementation PasteController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"粘贴代码";

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                     target:self
                                                     action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                     target:self
                                                     action:@selector(saveTapped)];

    self.nameField = [[UITextField alloc] init];
    self.nameField.text = @"新建页面.html";
    self.nameField.borderStyle = UITextBorderStyleRoundedRect;
    self.nameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.nameField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.nameField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.nameField];

    self.textView = [[UITextView alloc] init];
    self.textView.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.text =
        @"<!DOCTYPE html>\n<html>\n<head><meta charset=\"utf-8\"><title>新页面</title></head>\n"
         "<body>\n  <h1>Hello</h1>\n</body>\n</html>";
    self.textView.layer.borderColor = [UIColor separatorColor].CGColor;
    self.textView.layer.borderWidth = 1.0;
    self.textView.layer.cornerRadius = 8.0;
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.textView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.nameField.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [self.nameField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.nameField.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.nameField.heightAnchor constraintEqualToConstant:36],
        [self.textView.topAnchor constraintEqualToAnchor:self.nameField.bottomAnchor constant:12],
        [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.textView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16],
    ]];
}

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)saveTapped {
    NSString *code = self.textView.text ?: @"";
    NSString *trimmed = [code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) { return; }
    if (self.onSave) { self.onSave(self.nameField.text ?: @"未命名.html", code); }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - 主页（我的 HTML）

@interface FilesController : UIViewController <UITableViewDataSource, UITableViewDelegate,
                                               UISearchResultsUpdating, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSString *keyword;
@property (nonatomic, strong) UILabel *logLabel;
@end

@implementation FilesController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"HTML";

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 64;
    [self.view addSubview:self.tableView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.font = [UIFont systemFontOfSize:14];
    self.emptyLabel.textColor = [UIColor secondaryLabelColor];
    self.emptyLabel.text = @"还没有 HTML 文件\n点右上角 ＋ 导入文件、粘贴代码或打开文件夹";
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
    ]];

    [self buildAddMenu];

    self.logLabel = [[UILabel alloc] init];
    self.logLabel.font = [UIFont systemFontOfSize:10];
    self.logLabel.textColor = [UIColor secondaryLabelColor];
    self.logLabel.numberOfLines = 2;
    self.logLabel.textAlignment = NSTextAlignmentCenter;
    self.logLabel.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.logLabel.text = @"日志(点我复制)：";
    self.logLabel.userInteractionEnabled = YES;
    self.logLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.logLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                               action:@selector(copyLog)]];
    [self.view addSubview:self.logLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.logLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.logLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.logLabel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.logLabel.heightAnchor constraintEqualToConstant:30],
    ]];
    gLogLabel = self.logLabel;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"搜索文件";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(filesChanged:)
                                                 name:@"HTMLPadFilesChanged"
                                               object:nil];
}

- (void)filesChanged:(NSNotification *)notification {
    [[VStore shared] reload];
    [self.tableView reloadData];
    [self refreshEmptyState];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[VStore shared] reload];
    [self.tableView reloadData];
    [self refreshEmptyState];
}

- (void)buildAddMenu {
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                     target:self
                                                     action:@selector(showAddSheet)];
}

- (void)showAddSheet {
    LogEvent(@"点到了 +");
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"打开 HTML 文件"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf pickFile];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"粘贴代码"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf presentPaste];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"打开文件夹"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf pickFolder];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    PresentSafely(self, sheet, @"添加菜单");
}

- (void)refreshEmptyState {
    BOOL hasFiles = [VStore shared].files.count > 0;
    self.emptyLabel.hidden = hasFiles;
    self.tableView.hidden = !hasFiles;
}

- (void)copyLog {
    [UIPasteboard generalPasteboard].string = LogText();
    LogEvent(@"日志已复制到剪贴板");
}

#pragma mark 过滤

- (NSArray<NSDictionary *> *)displayFiles {
    NSArray *all = [VStore shared].files;
    if (self.keyword.length == 0) { return all; }
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSDictionary *file in all) {
        if ([file[@"name"] localizedCaseInsensitiveContainsString:self.keyword]) {
            [filtered addObject:file];
        }
    }
    return filtered;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.keyword = searchController.searchBar.text ?: @"";
    [self.tableView reloadData];
}

#pragma mark 数据源

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self displayFiles].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"file";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier];
    }
    NSDictionary *file = [self displayFiles][indexPath.row];
    cell.textLabel.text = file[@"name"];
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@",
                                 FormatSize([file[@"size"] longLongValue]),
                                 FormatDate(file[@"modified"])];
    cell.imageView.image = [UIImage systemImageNamed:@"chevron.left.forwardslash.chevron.right"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if ([[VStore shared] isFavorite:file]) {
        UIImageView *star = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"star.fill"]];
        star.tintColor = [UIColor systemOrangeColor];
        [star sizeToFit];
        cell.accessoryView = star;
    } else {
        cell.accessoryView = nil;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self openFile:[self displayFiles][indexPath.row]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *file = [self displayFiles][indexPath.row];
    __weak typeof(self) weakSelf = self;

    UIContextualAction *deleteAction =
        [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                title:@"删除"
                                              handler:^(UIContextualAction *action, UIView *sourceView, void (^completion)(BOOL)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除文件"
                                                                      message:file[@"name"]
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            [[VStore shared] deleteFile:file];
            [weakSelf.tableView reloadData];
            [weakSelf refreshEmptyState];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        PresentSafely(weakSelf, alert, @"删除确认");
        completion(YES);
    }];

    BOOL favorite = [[VStore shared] isFavorite:file];
    UIContextualAction *favAction =
        [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                title:(favorite ? @"取消收藏" : @"收藏")
                                              handler:^(UIContextualAction *action, UIView *sourceView, void (^completion)(BOOL)) {
        [[VStore shared] toggleFavorite:file];
        [weakSelf.tableView reloadData];
        completion(YES);
    }];
    favAction.backgroundColor = [UIColor systemOrangeColor];

    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, favAction]];
}

#pragma mark 打开 / 导入

- (void)openFile:(NSDictionary *)file {
    PreviewController *preview = [[PreviewController alloc] init];
    preview.file = file;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:preview];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    PresentSafely(self, nav, @"预览页");
}

- (void)pickFile {
    LogEvent(@"pickFile 开始");
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    UTType *html = [UTType typeWithIdentifier:@"public.html"];
    if (html) { [types addObject:html]; }
    UTType *text = [UTType typeWithIdentifier:@"public.plain-text"];
    if (text) { [types addObject:text]; }
    if (types.count == 0) { return; }

    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    PresentSafely(self, picker, @"文件选择器");
}

- (void)pickFolder {
    LogEvent(@"pickFolder 开始");
    UTType *folderType = [UTType typeWithIdentifier:@"public.folder"];
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:(folderType ? @[folderType] : @[])
                                                                    asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    PresentSafely(self, picker, @"文件夹选择器");
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    BOOL anyFailure = NO;
    for (NSURL *url in urls) {
        if (![[VStore shared] importFromURL:url]) { anyFailure = YES; }
    }
    [self.tableView reloadData];
    [self refreshEmptyState];
    if (anyFailure) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导入失败"
                                                                      message:@"可能是文件权限受限，试试先拷贝到「文件」App 再导入。"
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)presentPaste {
    LogEvent(@"presentPaste 开始");
    PasteController *paste = [[PasteController alloc] init];
    __weak typeof(self) weakSelf = self;
    paste.onSave = ^(NSString *name, NSString *code) {
        [[VStore shared] createFileNamed:name content:code];
        [weakSelf.tableView reloadData];
        [weakSelf refreshEmptyState];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:paste];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    PresentSafely(self, nav, @"粘贴代码");
}

@end

#pragma mark - 收藏夹

@interface FavoritesController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation FavoritesController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"收藏夹";

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 64;
    [self.view addSubview:self.tableView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.font = [UIFont systemFontOfSize:14];
    self.emptyLabel.textColor = [UIColor secondaryLabelColor];
    self.emptyLabel.text = @"还没有收藏\n在预览页右上角「⋯」里点「添加到收藏」";
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [self.emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[VStore shared] reload];
    [self.tableView reloadData];
    BOOL empty = [VStore shared].favoriteFiles.count == 0;
    self.emptyLabel.hidden = !empty;
    self.tableView.hidden = empty;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [VStore shared].favoriteFiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"fav";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier];
    }
    NSDictionary *file = [VStore shared].favoriteFiles[indexPath.row];
    cell.textLabel.text = file[@"name"];
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@",
                                 FormatSize([file[@"size"] longLongValue]),
                                 FormatDate(file[@"modified"])];
    cell.imageView.image = [UIImage systemImageNamed:@"star.fill"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *file = [VStore shared].favoriteFiles[indexPath.row];
    PreviewController *preview = [[PreviewController alloc] init];
    preview.file = file;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:preview];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    PresentSafely(self, nav, @"预览页");
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *file = [VStore shared].favoriteFiles[indexPath.row];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *action =
        [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                title:@"取消收藏"
                                              handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [[VStore shared] toggleFavorite:file];
        [weakSelf.tableView reloadData];
        done(YES);
    }];
    action.backgroundColor = [UIColor systemOrangeColor];
    return [UISwipeActionsConfiguration configurationWithActions:@[action]];
}

@end

#pragma mark - 设置

@interface SettingsController : UITableViewController
@end

@implementation SettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设置";
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"外观主题";
        case 1: return @"安全";
        case 2: return @"存储与数据";
        default: return @"关于";
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) {
        return @"关闭网络后，页面里的在线脚本、图片、字体都不会被加载；本地文件不受影响。关闭 JavaScript 后需要重新打开页面生效。";
    }
    if (section == 2) {
        return @"清空会删除 App 本地目录里的全部 HTML 文件和收藏记录，不可恢复。";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 1;
        case 1: return 3;
        case 2: return 3;
        default: return 2;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"setting";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                      reuseIdentifier:identifier];
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.textAlignment = NSTextAlignmentNatural;
    cell.detailTextLabel.text = nil;

    if (indexPath.section == 0) {
        cell.textLabel.text = @"主题";
        UISegmentedControl *segmented = [[UISegmentedControl alloc] initWithItems:@[@"跟随系统", @"浅色", @"深色"]];
        segmented.selectedSegmentIndex = PrefAppearance();
        [segmented addTarget:self action:@selector(appearanceChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = segmented;
    } else if (indexPath.section == 1) {
        UISwitch *toggle = [[UISwitch alloc] init];
        if (indexPath.row == 0) {
            cell.textLabel.text = @"允许网络访问";
            toggle.on = PrefAllowNetwork();
            toggle.tag = 1;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"启用 JavaScript";
            toggle.on = PrefAllowJS();
            toggle.tag = 2;
        } else {
            cell.textLabel.text = @"外部链接用 Safari 打开";
            toggle.on = PrefExternalSafari();
            toggle.tag = 3;
        }
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"文件数量";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)[VStore shared].files.count];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"占用空间";
            cell.detailTextLabel.text = [[VStore shared] totalBytesText];
        } else {
            cell.textLabel.text = @"清空数据";
            cell.textLabel.textColor = [UIColor systemRedColor];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
    } else {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"版本";
            cell.detailTextLabel.text = [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] ?: @"1.0";
        } else {
            cell.textLabel.text = @"纯本地运行 · 无广告 · 无内购 · 不收集数据";
            cell.textLabel.font = [UIFont systemFontOfSize:13];
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
            cell.textLabel.numberOfLines = 0;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 2 && indexPath.row == 2) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确定清空全部本地数据？"
                                                                      message:@"所有 HTML 文件和收藏记录都会被删除。"
                                                               preferredStyle:UIAlertControllerStyleAlert];
        __weak typeof(self) weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:@"全部删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            [[VStore shared] clearAll];
            [weakSelf.tableView reloadData];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)appearanceChanged:(UISegmentedControl *)sender {
    [UD() setInteger:sender.selectedSegmentIndex forKey:@"appearance"];
    if ([self.tabBarController isKindOfClass:[RootTabController class]]) {
        [(RootTabController *)self.tabBarController setOverrideColorScheme];
    }
}

- (void)toggleChanged:(UISwitch *)sender {
    if (sender.tag == 1) { [UD() setBool:sender.on forKey:@"allowNetwork"]; }
    else if (sender.tag == 2) { [UD() setBool:sender.on forKey:@"allowJS"]; }
    else { [UD() setBool:sender.on forKey:@"openExternalInSafari"]; }
}

@end

#pragma mark - 预览页

@interface PreviewController ()
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) BOOL networkAllowed;
@property (nonatomic, assign) BOOL externalInSafari;
@property (nonatomic, assign) NSInteger styleMode;
@end

@implementation PreviewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.networkAllowed = PrefAllowNetwork();
    self.externalInSafari = PrefExternalSafari();
    self.styleMode = PrefAppearance();

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 200, 20)];
    titleLabel.text = self.file[@"name"];
    titleLabel.font = [UIFont boldSystemFontOfSize:15];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.navigationItem.titleView = titleLabel;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                     target:self
                                                     action:@selector(closeTapped)];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [UIFont systemFontOfSize:10];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.text = self.file[@"path"];
    self.statusLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.defaultWebpagePreferences.allowsContentJavaScript = PrefAllowJS();
    if (PrefAllowJS()) {
        [config.userContentController addUserScript:[PreviewController viewportScript]];
    }

    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.allowsBackForwardNavigationGestures = YES;
    self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.overrideUserInterfaceStyle = StyleFromMode(self.styleMode);
    [self.view addSubview:self.webView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.statusLabel.topAnchor],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.statusLabel.heightAnchor constraintEqualToConstant:18],
    ]];

    [self buildToolbar];
    [self loadPage];
}

static NSString *const kViewportJS =
    @"(function(){function f(){if(!document.head){return;}if(!document.querySelector('meta[name=\"viewport\"]')){var m=document.createElement('meta');m.name='viewport';m.content='width=device-width,initial-scale=1,viewport-fit=cover';document.head.appendChild(m);}}"
     "if(document.readyState==='loading'){document.addEventListener('DOMContentLoaded',f);}else{f();}"
     "document.addEventListener('click',function(e){var a=e.target&&e.target.closest?e.target.closest('a[target=\"_blank\"]'):null;if(a){a.target='_self';}},true);})();";

+ (WKUserScript *)viewportScript {
    return [[WKUserScript alloc] initWithSource:kViewportJS
                                  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                               forMainFrameOnly:NO];
}

- (void)loadPage {
    NSString *path = self.file[@"path"];
    if (path.length == 0) { return; }
    NSURL *url = [NSURL fileURLWithPath:path];
    // 关键：允许读取整个父文件夹，css / js / 图片才能正常加载
    [self.webView loadFileURL:url allowingReadAccessToURL:[url URLByDeletingLastPathComponent]];
    if (!self.networkAllowed) {
        [self applyBlockRuleList];
    }
}

- (void)applyBlockRuleList {
    NSString *json = @"[{\"trigger\":{\"url-filter\":\".*\"},\"action\":{\"type\":\"block\"}}]";
    __weak typeof(self) weakSelf = self;
    [[WKContentRuleListStore defaultStore] compileContentRuleListForIdentifier:@"html.blockall"
                                                       encodedContentRuleList:json
                                                            completionHandler:^(WKContentRuleList *list, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!list || !weakSelf) { return; }
            WKUserContentController *controller = weakSelf.webView.configuration.userContentController;
            [controller removeAllContentRuleLists];
            [controller addContentRuleList:list];
            [weakSelf.webView reload];
        });
    }];
}

#pragma mark 工具栏 / 菜单

- (void)buildToolbar {
    UIBarButtonItem *search = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSearch
                                                                           target:self
                                                                           action:@selector(presentFind)];
    UIBarButtonItem *more = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                                                            style:UIBarButtonItemStylePlain
                                                           target:self
                                                           action:@selector(showMoreSheet)];
    self.navigationItem.rightBarButtonItems = @[more, search];
}

- (void)showMoreSheet {
    LogEvent(@"点到了 ⋯");
    BOOL favorite = [[VStore shared] isFavorite:self.file];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;

    [sheet addAction:[UIAlertAction actionWithTitle:(favorite ? @"取消收藏" : @"添加到收藏")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [[VStore shared] toggleFavorite:weakSelf.file];
        LogEvent(favorite ? @"已取消收藏" : @"已收藏");
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"查看源代码"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        SourceController *controller = [[SourceController alloc] initWithFile:weakSelf.file];
        [weakSelf.navigationController pushViewController:controller animated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"重新加载"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf.webView reload];
        LogEvent(@"已重新加载");
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"显示方式…"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf showStyleSheet];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"网络访问…"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf showNetworkSheet];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"外部链接…"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf showExternalSheet];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"分享文件"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf shareTapped];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    PresentSafely(self, sheet, @"更多菜单");
}

- (void)showStyleSheet {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"显示方式"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    NSArray *titles = @[@"跟随系统", @"浅色", @"深色"];
    for (NSInteger index = 0; index < titles.count; index++) {
        NSString *mark = (weakSelf.styleMode == index) ? @"✓ " : @"";
        [sheet addAction:[UIAlertAction actionWithTitle:[mark stringByAppendingString:titles[index]]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            [weakSelf setStyleMode:index];
            [weakSelf showStyleSheet];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    PresentSafely(self, sheet, @"显示方式");
}

- (void)showNetworkSheet {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"网络访问"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:(weakSelf.networkAllowed ? @"✓ 允许" : @"允许")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) { [weakSelf setNetworkAllowed:YES]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:(weakSelf.networkAllowed ? @"禁止" : @"✓ 禁止")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) { [weakSelf setNetworkAllowed:NO]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    PresentSafely(self, sheet, @"网络访问");
}

- (void)showExternalSheet {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"外部链接"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:(weakSelf.externalInSafari ? @"App 内打开" : @"✓ App 内打开")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) { [weakSelf setExternalInSafari:NO]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:(weakSelf.externalInSafari ? @"✓ Safari 中打开" : @"Safari 中打开")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) { [weakSelf setExternalInSafari:YES]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    PresentSafely(self, sheet, @"外部链接");
}

- (void)setStyleMode:(NSInteger)mode {
    _styleMode = mode;
    self.webView.overrideUserInterfaceStyle = StyleFromMode(mode);
    LogEvent(@"显示方式 → %ld", (long)mode);
}

- (void)setNetworkAllowed:(BOOL)allowed {
    _networkAllowed = allowed;
    if (allowed) {
        [self.webView.configuration.userContentController removeAllContentRuleLists];
        [self.webView reload];
    } else {
        [self applyBlockRuleList];
    }
    LogEvent(@"网络访问 → %@", allowed ? @"允许" : @"禁止");
}

- (void)setExternalInSafari:(BOOL)safari {
    _externalInSafari = safari;
    LogEvent(@"外部链接 → %@", safari ? @"Safari" : @"App 内");
}

- (void)presentFind {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"在页面中查找"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"关键词";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"查找" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *keyword = alert.textFields.firstObject.text ?: @"";
        if (keyword.length == 0) { return; }
        WKFindConfiguration *config = [[WKFindConfiguration alloc] init];
        config.backwards = NO;
        config.wraps = YES;
        [weakSelf.webView findString:keyword withConfiguration:config completionHandler:^(WKFindResult *result) {
            weakSelf.statusLabel.text = result.matchFound
                ? [NSString stringWithFormat:@"找到：%@", keyword]
                : [NSString stringWithFormat:@"没有找到：%@", keyword];
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)shareTapped {
    NSString *path = self.file[@"path"];
    if (path.length == 0) { return; }
    UIActivityViewController *activity =
        [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]]
                                          applicationActivities:nil];
    activity.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    PresentSafely(self, activity, @"分享面板");
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark 导航策略

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {

    NSURL *url = navigationAction.request.URL;
    NSString *scheme = url.scheme.lowercaseString ?: @"";
    if ([scheme isEqualToString:@"file"] || [scheme isEqualToString:@"about"] ||
        [scheme isEqualToString:@"data"] || [scheme isEqualToString:@"blob"]) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }
    if (!self.networkAllowed) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    if (navigationAction.targetFrame == nil) {
        [webView loadRequest:[NSURLRequest requestWithURL:url]];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    if (navigationAction.targetFrame.isMainFrame && self.externalInSafari) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (WKWebView *)webView:(WKWebView *)webView
createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction
        windowFeatures:(WKWindowFeatures *)windowFeatures {
    NSURL *url = navigationAction.request.URL;
    if (!url || !self.networkAllowed) { return nil; }
    if (self.externalInSafari) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        [webView loadRequest:[NSURLRequest requestWithURL:url]];
    }
    return nil;
}

@end

#pragma mark - 源代码

@interface SourceController ()
@property (nonatomic, strong) NSDictionary *file;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UISearchController *searchController;
@end

@implementation SourceController

- (instancetype)initWithFile:(NSDictionary *)file {
    self = [super initWithNibName:nil bundle:nil];
    if (self) { _file = file; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"源代码";

    self.textView = [[UITextView alloc] init];
    self.textView.editable = NO;
    self.textView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.textView.text = ReadTextFile(self.file[@"path"]);
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.textView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.textView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"搜索代码";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                     target:self
                                                     action:@selector(shareTapped)];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *keyword = searchController.searchBar.text ?: @"";
    if (keyword.length == 0) { return; }
    NSString *text = self.textView.text ?: @"";
    NSRange range = [text rangeOfString:keyword options:NSCaseInsensitiveSearch];
    if (range.location != NSNotFound) {
        self.textView.selectedRange = range;
        [self.textView scrollRangeToVisible:range];
    }
}

- (void)shareTapped {
    NSString *path = self.file[@"path"];
    if (path.length == 0) { return; }
    UIActivityViewController *activity =
        [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]]
                                          applicationActivities:nil];
    activity.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    PresentSafely(self, activity, @"分享面板");
}

@end

#pragma mark - 根 TabBar


@implementation RootTabController

- (void)viewDidLoad {
    [super viewDidLoad];

    FilesController *files = [[FilesController alloc] init];
    UINavigationController *filesNav = [[UINavigationController alloc] initWithRootViewController:files];
    filesNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"我的 HTML"
                                                       image:[UIImage systemImageNamed:@"doc.on.doc"]
                                                         tag:0];

    FavoritesController *favorites = [[FavoritesController alloc] init];
    UINavigationController *favoritesNav = [[UINavigationController alloc] initWithRootViewController:favorites];
    favoritesNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"收藏夹"
                                                           image:[UIImage systemImageNamed:@"star"]
                                                             tag:1];

    SettingsController *settings = [[SettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *settingsNav = [[UINavigationController alloc] initWithRootViewController:settings];
    settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"设置"
                                                          image:[UIImage systemImageNamed:@"gearshape"]
                                                            tag:2];

    self.viewControllers = @[filesNav, favoritesNav, settingsNav];
    self.tabBar.tintColor = [UIColor systemBlueColor];
    [self setOverrideColorScheme];
}

- (void)setOverrideColorScheme {
    self.overrideUserInterfaceStyle = StyleFromMode(PrefAppearance());
}

@end

#pragma mark - AppDelegate

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSURL *launchURL = launchOptions[UIApplicationLaunchOptionsURLKey];
    if (launchURL.isFileURL) {
        [[VStore shared] importFromURL:launchURL];
    }

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[RootTabController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

/// 从「文件」App / 其它 App 用「HTML」打开文件 → 直接导入到沙盒
- (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    if (url.isFileURL) {
        [[VStore shared] importFromURL:url];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"HTMLPadFilesChanged" object:nil];
        });
    }
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, @"AppDelegate");
    }
}