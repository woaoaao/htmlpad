//
//  viewer.m — 「HTML」本地 HTML 查看器（Objective-C 版，功能对齐 SwiftUI 版）
//  Ubuntu 交叉编译（clang + ld64.lld + iPhoneOS SDK）→ 未签名 ipa
//
//  三个 Tab：我的 HTML / 收藏夹 / 设置
//  预览页：关闭 / 文件名 / 查找 / ⋯ 菜单（收藏、源码、重载、显示、网络、外链、分享）
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

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

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"搜索文件";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[VStore shared] reload];
    [self.tableView reloadData];
    [self refreshEmptyState];
}

- (void)buildAddMenu {
    __weak typeof(self) weakSelf = self;
    UIAction *openFile = [UIAction actionWithTitle:@"打开 HTML 文件"
                                            image:[UIImage systemImageNamed:@"doc.badge.plus"]
                                       identifier:nil
                                          handler:^(UIAction *action) { [weakSelf pickFile]; }];
    UIAction *paste = [UIAction actionWithTitle:@"粘贴代码"
                                         image:[UIImage systemImageNamed:@"doc.on.clipboard"]
                                    identifier:nil
                                       handler:^(UIAction *action) { [weakSelf presentPaste]; }];
    UIAction *folder = [UIAction actionWithTitle:@"打开文件夹"
                                           image:[UIImage systemImageNamed:@"folder.badge.plus"]
                                      identifier:nil
                                         handler:^(UIAction *action) { [weakSelf pickFolder]; }];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:@"plus.circle.fill"] forState:UIControlStateNormal];
    button.menu = [UIMenu menuWithTitle:@"" children:@[openFile, paste, folder]];
    button.showsMenuAsPrimaryAction = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:button];
}

- (void)refreshEmptyState {
    BOOL hasFiles = [VStore shared].files.count > 0;
    self.emptyLabel.hidden = hasFiles;
    self.tableView.hidden = !hasFiles;
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
        [weakSelf presentViewController:alert animated:YES completion:nil];
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
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)pickFile {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.html", @"public.plain-text"]
                                                               inMode:UIDocumentPickerModeOpen];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)pickFolder {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.folder"]
                                                               inMode:UIDocumentPickerModeOpen];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
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
    PasteController *paste = [[PasteController alloc] init];
    __weak typeof(self) weakSelf = self;
    paste.onSave = ^(NSString *name, NSString *code) {
        [[VStore shared] createFileNamed:name content:code];
        [weakSelf.tableView reloadData];
        [weakSelf refreshEmptyState];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:paste];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;

    [self presentViewController:nav animated:YES completion:nil];
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
    [self presentViewController:nav animated:YES completion:nil];
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
    __weak typeof(self) weakSelf = self;

    UIButton *searchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [searchButton setImage:[UIImage systemImageNamed:@"magnifyingglass"] forState:UIControlStateNormal];
    [searchButton addAction:[UIAction actionWithHandler:^(UIAction *action) {
        [weakSelf presentFind];
    }] forControlEvents:UIControlEventTouchUpInside];

    UIButton *moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [moreButton setImage:[UIImage systemImageNamed:@"ellipsis.circle.fill"] forState:UIControlStateNormal];
    moreButton.showsMenuAsPrimaryAction = YES;
    [self rebuildMoreMenu:moreButton];

    UIBarButtonItem *searchItem = [[UIBarButtonItem alloc] initWithCustomView:searchButton];
    UIBarButtonItem *moreItem = [[UIBarButtonItem alloc] initWithCustomView:moreButton];
    self.navigationItem.rightBarButtonItems = @[moreItem, searchItem];
}

