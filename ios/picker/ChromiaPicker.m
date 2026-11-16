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
//
// tune.txt (Settings > No Touch Delay / 120 Hz):  frames per second (0 = leave),
// touch delay in seconds (-1 = leave), how frames are handed to the screen
// (-1 or missing = leave, 0 = the engine's way, 1 / 2 = see chromia_present).
// Answered with tune_ok.txt.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGL.h>
#import <objc/runtime.h>

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
	[self finishWithPaths:[NSArray array] ok:NO];
}

- (void)show:(BOOL)multi {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	UIDocumentPickerViewController *c;
	if ([self.mode isEqualToString:@"export"]) {
		c = [[UIDocumentPickerViewController alloc] initWithURL:[NSURL fileURLWithPath:self.target] inMode:UIDocumentPickerModeExportToService];
	} else {
		c = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item"] inMode:UIDocumentPickerModeImport];
		c.allowsMultipleSelection = multi; // iOS 11+, and Chromia needs 12
	}
#pragma clang diagnostic pop
	c.delegate = self;
	c.modalPresentationStyle = UIModalPresentationFormSheet;
	self.controller = c;
	UIViewController *top = top_controller();
	if (top == nil) {
		[self finishWithPaths:[NSArray array] ok:NO];
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

// Godot's view (GodotView): the view under the root view controller that has
// a display link.
static UIView *godot_view(void) {
	UIWindow *win = nil;
	for (UIWindow *w in UIApplication.sharedApplication.windows) {
		if (w.isKeyWindow) { win = w; break; }
	}
	if (win == nil) win = UIApplication.sharedApplication.windows.firstObject;
	NSMutableArray<UIView *> *todo = [NSMutableArray array];
	if (win.rootViewController.view) [todo addObject:win.rootViewController.view];
	while (todo.count > 0) {
		UIView *v = todo.firstObject;
		[todo removeObjectAtIndex:0];
		if ([v respondsToSelector:NSSelectorFromString(@"setRenderingInterval:")]) return v;
		[todo addObjectsFromArray:v.subviews];
	}
	return nil;
}

// --- how a finished frame is handed to the screen --------------------------------
// The engine draws with OpenGL ES and shows each frame with
// -[EAGLContext presentRenderbuffer:]. Asked for 120 frames a second that way,
// an iPhone settles at 60: the screen timer keeps firing at 120, but the first
// drawing after each present waits for the layer's picture to come back, long
// enough to miss every other refresh (80 holds). EAGL has two other presents,
// both made for 120 Hz screens, that say when the frame is meant to show:
//   1: presentRenderbuffer:afterMinimumDuration:  (one refresh of the asked rate)
//   2: presentRenderbuffer:atTime:                (the screen timer's next refresh)
// The game tries them and measures what it gets (scripts/HighHzCheck.gd);
// mode 0 is the engine's own call, untouched.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static int present_mode = 0;
static double present_step = 1.0 / 120.0;
static BOOL present_hooked = NO;
static BOOL in_present = NO;
static BOOL (*orig_present)(id, SEL, NSUInteger) = NULL;
static __weak UIView *tuned_view = nil;

static BOOL chromia_present(id self, SEL _cmd, NSUInteger target) {
	// (as it was: mode 0, another thread, or one of the presents below calling this one)
	if (present_mode == 0 || in_present || !NSThread.isMainThread) return orig_present(self, _cmd, target);
	in_present = YES;
	BOOL ok = NO;
	@try {
		EAGLContext *ctx = (EAGLContext *)self;
		if (present_mode == 2) {
			CADisplayLink *link = nil;
			UIView *v = tuned_view;
			if (v != nil) link = [v valueForKey:@"displayLink"];
			ok = [ctx presentRenderbuffer:target atTime:(link != nil ? link.targetTimestamp : CACurrentMediaTime())];
		} else {
			ok = [ctx presentRenderbuffer:target afterMinimumDuration:present_step];
		}
	} @catch (NSException *e) {
		present_mode = 0;
		ok = orig_present(self, _cmd, target);
	}
	in_present = NO;
	return ok;
}

static BOOL hook_present(void) {
	if (present_hooked) return YES;
	Class c = [EAGLContext class];
	if (c == Nil || ![c instancesRespondToSelector:@selector(presentRenderbuffer:afterMinimumDuration:)]
			|| ![c instancesRespondToSelector:@selector(presentRenderbuffer:atTime:)]) return NO;
	Method m = class_getInstanceMethod(c, @selector(presentRenderbuffer:));
	if (m == NULL) return NO;
	orig_present = (BOOL (*)(id, SEL, NSUInteger))method_getImplementation(m);
	if (orig_present == NULL) return NO;
	method_setImplementation(m, (IMP)chromia_present);
	present_hooked = YES;
	return YES;
}
#pragma clang diagnostic pop

static void handle_tune(void) {
	NSFileManager *fm = NSFileManager.defaultManager;
	NSString *path = [picker_dir() stringByAppendingPathComponent:@"tune.txt"];
	NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
	if (text == nil) return;
	[fm removeItemAtPath:path error:nil];
	NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
	NSInteger fps = lines.count > 0 ? lines[0].integerValue : 0;
	double delay = lines.count > 1 ? lines[1].doubleValue : -1;
	NSInteger present = (lines.count > 2 && lines[2].length > 0) ? lines[2].integerValue : -1;
	NSMutableString *report = [NSMutableString string];
	UIView *view = godot_view();
	if (view != nil) tuned_view = view;
	if (present >= 0) {
		// (the engine's own call stays as it is until another way is asked for)
		if (present == 0) {
			present_mode = 0;
		} else if (present <= 2 && hook_present()) {
			present_mode = (int)present;
		} else {
			present_mode = 0;
		}
	}
	if (view == nil) {
		[report appendString:@"no view\n"];
	} else {
		if (fps > 0) {
			NSInteger maxfps = UIScreen.mainScreen.maximumFramesPerSecond;
			if (fps > maxfps) fps = maxfps;
			present_step = 1.0 / (double)fps;
			// Godot restarts its display link with this rate (also after the app comes back)
			[view setValue:@(1.0 / (double)fps) forKey:@"renderingInterval"];
			CADisplayLink *link = nil;
			@try { link = [view valueForKey:@"displayLink"]; } @catch (NSException *e) { link = nil; }
			if (link != nil) {
				link.preferredFramesPerSecond = fps;
				// iOS 15+ (ProMotion screens)
				if ([link respondsToSelector:@selector(setPreferredFrameRateRange:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
					CAFrameRateRange range;
					range.minimum = fps >= 80 ? 80 : (float)fps;
					range.maximum = (float)fps;
					range.preferred = (float)fps;
					link.preferredFrameRateRange = range;
#pragma clang diagnostic pop
				}
			}
			[report appendFormat:@"fps %ld (screen max %ld)\n", (long)fps, (long)maxfps];
		}
		if (delay >= 0) {
			// Godot holds each new touch back for input_devices/pointing/ios/touch_delay
			// (0.15 s) in a gesture recognizer on its view
			for (UIGestureRecognizer *g in view.gestureRecognizers) {
				if ([g respondsToSelector:NSSelectorFromString(@"setDelayTimeInterval:")]) {
					[g setValue:@(delay) forKey:@"delayTimeInterval"];
					[report appendFormat:@"touch delay %.3f\n", delay];
				}
			}
		}
	}
	// What decides the refresh rate besides the game (for its 120 Hz check,
	// scripts/HighHzCheck.gd): Low Power Mode holds an iPhone at 60 Hz, the app
	// needs CADisableMinimumFrameDurationOnPhone in its Info.plist, and the
	// rate iOS is really giving the display link right now.
	// (helper 3: can change how frames are presented, and says the screen's top rate here too)
	[report appendFormat:@"helper 3\npresent %d\nscreen %ld\n", present_mode, (long)UIScreen.mainScreen.maximumFramesPerSecond];
	[report appendFormat:@"lowpower %d\n", (int)NSProcessInfo.processInfo.lowPowerModeEnabled];
	id plist_key = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CADisableMinimumFrameDurationOnPhone"];
	[report appendFormat:@"plist120 %d\n", (int)[plist_key boolValue]];
	if (view != nil) {
		CADisplayLink *now_link = nil;
		@try { now_link = [view valueForKey:@"displayLink"]; } @catch (NSException *e) { now_link = nil; }
		if (now_link != nil) {
			double step = now_link.targetTimestamp - now_link.timestamp;
			[report appendFormat:@"link %.1f asked %ld\n", step > 0.0001 ? 1.0 / step : 0.0, (long)now_link.preferredFramesPerSecond];
		}
	}
	[fm createDirectoryAtPath:picker_dir() withIntermediateDirectories:YES attributes:nil error:nil];
	[report writeToFile:[picker_dir() stringByAppendingPathComponent:@"tune_ok.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

__attribute__((visibility("default"))) void godot_gdnative_init(void *options) {
	if (NSThread.isMainThread) {
		handle_tune();
		handle_request();
	} else {
		dispatch_async(dispatch_get_main_queue(), ^{
			handle_tune();
			handle_request();
		});
	}
}

__attribute__((visibility("default"))) void godot_gdnative_terminate(void *options) {
}
