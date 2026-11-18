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
// (-1 or missing = leave, 0 = the engine's way, 1 to 5 = see chromia_present).
// Answered with tune_ok.txt.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreVideo/CoreVideo.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
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
// drawing after each present waits about 15 ms for the layer's picture to come
// back, so every other refresh is missed (80 holds). That is what two buffers
// give: the one just presented is on its way to the screen for two refreshes,
// and the other is still showing, so there is nothing to draw into.
//
// The ways the game can ask for instead (it tries them and measures what it
// gets, scripts/HighHzCheck.gd; mode 0 is the engine's own call, untouched):
//   1: presentRenderbuffer:afterMinimumDuration:  (one refresh of the asked rate)
//   2: presentRenderbuffer:atTime:                (the screen timer's next refresh)
//   3: the engine's call, inside a Core Animation transaction
//      (CAEAGLLayer.presentsWithTransaction)
//   4: three buffers of our own. The engine's framebuffer gets a texture of
//      ours as its colour buffer instead of the layer's; a finished frame is
//      put on a plain layer over the engine's (CALayer.contents takes the
//      IOSurface behind the texture) and the engine draws the next frame into
//      the next of the three. The layer's own present is never called, so
//      nothing waits for it.
//   5: as 4, waiting for the graphics chip to finish the frame before it is
//      shown (glFinish instead of glFlush), in case 4 shows half-drawn frames.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static int present_mode = 0;
static double present_step = 1.0 / 120.0;
static BOOL present_hooked = NO;
static BOOL in_present = NO;
static BOOL (*orig_present)(id, SEL, NSUInteger) = NULL;
static __weak UIView *tuned_view = nil;

// the engine's OpenGL layer (GodotOpenGLLayer, a sublayer of its view's layer)
static CALayer *godot_gl_layer(void) {
	UIView *v = tuned_view;
	if (v == nil) return nil;
	CALayer *l = nil;
	@try { l = [v valueForKey:@"renderingLayer"]; } @catch (NSException *e) { l = nil; }
	return l;
}

// its framebuffer and colour renderbuffer (GodotOpenGLLayer's own variables)
static BOOL layer_gl_names(CALayer *l, GLuint *fbo, GLuint *rb) {
	Ivar a = class_getInstanceVariable(object_getClass(l), "viewFramebuffer");
	Ivar b = class_getInstanceVariable(object_getClass(l), "viewRenderbuffer");
	if (a == NULL || b == NULL) return NO;
	const uint8_t *base = (const uint8_t *)(__bridge void *)l;
	*fbo = *(const GLuint *)(base + ivar_getOffset(a));
	*rb = *(const GLuint *)(base + ivar_getOffset(b));
	return *fbo != 0 && *rb != 0;
}

// --- ways 4 and 5: three buffers of our own ---
#define SURF_N 3
typedef struct {
	CVPixelBufferRef pb;
	CVOpenGLESTextureRef tex;
} Surf;
static Surf surf[SURF_N];
static CVOpenGLESTextureCacheRef surf_cache = NULL;
static int surf_w = 0, surf_h = 0, surf_cur = 0;
// 0: not in use, 1: the engine draws into ours, 2: the engine's buffer is back, our layer still up for a few frames
static int surf_state = 0;
static int surf_leave_frames = 0;
static CALayer *surf_layer = nil;
static NSString *surf_note = @"";
static long surf_shown = 0;
static int surf_remakes = 0; // in a row, without one frame shown from ours

static void surf_free(void) {
	for (int i = 0; i < SURF_N; i++) {
		if (surf[i].tex != NULL) CFRelease(surf[i].tex);
		if (surf[i].pb != NULL) CVPixelBufferRelease(surf[i].pb);
		surf[i].tex = NULL;
		surf[i].pb = NULL;
	}
	if (surf_cache != NULL) {
		CVOpenGLESTextureCacheFlush(surf_cache, 0);
		CFRelease(surf_cache);
		surf_cache = NULL;
	}
	surf_w = 0;
	surf_h = 0;
	surf_cur = 0;
}