- (void)rebuildMoreMenu:(UIButton *)button {
    __weak typeof(self) weakSelf = self;

    BOOL favorite = [[VStore shared] isFavorite:self.file];
    UIAction *fav = [UIAction actionWithTitle:(favorite ? @"取消收藏" : @"添加到收藏")
                                        image:[UIImage systemImageNamed:(favorite ? @"star.slash" : @"star")]
                                   identifier:nil
                                      handler:^(UIAction *action) {
        [[VStore shared] toggleFavorite:weakSelf.file];
        [weakSelf rebuildMoreMenu:button];
    }];

    UIAction *source = [UIAction actionWithTitle:@"查看源代码"
                                           image:[UIImage systemImageNamed:@"chevron.left.forwardslash.chevron.right"]
                                      identifier:nil
                                         handler:^(UIAction *action) {
        SourceController *controller = [[SourceController alloc] initWithFile:weakSelf.file];
        [weakSelf.navigationController pushViewController:controller animated:YES];
    }];

    UIAction *reload = [UIAction actionWithTitle:@"重新加载"
                                           image:[UIImage systemImageNamed:@"arrow.clockwise"]
                                      identifier:nil
                                         handler:^(UIAction *action) { [weakSelf.webView reload]; }];

    UIAction *systemStyle = [UIAction actionWithTitle:@"跟随系统"
                                                image:[UIImage systemImageNamed:(weakSelf.styleMode == 0 ? @"checkmark" : @"circle.lefthalf.filled")]
                                           identifier:nil
                                              handler:^(UIAction *action) { [weakSelf setStyleMode:0 button:button]; }];
    UIAction *lightStyle = [UIAction actionWithTitle:@"浅色"
                                               image:[UIImage systemImageNamed:(weakSelf.styleMode == 1 ? @"checkmark" : @"sun.max")]
                                          identifier:nil
                                             handler:^(UIAction *action) { [weakSelf setStyleMode:1 button:button]; }];
    UIAction *darkStyle = [UIAction actionWithTitle:@"深色"
                                              image:[UIImage systemImageNamed:(weakSelf.styleMode == 2 ? @"checkmark" : @"moon")]
                                         identifier:nil
                                            handler:^(UIAction *action) { [weakSelf setStyleMode:2 button:button]; }];
    UIMenu *styleMenu = [UIMenu menuWithTitle:@"显示"
                                        image:[UIImage systemImageNamed:@"circle.lefthalf.filled"]
                                   identifier:nil
                                      options:0
                                     children:@[systemStyle, lightStyle, darkStyle]];

    UIAction *allowNetwork = [UIAction actionWithTitle:@"允许"
                                                 image:[UIImage systemImageNamed:(weakSelf.networkAllowed ? @"checkmark" : @"wifi")]
                                            identifier:nil
                                               handler:^(UIAction *action) { [weakSelf setNetworkAllowed:YES button:button]; }];
    UIAction *denyNetwork = [UIAction actionWithTitle:@"禁止"
                                                image:[UIImage systemImageNamed:(weakSelf.networkAllowed ? @"wifi.slash" : @"checkmark")]
                                           identifier:nil
                                              handler:^(UIAction *action) { [weakSelf setNetworkAllowed:NO button:button]; }];
    UIMenu *networkMenu = [UIMenu menuWithTitle:@"网络访问"
                                          image:[UIImage systemImageNamed:(weakSelf.networkAllowed ? @"network" : @"network.slash")]
                                     identifier:nil
                                        options:0
                                       children:@[allowNetwork, denyNetwork]];

    UIAction *inApp = [UIAction actionWithTitle:@"App 内打开"
                                          image:[UIImage systemImageNamed:(weakSelf.externalInSafari ? @"iphone" : @"checkmark")]
                                     identifier:nil
                                        handler:^(UIAction *action) { [weakSelf setExternalInSafari:NO button:button]; }];
    UIAction *inSafari = [UIAction actionWithTitle:@"Safari 中打开"
                                             image:[UIImage systemImageNamed:(weakSelf.externalInSafari ? @"checkmark" : @"safari")]
                                        identifier:nil
                                           handler:^(UIAction *action) { [weakSelf setExternalInSafari:YES button:button]; }];
    UIMenu *externalMenu = [UIMenu menuWithTitle:@"外部链接"
                                            image:[UIImage systemImageNamed:@"arrow.up.right.square"]
                                       identifier:nil
                                          options:0
                                         children:@[inApp, inSafari]];

    UIAction *share = [UIAction actionWithTitle:@"分享文件"
                                          image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                     identifier:nil
                                        handler:^(UIAction *action) { [weakSelf shareTapped]; }];

    button.menu = [UIMenu menuWithTitle:@""
                               children:@[fav, source, reload, styleMenu, networkMenu, externalMenu, share]];
}

- (void)setStyleMode:(NSInteger)mode button:(UIButton *)button {
    self.styleMode = mode;
    self.webView.overrideUserInterfaceStyle = StyleFromMode(mode);
    [self rebuildMoreMenu:button];
}

- (void)setNetworkAllowed:(BOOL)allowed button:(UIButton *)button {
    self.networkAllowed = allowed;
    if (allowed) {
        [self.webView.configuration.userContentController removeAllContentRuleLists];
        [self.webView reload];
    } else {
        [self applyBlockRuleList];
    }
    [self rebuildMoreMenu:button];
}

- (void)setExternalInSafari:(BOOL)safari button:(UIButton *)button {
    self.externalInSafari = safari;
    [self rebuildMoreMenu:button];
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
    [self presentViewController:activity animated:YES completion:nil];
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
    [self presentViewController:activity animated:YES completion:nil];
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
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[RootTabController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, @"AppDelegate");
    }
}