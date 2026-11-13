//
//  HTMLPad — iOS HTML 编辑器（Objective-C 原生外壳 + WKWebView 编辑器）
//  用 Ubuntu 上的 clang + ld64.lld + iPhoneOS SDK 交叉编译，产出未签名 ipa。
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const kRecentsKey = @"HtmlPadRecentsV1";
static NSString *const kOpenURLNotification = @"HtmlPadOpenURL";

#pragma mark - 小工具

/// 把 NSString 变成可安全嵌入 JS 源码的字符串字面量
static NSString *JSStringLiteral(NSString *s) {
    if (s == nil) {
        return @"\"\"";
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[s] options:0 error:NULL];
    if (data == nil) {
        return @"\"\"";
    }
    NSString *arrayLiteral = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (arrayLiteral.length < 2) {
        return @"\"\"";
    }
    return [arrayLiteral substringWithRange:NSMakeRange(1, arrayLiteral.length - 2)];
}

static NSStringEncoding GB18030Encoding(void) {
    return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
}

static NSString *DecodeText(NSData *data) {
    if (data.length == 0) {
        return @"";
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text == nil) {
        text = [[NSString alloc] initWithData:data encoding:GB18030Encoding()];
    }
    if (text == nil) {
        text = [[NSString alloc] initWithData:data encoding:NSUTF16StringEncoding];
    }
    if (text == nil) {
        text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    }
    return text;
}

#pragma mark - 脚本消息弱引用代理（避免 WKUserContentController 强引用 VC）

@class EditorViewController;

@interface ScriptProxy : NSObject <WKScriptMessageHandler>
@property (nonatomic, weak) EditorViewController *target;
@end

@implementation ScriptProxy

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    [self.target userContentController:userContentController didReceiveScriptMessage:message];
}

@end

#pragma mark - 预览页

@interface PreviewViewController : UIViewController
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation PreviewViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = self.url.lastPathComponent ?: @"预览";

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                      target:self
                                                      action:@selector(closeTapped)];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(reloadTapped)];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;

    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.webView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self loadPage];
}

- (void)loadPage {
    if (self.url == nil) {
        return;
    }
    NSURL *directory = [self.url URLByDeletingLastPathComponent];
    BOOL scoped = [directory startAccessingSecurityScopedResource];
    [self.webView loadFileURL:self.url allowingReadAccessToURL:directory];
    if (scoped) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [directory stopAccessingSecurityScopedResource];
        });
    }
}

- (void)reloadTapped {
    [self loadPage];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - 主编辑页

@interface EditorViewController : UIViewController <WKScriptMessageHandler, WKNavigationDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIBarButtonItem *moreButton;
@property (nonatomic, strong) UIBarButtonItem *shareButton;
@property (nonatomic, strong) ScriptProxy *proxy;
@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, assign) BOOL dirty;
@property (nonatomic, assign) BOOL ready;
@property (nonatomic, copy) NSString *pendingText;
@end

