// Copyright (c) 2009 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "CTBrowserFrameView.h"

#import <objc/runtime.h>
#import <Carbon/Carbon.h>

#import "scoped_nsautorelease_pool.h"
#import "CTBrowserWindow.h"

static const CGFloat kBrowserFrameViewPaintHeight = 60.0;
static const NSPoint kBrowserFrameViewPatternPhaseOffset = { -5, 3 };

static BOOL gCanDrawTitle = NO;
static BOOL gCanGetCornerRadius = NO;

@interface NSView (Swizzles)
- (void)drawRectOriginal:(NSRect)rect;
- (BOOL)_mouseInGroup:(NSButton*)widget;
- (void)updateTrackingAreas;
@end

// Undocumented APIs. They are really on NSGrayFrame rather than
// CTBrowserFrameView, but we call them from methods swizzled onto NSGrayFrame.
@interface CTBrowserFrameView (UndocumentedAPI)

- (float)roundedCornerRadius;
- (CGRect)_titlebarTitleRect;
- (void)_drawTitleStringIn:(struct CGRect)arg1 withColor:(id)color;

@end

@implementation CTBrowserFrameView

+ (void)load {
  // This is where we swizzle drawRect, and add in two methods that we
  // need. If any of these fail it shouldn't affect the functionality of the
  // others. If they all fail, we will lose window frame theming and
  // roll overs for our close widgets, but things should still function
  // correctly.
  ScopedNSAutoreleasePool pool;
  Class grayFrameClass = NSClassFromString(@"NSGrayFrame");
  DCHECK(grayFrameClass);
  if (!grayFrameClass) return;

  // Exchange draw rect
  Method m0 = class_getInstanceMethod([self class], @selector(drawRect:));
  DCHECK(m0);
  if (m0) {
    BOOL didAdd = class_addMethod(grayFrameClass,
                                  @selector(drawRectOriginal:),
                                  method_getImplementation(m0),
                                  method_getTypeEncoding(m0));
    DCHECK(didAdd);
    if (didAdd) {
      Method m1 = class_getInstanceMethod(grayFrameClass, @selector(drawRect:));
      Method m2 = class_getInstanceMethod(grayFrameClass,
                                          @selector(drawRectOriginal:));
      DCHECK(m1 && m2);
      if (m1 && m2) {
        method_exchangeImplementations(m1, m2);
      }
    }
  }

  // Add _mouseInGroup
  m0 = class_getInstanceMethod([self class], @selector(_mouseInGroup:));
  DCHECK(m0);
  if (m0) {
    BOOL didAdd = class_addMethod(grayFrameClass,
                                  @selector(_mouseInGroup:),
                                  method_getImplementation(m0),
                                  method_getTypeEncoding(m0));
    DCHECK(didAdd);
  }
  // Add updateTrackingArea
  m0 = class_getInstanceMethod([self class], @selector(updateTrackingAreas));
  DCHECK(m0);
  if (m0) {
    BOOL didAdd = class_addMethod(grayFrameClass,
                                  @selector(updateTrackingAreas),
                                  method_getImplementation(m0),
                                  method_getTypeEncoding(m0));
    DCHECK(didAdd);
  }

  gCanDrawTitle =
      [grayFrameClass
        instancesRespondToSelector:@selector(_titlebarTitleRect)] &&
      [grayFrameClass
        instancesRespondToSelector:@selector(_drawTitleStringIn:withColor:)];
  gCanGetCornerRadius =
      [grayFrameClass
        instancesRespondToSelector:@selector(roundedCornerRadius)];
}

- (id)initWithFrame:(NSRect)frame {
  // This class is not for instantiating.
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (id)initWithCoder:(NSCoder*)coder {
  // This class is not for instantiating.
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

// Here is our custom drawing for our frame.
- (void)drawRect:(NSRect)rect {
  // If this isn't the window class we expect, then pass it on to the
  // original implementation.
  if (![[self window] isKindOfClass:[CTBrowserWindow class]]) {
    [self drawRectOriginal:rect];
    return;
  }

  // WARNING: There is an obvious optimization opportunity here that you DO NOT
  // want to take. To save painting cycles, you might think it would be a good
  // idea to call out to -drawRectOriginal: only if no theme were drawn. In
  // reality, however, if you fail to call -drawRectOriginal:, or if you call it
  // after a clipping path is set, the rounded corners at the top of the window
  // will not draw properly. Do not try to be smart here.

  // Only paint the top of the window.
  NSWindow* window = [self window];
  NSRect windowRect = [self convertRect:[window frame] fromView:nil];
  windowRect.origin = NSMakePoint(0, 0);

  NSRect paintRect = windowRect;
  paintRect.origin.y = NSMaxY(paintRect) - kBrowserFrameViewPaintHeight;
  paintRect.size.height = kBrowserFrameViewPaintHeight;
  rect = NSIntersectionRect(paintRect, rect);
  [self drawRectOriginal:rect];

  // Set up our clip.
  float cornerRadius = 4.0;
  if (gCanGetCornerRadius)
    cornerRadius = [self roundedCornerRadius];
  [[NSBezierPath bezierPathWithRoundedRect:windowRect
                                   xRadius:cornerRadius
                                   yRadius:cornerRadius] addClip];
  [[NSBezierPath bezierPathWithRect:rect] addClip];

  // -- removed: themed window drawing routines --
}

// Check to see if the mouse is currently in one of our window widgets.
- (BOOL)_mouseInGroup:(NSButton*)widget {
  BOOL mouseInGroup = NO;
  NSWindow *window = [self window];
  if ([window isKindOfClass:[CTBrowserWindow class]]) {
    mouseInGroup = [static_cast<CTBrowserWindow*>(window) mouseInGroup:widget];
  } else if ([super respondsToSelector:@selector(_mouseInGroup:)]) {
    mouseInGroup = [super _mouseInGroup:widget];
  }
  return mouseInGroup;
}

// Let our window handle updating the window widget tracking area.
- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  NSWindow *window = [self window];
  if ([window isKindOfClass:[CTBrowserWindow class]]) {
    [static_cast<CTBrowserWindow*>(window) updateTrackingAreas];
  }
}

@end