static BOOL surf_make(EAGLContext *ctx, int w, int h) {
	surf_free();
	if (CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, ctx, NULL, &surf_cache) != kCVReturnSuccess) return NO;
	NSDictionary *attrs = @{
		(id)kCVPixelBufferIOSurfacePropertiesKey : @{},
		(id)kCVPixelBufferOpenGLESCompatibilityKey : @YES,
	};
	GLint old_tex = 0;
	glGetIntegerv(GL_TEXTURE_BINDING_2D, &old_tex);
	BOOL ok = YES;
	for (int i = 0; i < SURF_N; i++) {
		if (CVPixelBufferCreate(kCFAllocatorDefault, (size_t)w, (size_t)h, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attrs, &surf[i].pb) != kCVReturnSuccess
				|| CVPixelBufferGetIOSurface(surf[i].pb) == NULL
				|| CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, surf_cache, surf[i].pb, NULL, GL_TEXTURE_2D, GL_RGBA, w, h, GL_BGRA_EXT, GL_UNSIGNED_BYTE, 0, &surf[i].tex) != kCVReturnSuccess) {
			ok = NO;
			break;
		}
		glBindTexture(GL_TEXTURE_2D, CVOpenGLESTextureGetName(surf[i].tex));
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	}
	glBindTexture(GL_TEXTURE_2D, (GLuint)old_tex);
	if (!ok) {
		surf_free();
		return NO;
	}
	surf_w = w;
	surf_h = h;
	surf_cur = 0;
	return YES;
}

// puts buffer i (or nothing: -1) on our layer over the engine's
static void surf_show(int i, CALayer *gl) {
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	if (surf_layer == nil) {
		surf_layer = [CALayer layer];
		surf_layer.opaque = YES;
		surf_layer.contentsGravity = kCAGravityResize;
		// (OpenGL's first row of a picture is the bottom one)
		surf_layer.affineTransform = CGAffineTransformMakeScale(1.0, -1.0);
	}
	if (surf_layer.superlayer != gl) [gl addSublayer:surf_layer];
	CGRect b = gl.bounds;
	if (!CGSizeEqualToSize(surf_layer.bounds.size, b.size)) {
		surf_layer.bounds = CGRectMake(0, 0, b.size.width, b.size.height);
		surf_layer.position = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b));
	}
	surf_layer.contents = i >= 0 ? (__bridge id)CVPixelBufferGetIOSurface(surf[i].pb) : nil;
	[CATransaction commit];
}

static void surf_remove_layer(void) {
	if (surf_layer == nil) return;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	surf_layer.contents = nil;
	[surf_layer removeFromSuperlayer];
	[CATransaction commit];
	surf_layer = nil;
}

