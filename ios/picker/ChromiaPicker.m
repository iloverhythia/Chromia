// Chromia's iPhone file picker: Apple's document picker (the same sheet other
// apps use to pick a file from iCloud Drive, On My iPhone, Downloads, ...)
// shown inside Chromia, and "Save to..." for exports.
//
// Built as ChromiaPicker.framework (.github/scripts/build_ios_picker.sh) and
// put into the .ipa's Frameworks folder. The game loads it through Godot's
// GDNative (scripts/IosFilePicker.gd); each GDNative.initialize() calls
// godot_gdnative_init below, which reads the request the game wrote to
// Documents/.chromia_picker/request.txt and answers in result.txt.
//
// request.txt lines:  open|export   multi (0/1)   destination folder or file to export
// result.txt lines:   ok|cancel     then one path per picked / saved file

#import <UIKit/UIKit.h>

static NSString *picker_dir(void) {
	NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
	return [docs stringByAppendingPathComponent:@".chromia_picker"];
}

static UIViewController *top_controller(void) {
	UIWindow *win = nil;
	for (UIWindow *w in UIApplication.sharedApplication.windows) {
		if (w.isKeyWindow) { win = w; break; }
	}
	if (win == nil) win = UIApplication.sharedApplication.windows.firstObject;
	UIViewController *vc = win.rootViewController;
	while (vc.presentedViewController != nil) vc = vc.presentedViewController;
	return vc;
}

@interface ChromiaPicker : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, copy) NSString *mode;
@property (nonatomic, copy) NSString *target;
@property (nonatomic, strong) UIDocumentPickerViewController *controller;
@end

static ChromiaPicker *active_picker = nil;

@implementation ChromiaPicker

- (void)finishWithPaths:(NSArray<NSString *> *)paths ok:(BOOL)ok {
	NSMutableString *out = [NSMutableString stringWithString:(ok ? @"ok\n" : @"cancel\n")];
	for (NSString *p in paths) {
		[out appendString:p];
		[out appendString:@"\n"];
	}
	NSFileManager *fm = NSFileManager.defaultManager;
	NSString *dir = picker_dir();
	[fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	NSString *result = [dir stringByAppendingPathComponent:@"result.txt"];
	NSString *tmp = [dir stringByAppendingPathComponent:@"result.tmp"];
	[out writeToFile:tmp atomically:YES encoding:NSUTF8StringEncoding error:nil];
	[fm removeItemAtPath:result error:nil];
	[fm moveItemAtPath:tmp toPath:result error:nil];
	self.controller.delegate = nil;
	self.controller = nil;
	active_picker = nil;
}

- (void)picked:(NSArray<NSURL *> *)urls {
	if ([self.mode isEqualToString:@"export"]) {
		NSMutableArray *names = [NSMutableArray array];
		for (NSURL *u in urls) [names addObject:u.lastPathComponent ?: @""];
		[self finishWithPaths:names ok:urls.count > 0];
		return;
	}
	NSFileManager *fm = NSFileManager.defaultManager;
	[fm createDirectoryAtPath:self.target withIntermediateDirectories:YES attributes:nil error:nil];
	NSMutableArray *paths = [NSMutableArray array];
	for (NSURL *u in urls) {
		BOOL scoped = [u startAccessingSecurityScopedResource];
		NSString *dst = [self.target stringByAppendingPathComponent:u.lastPathComponent];
		[fm removeItemAtPath:dst error:nil];
		NSError *err = nil;
		if ([fm copyItemAtURL:u toURL:[NSURL fileURLWithPath:dst] error:&err]) {
			[paths addObject:dst];
		} else {
			NSLog(@"[ChromiaPicker] couldn't copy %@: %@", u, err);
		}
		if (scoped) [u stopAccessingSecurityScopedResource];
	}
	[self finishWithPaths:paths ok:paths.count > 0];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	[self picked:urls];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
	[self picked:@[url]];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
	[self finishWithPaths:@[] ok:NO];
}

- (void)show:(BOOL)multi {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	UIDocumentPickerViewController *c;
	if ([self.mode isEqualToString:@"export"]) {
		c = [[UIDocumentPickerViewController alloc] initWithURL:[NSURL fileURLWithPath:self.target] inMode:UIDocumentPickerModeExportToService];
	} else {
		c = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item"] inMode:UIDocumentPickerModeImport];
		if (@available(iOS 11.0, *)) c.allowsMultipleSelection = multi;
	}
#pragma clang diagnostic pop
	c.delegate = self;
	c.modalPresentationStyle = UIModalPresentationFormSheet;
	self.controller = c;
	UIViewController *top = top_controller();
	if (top == nil) {
		[self finishWithPaths:@[] ok:NO];
		return;
	}
	[top presentViewController:c animated:YES completion:nil];
}

@end

static void handle_request(void) {
	NSFileManager *fm = NSFileManager.defaultManager;
	NSString *req = [picker_dir() stringByAppendingPathComponent:@"request.txt"];
	NSString *text = [NSString stringWithContentsOfFile:req encoding:NSUTF8StringEncoding error:nil];
	if (text == nil) return;
	[fm removeItemAtPath:req error:nil];
	NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
	if (lines.count < 3 || active_picker != nil) return;
	ChromiaPicker *p = [ChromiaPicker new];
	p.mode = lines[0];
	p.target = lines[2];
	active_picker = p;
	[p show:[lines[1] isEqualToString:@"1"]];
}

__attribute__((visibility("default"))) void godot_gdnative_init(void *options) {
	if (NSThread.isMainThread) {
		handle_request();
	} else {
		dispatch_async(dispatch_get_main_queue(), ^{ handle_request(); });
	}
}

__attribute__((visibility("default"))) void godot_gdnative_terminate(void *options) {
}