@implementation EditorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.fileName = @"未命名.html";
    [self updateTitle];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;

    self.proxy = [[ScriptProxy alloc] init];
    self.proxy.target = self;
    [config.userContentController addScriptMessageHandler:(id<WKScriptMessageHandler>)self.proxy
                                                     name:@"bridge"];

    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.navigationDelegate = self;
    self.webView.opaque = NO;
    self.webView.backgroundColor = [UIColor clearColor];
    self.webView.scrollView.backgroundColor = [UIColor clearColor];
    self.webView.scrollView.bounces = NO;
    self.webView.scrollView.alwaysBounceVertical = NO;
    self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.webView];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [UIFont systemFontOfSize:10];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.text = @"点左上角「打开」选择 HTML 文件";
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.statusLabel.topAnchor],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.statusLabel.heightAnchor constraintEqualToConstant:22.0],
    ]];

    [self buildBarButtons];
    [self loadEditorPage];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidEnterBackground)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleOpenURLNotification:)
                                                 name:kOpenURLNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildBarButtons {
    UIBarButtonItem *open = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder"]
                                                            style:UIBarButtonItemStylePlain
                                                           target:self
                                                           action:@selector(openTapped)];
    UIBarButtonItem *newDoc = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"doc.badge.plus"]
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(newDocument)];
    self.navigationItem.leftBarButtonItems = @[open, newDoc];

    UIBarButtonItem *preview = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"eye"]
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(previewTapped)];
    UIBarButtonItem *save = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"tray.and.arrow.down"]
                                                            style:UIBarButtonItemStylePlain
                                                           target:self
                                                           action:@selector(saveTapped)];
    self.shareButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                                         style:UIBarButtonItemStylePlain
                                                        target:self
                                                        action:@selector(shareTapped)];
    self.moreButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                                                       style:UIBarButtonItemStylePlain
                                                      target:self
                                                      action:@selector(moreTapped)];
    self.navigationItem.rightBarButtonItems = @[self.moreButton, save, preview, self.shareButton];
}

- (void)loadEditorPage {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"editor" ofType:@"html"];
    if (path.length) {
        NSURL *url = [NSURL fileURLWithPath:path];
        [self.webView loadFileURL:url allowingReadAccessToURL:[url URLByDeletingLastPathComponent]];
    } else {
        [self.webView loadHTMLString:@"<h3>缺少 editor.html</h3>" baseURL:nil];
    }
}

#pragma mark - 界面状态

- (void)updateTitle {
    self.title = [NSString stringWithFormat:@"%@%@", self.fileName, self.dirty ? @" ●" : @""];
}

- (void)setStatus:(NSString *)text {
    self.statusLabel.text = text;
}

#pragma mark - 与编辑器通信

- (void)setEditorText:(NSString *)text {
    if (!self.ready) {
        self.pendingText = text;
        return;
    }
    NSString *js = [NSString stringWithFormat:@"window.editor.setText(%@);", JSStringLiteral(text)];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)fetchText:(void (^)(NSString *text))completion {
    if (!self.ready) {
        completion(@"");
        return;
    }
    [self.webView evaluateJavaScript:@"window.editor.getText()"
                   completionHandler:^(id result, NSError *error) {
        NSString *text = [result isKindOfClass:[NSString class]] ? (NSString *)result : @"";
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(text);
        });
    }];
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.body isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *body = (NSDictionary *)message.body;
    NSString *type = body[@"type"];
    if (![type isKindOfClass:[NSString class]]) {
        return;
    }

    if ([type isEqualToString:@"ready"]) {
        self.ready = YES;
        if (self.pendingText) {
            NSString *text = self.pendingText;
            self.pendingText = nil;
            [self setEditorText:text];
        }
    } else if ([type isEqualToString:@"change"]) {
        BOOL wasDirty = self.dirty;
        self.dirty = YES;
        NSNumber *length = body[@"length"];
        if ([length isKindOfClass:[NSNumber class]]) {
            [self setStatus:[NSString stringWithFormat:@"%@ · %@ 字符", self.fileName, length]];
        }
        if (!wasDirty) {
            [self updateTitle];
        }
    } else if ([type isEqualToString:@"save"]) {
        [self saveTapped];
    }
}

#pragma mark - 打开文件

- (void)openTapped {
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    UTType *html = [UTType typeWithIdentifier:@"public.html"];
    if (html) {
        [types addObject:html];
    }
    NSArray *extensions = @[@"html", @"htm", @"xhtml", @"shtml", @"css", @"js", @"mjs",
                            @"json", @"txt", @"md", @"markdown", @"xml", @"svg", @"vue", @"php"];
    for (NSString *ext in extensions) {
        UTType *type = [UTType typeWithFilenameExtension:ext];
        if (type && ![types containsObject:type]) {
            [types addObject:type];
        }
    }
    if (types.count == 0) {
        return;
    }

    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [self loadFileAtURL:urls.firstObject];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
}