// One frame with ways 4 / 5 (wanted), or on the way out of them (not wanted).
// NO: nothing was shown and nothing is left changed; the caller presents as the engine does.
static BOOL surf_present(EAGLContext *ctx, SEL sel, NSUInteger target, BOOL wanted, BOOL finish) {
	CALayer *gl = godot_gl_layer();
	GLuint fbo = 0, rb = 0;
	GLint bound_rb = 0, w = 0, h = 0, old_fbo = 0, type = 0, name = 0;
	if (gl == nil || !layer_gl_names(gl, &fbo, &rb)) {
		surf_note = @"no layer";
		return NO;
	}
	glGetIntegerv(GL_RENDERBUFFER_BINDING, &bound_rb);
	if ((GLuint)bound_rb != rb) {
		surf_note = @"other buffer";
		return NO;
	}
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &w);
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &h);
	glGetIntegerv(GL_FRAMEBUFFER_BINDING, &old_fbo);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, &type);
	glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME, &name);
	BOOL ours = surf_state == 1 && type == GL_TEXTURE && surf[surf_cur].tex != NULL && (GLuint)name == CVOpenGLESTextureGetName(surf[surf_cur].tex);
	BOOL ok = YES;
	if (ours) {
		// this frame is in our buffer. Nothing see-through in it (the engine's layer is opaque too)
		GLboolean mask[4] = { GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE };
		GLfloat cc[4] = { 0, 0, 0, 1 };
		glGetBooleanv(GL_COLOR_WRITEMASK, mask);
		glGetFloatv(GL_COLOR_CLEAR_VALUE, cc);
		GLboolean scissor = glIsEnabled(GL_SCISSOR_TEST);
		if (scissor) glDisable(GL_SCISSOR_TEST);
		glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_TRUE);
		glClearColor(0, 0, 0, 1);
		glClear(GL_COLOR_BUFFER_BIT);
		glColorMask(mask[0], mask[1], mask[2], mask[3]);
		glClearColor(cc[0], cc[1], cc[2], cc[3]);
		if (scissor) glEnable(GL_SCISSOR_TEST);
		if (finish) glFinish(); else glFlush();
		surf_show(surf_cur, gl);
		surf_shown++;
		surf_remakes = 0;
		if (wanted && w == surf_w && h == surf_h) {
			surf_cur = (surf_cur + 1) % SURF_N;
			glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, CVOpenGLESTextureGetName(surf[surf_cur].tex), 0);
		} else {
			// leaving: the engine's own buffer again; our layer stays up until the engine's has a new picture
			glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rb);
			surf_state = 2;
			surf_leave_frames = 0;
		}
	} else {
		// This frame is in the engine's buffer: the first frame this way, the engine
		// made its buffers anew (the screen turned, the app came back), or the way out.
		if (type != GL_RENDERBUFFER) glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rb);
		glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)old_fbo);
		ok = orig_present(ctx, sel, target);
		glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		if (wanted) {
			if (surf_layer != nil) surf_show(-1, gl);
			// (an engine that keeps taking its buffer back: not for this way)
			BOOL again = ++surf_remakes > 8;
			BOOL made = !again && w > 0 && h > 0 && surf_make(ctx, w, h);
			if (again) {
				surf_note = @"buffers kept being replaced";
			} else if (made) {
				glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, CVOpenGLESTextureGetName(surf[0].tex), 0);
				if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
					glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rb);
					made = NO;
					surf_note = @"framebuffer incomplete";
				}
			} else {
				surf_note = @"no buffers";
			}
			if (made) {
				surf_state = 1;
				surf_note = [NSString stringWithFormat:@"%d x %d", w, h];
			} else {
				surf_free();
				surf_remove_layer();
				surf_state = 0;
				present_mode = 0;
			}
		} else {
			surf_leave_frames++;
			if (surf_state != 2 || surf_leave_frames >= 3) {
				surf_remove_layer();
				surf_free();
				surf_state = 0;
			}
		}
	}
	glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)old_fbo);
	return ok;
}

static BOOL chromia_present(id self, SEL _cmd, NSUInteger target) {
	// (as it was: mode 0, another thread, or one of the presents below calling this one)
	if ((present_mode == 0 && surf_state == 0) || in_present || !NSThread.isMainThread) return orig_present(self, _cmd, target);
	in_present = YES;
	BOOL ok = NO;
	@try {
		EAGLContext *ctx = (EAGLContext *)self;
		if (present_mode >= 4 || surf_state != 0) {
			if (!surf_present(ctx, _cmd, target, present_mode >= 4, present_mode == 5)) {
				if (present_mode >= 4) present_mode = 0;
				ok = orig_present(self, _cmd, target);
			} else {
				ok = YES;
			}
		} else if (present_mode == 3) {
			[CATransaction begin];
			ok = orig_present(self, _cmd, target);
			[CATransaction commit];
		} else if (present_mode == 2) {
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

// way 3: the engine's present goes out with the Core Animation transaction
static void set_with_transaction(BOOL on) {
	CALayer *gl = godot_gl_layer();
	if ([gl isKindOfClass:[CAEAGLLayer class]]) {
		CAEAGLLayer *e = (CAEAGLLayer *)gl;
		if (e.presentsWithTransaction != on) e.presentsWithTransaction = on;
	}
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
		// (ways 4 / 5 are taken down by the next frame, where OpenGL can be used)
		if (present == 0) {
			present_mode = 0;
		} else if (present <= 5 && hook_present()) {
			present_mode = (int)present;
		} else {
			present_mode = 0;
		}
		if (present_mode >= 4) {
			surf_note = @"";
			surf_remakes = 0;
		}
		set_with_transaction(present_mode == 3);
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
	// (helper 3: can change how frames are presented, and says the screen's top
	// rate here too. Helper 4: ways 3 to 5, and what became of our own buffers)
	[report appendFormat:@"helper 4\npresent %d\nscreen %ld\n", present_mode, (long)UIScreen.mainScreen.maximumFramesPerSecond];
	[report appendFormat:@"buffers %d %ld %@\n", surf_state, surf_shown, surf_note.length > 0 ? surf_note : @"-"];
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