- (void)loadFileAtURL:(NSURL *)url {
    if (url == nil) {
        return;
    }

    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&error];
    NSData *bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
                     includingResourceValuesForKeys:nil
                                      relativeToURL:nil
                                              error:NULL];
    if (scoped) {
        [url stopAccessingSecurityScopedResource];
    }

    if (data == nil) {
        [self setStatus:[NSString stringWithFormat:@"打开失败：%@", error.localizedDescription ?: @"读不到文件"]];
        return;
    }

    NSString *text = DecodeText(data);
    if (text == nil) {
        [self setStatus:@"打开失败：无法识别文件编码"];
        return;
    }

    self.fileURL = url;
    self.fileName = url.lastPathComponent ?: @"未命名.html";
    self.dirty = NO;
    [self setEditorText:text];
    [self addRecentURL:url bookmark:bookmark];
    [self updateTitle];

    if ([url.path rangeOfString:@"/Inbox/"].location != NSNotFound) {
        [self setStatus:@"已打开其他 App 送来的副本，改完请用「导出 / 分享」发回去"];
    } else {
        [self setStatus:[NSString stringWithFormat:@"已打开 %@ · %lu 字符",
                          self.fileName, (unsigned long)text.length]];
    }
}

- (void)newDocument {
    NSString *template =
        @"<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head>\n  <meta charset=\"utf-8\">\n"
         "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
         "  <title>新页面</title>\n  <style>\n"
         "    body { margin: 0; padding: 24px; font-family: -apple-system, \"PingFang SC\", sans-serif; line-height: 1.75; }\n"
         "  </style>\n</head>\n<body>\n  <h1>新页面</h1>\n  <p>开始编辑吧。</p>\n</body>\n</html>\n";
    self.fileURL = nil;
    self.fileName = @"未命名.html";
    self.dirty = NO;
    [self setEditorText:template];
    [self updateTitle];
    [self setStatus:@"已新建空白页面，记得「另存为」"];
}

- (void)handleOpenURLNotification:(NSNotification *)notification {
    id object = notification.object;
    if ([object isKindOfClass:[NSURL class]]) {
        NSURL *url = (NSURL *)object;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self loadFileAtURL:url];
        });
    }
}

- (void)reloadTapped {
    if (self.fileURL) {
        [self loadFileAtURL:self.fileURL];
    }
}

#pragma mark - 保存

- (void)saveTapped {
    if (self.fileURL == nil) {
        [self presentSaveAs];
        return;
    }
    [self saveToCurrentFileWithCompletion:nil];
}

- (void)saveToCurrentFileWithCompletion:(void (^)(BOOL ok))completion {
    NSURL *url = self.fileURL;
    if (url == nil) {
        if (completion) {
            completion(NO);
        }
        return;
    }
    [self fetchText:^(NSString *text) {
        BOOL scoped = [url startAccessingSecurityScopedResource];
        NSError *error = nil;
        BOOL ok = [text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (!ok) {
            ok = [text writeToURL:url atomically:NO encoding:NSUTF8StringEncoding error:&error];
        }
        if (scoped) {
            [url stopAccessingSecurityScopedResource];
        }
        if (ok) {
            self.dirty = NO;
            [self updateTitle];
            [self setStatus:[NSString stringWithFormat:@"已保存 · %@ 字符", @(text.length)]];
        } else {
            [self setStatus:[NSString stringWithFormat:@"保存失败：%@", error.localizedDescription ?: @"未知错误"]];
        }
        if (completion) {
            completion(ok);
        }
    }];
}

- (void)presentSaveAs {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"另存为"
                                                                  message:@"保存到「文件」App → 我的 iPhone → HTML 编辑"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = self.fileURL.lastPathComponent ?: self.fileName;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields.firstObject.text;
        [weakSelf saveAs:name];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveAs:(NSString *)rawName {
    NSString *name = [(rawName ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0) {
        name = @"未命名.html";
    }
    if (name.pathExtension.length == 0) {
        name = [name stringByAppendingString:@".html"];
    }

    NSURL *documents = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                               inDomains:NSUserDomainMask] firstObject];
    NSURL *target = [documents URLByAppendingPathComponent:name];
    int counter = 2;
    while ([[NSFileManager defaultManager] fileExistsAtPath:target.path]) {
        NSString *base = name.stringByDeletingPathExtension;
        NSString *extension = name.pathExtension;
        target = [documents URLByAppendingPathComponent:
                  [NSString stringWithFormat:@"%@-%d.%@", base, counter, extension]];
        counter += 1;
    }

    [self fetchText:^(NSString *text) {
        NSError *error = nil;
        BOOL ok = [text writeToURL:target atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (ok) {
            self.fileURL = target;
            self.fileName = target.lastPathComponent;
            self.dirty = NO;
            [self updateTitle];
            [self addRecentURL:target bookmark:nil];
            [self setStatus:[NSString stringWithFormat:@"已另存为 %@", self.fileName]];
        } else {
            [self setStatus:[NSString stringWithFormat:@"保存失败：%@", error.localizedDescription ?: @"未知错误"]];
        }
    }];
}

#pragma mark - 预览 / 分享

- (void)previewTapped {
    if (self.fileURL == nil) {
        [self presentSaveAs];
        return;
    }
    __weak typeof(self) weakSelf = self;
    void (^show)(void) = ^{
        PreviewViewController *preview = [[PreviewViewController alloc] init];
        preview.url = weakSelf.fileURL;
        UINavigationController *navigation =
            [[UINavigationController alloc] initWithRootViewController:preview];
        navigation.modalPresentationStyle = UIModalPresentationFullScreen;
        [weakSelf presentViewController:navigation animated:YES completion:nil];
    };

    if (self.dirty) {
        [self saveToCurrentFileWithCompletion:^(BOOL ok) {
            if (ok) {
                show();
            }
        }];
    } else {
        show();
    }
}

- (void)shareTapped {
    if (self.fileURL == nil) {
        [self presentSaveAs];
        return;
    }
    __weak typeof(self) weakSelf = self;
    void (^show)(void) = ^{
        UIActivityViewController *activity =
            [[UIActivityViewController alloc] initWithActivityItems:@[weakSelf.fileURL]
                                              applicationActivities:nil];
        activity.popoverPresentationController.barButtonItem = weakSelf.shareButton;
        [weakSelf presentViewController:activity animated:YES completion:nil];
    };

    if (self.dirty) {
        [self saveToCurrentFileWithCompletion:^(BOOL ok) {
            if (ok) {
                show();
            }
        }];
    } else {
        show();
    }
}

#pragma mark - 更多菜单

- (void)moreTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;

    [sheet addAction:[UIAlertAction actionWithTitle:@"新建空白页面" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf newDocument];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"另存为…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf presentSaveAs];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"插入代码片段…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf showSnippets];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"最近文件…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf showRecents];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"重新载入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf reloadTapped];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    sheet.popoverPresentationController.barButtonItem = self.moreButton;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)wrapSelectionWithBefore:(NSString *)before after:(NSString *)after {
    if (!self.ready) {
        return;
    }
    NSString *js = [NSString stringWithFormat:@"window.editor.wrap(%@, %@);",
                    JSStringLiteral(before), JSStringLiteral(after)];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)insertText:(NSString *)text {
    if (!self.ready) {
        return;
    }
    NSString *js = [NSString stringWithFormat:@"window.editor.insert(%@);", JSStringLiteral(text)];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)showSnippets {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"插入代码片段"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;

    NSArray<NSArray<NSString *> *> *items = @[
        @[@"标题 <h1>", @"<h1>", @"</h1>"],
        @[@"段落 <p>", @"<p>", @"</p>"],
        @[@"加粗 <strong>", @"<strong>", @"</strong>"],
        @[@"链接 <a>", @"<a href=\"https://example.com\">", @"</a>"],
        @[@"图片 <img>", @"<img src=\"\" alt=\"\">", @""],
        @[@"无序列表", @"<ul>\n  <li></li>\n  <li></li>\n</ul>\n", @""],
        @[@"表格", @"<table border=\"1\" cellpadding=\"6\" cellspacing=\"0\">\n  <tr><th>标题 1</th><th>标题 2</th></tr>\n  <tr><td>内容</td><td>内容</td></tr>\n</table>\n", @""],
        @[@"换行 <br>", @"<br>", @""],
        @[@"HTML 注释", @"<!-- ", @" -->"],
    ];

    for (NSArray<NSString *> *item in items) {
        NSString *title = item[0];
        NSString *before = item[1];
        NSString *after = item[2];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            if (after.length == 0) {
                [weakSelf insertText:before];
            } else {
                [weakSelf wrapSelectionWithBefore:before after:after];
            }
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    sheet.popoverPresentationController.barButtonItem = self.moreButton;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showRecents {
    NSArray<NSDictionary *> *items = [self recents];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"最近文件"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;

    if (items.count == 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"（暂无记录）" style:UIAlertActionStyleDefault handler:nil]];
    }
    int index = 0;
    for (NSDictionary *item in items) {
        if (index++ >= 8) {
            break;
        }
        NSString *name = item[@"name"] ?: @"?";
        [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [weakSelf openRecent:item];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    sheet.popoverPresentationController.barButtonItem = self.moreButton;
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - 最近文件存储

- (NSArray<NSDictionary *> *)recents {
    NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:kRecentsKey];
    return stored ?: @[];
}

- (void)addRecentURL:(NSURL *)url bookmark:(NSData *)bookmark {
    NSString *path = url.path ?: @"";
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *item in [self recents]) {
        if (![item[@"path"] isEqual:path]) {
            [list addObject:item];
        }
    }
    NSMutableDictionary *item = [NSMutableDictionary dictionary];
    item[@"path"] = path;
    item[@"name"] = url.lastPathComponent ?: @"?";
    if (bookmark) {
        item[@"bookmark"] = bookmark;
    }
    [list insertObject:item atIndex:0];
    while (list.count > 10) {
        [list removeLastObject];
    }
    [[NSUserDefaults standardUserDefaults] setObject:list forKey:kRecentsKey];
}

- (void)openRecent:(NSDictionary *)item {
    NSData *bookmark = item[@"bookmark"];
    if ([bookmark isKindOfClass:[NSData class]]) {
        BOOL stale = NO;
        NSURL *url = [NSURL URLByResolvingBookmarkData:bookmark
                                              options:0
                                        relativeToURL:nil
                                  bookmarkDataIsStale:&stale
                                                error:NULL];
        if (url) {
            [self loadFileAtURL:url];
            return;
        }
    }
    NSString *path = item[@"path"];
    if (path.length && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [self loadFileAtURL:[NSURL fileURLWithPath:path]];
    } else {
        [self setStatus:@"文件已不存在"];
    }
}

#pragma mark - 后台自动保存

- (void)appDidEnterBackground {
    if (self.dirty && self.fileURL) {
        [self saveToCurrentFileWithCompletion:nil];
    }
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
    EditorViewController *editor = [[EditorViewController alloc] init];
    UINavigationController *navigation =
        [[UINavigationController alloc] initWithRootViewController:editor];
    self.window.rootViewController = navigation;
    [self.window makeKeyAndVisible];
    return YES;
}

- (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    [[NSNotificationCenter defaultCenter] postNotificationName:kOpenURLNotification object:url];
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, @"AppDelegate");
    }
}
