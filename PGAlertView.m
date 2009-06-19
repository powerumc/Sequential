/* Copyright © 2007-2008, The Sequential Project
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the the Sequential Project nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE SEQUENTIAL PROJECT ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE SEQUENTIAL PROJECT BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */
#import "PGAlertView.h"

// Views
#import "PGBezelPanel.h"

// Other
#import "PGDelayedPerforming.h"
#import "PGGeometry.h"

// Categories
#import "NSBezierPathAdditions.h"
#import "NSColorAdditions.h"
#import "NSObjectAdditions.h"

#define PGAlertViewSize 100.0f
#define PGMarginSize 4.0

@interface PGAlertView (Private)

- (void)_updateCurrentGraphic;

@end

@interface PGCannotGoRightGraphic : PGAlertGraphic
@end
@interface PGCannotGoLeftGraphic : PGCannotGoRightGraphic
@end
@interface PGLoopedLeftGraphic : PGAlertGraphic
@end
@interface PGLoopedRightGraphic : PGLoopedLeftGraphic
@end

@implementation PGAlertView

#pragma mark Instance Methods

- (PGAlertGraphic *)currentGraphic
{
	return [[_currentGraphic retain] autorelease];
}
- (void)pushGraphic:(PGAlertGraphic *)aGraphic
        window:(NSWindow *)window
{
	NSParameterAssert(aGraphic);
	unsigned const i = [_graphicStack indexOfObject:aGraphic];
	if(0 == i) {
		[self PG_cancelPreviousPerformRequestsWithSelector:@selector(popGraphicIdenticalTo:) object:_currentGraphic];
	} else {
		[_graphicStack insertObject:aGraphic atIndex:0];
		[self _updateCurrentGraphic];
	}
	NSTimeInterval const fadeOutDelay = [_currentGraphic fadeOutDelay];
	if(fadeOutDelay >= 0.01) [self PG_performSelector:@selector(popGraphicIdenticalTo:) withObject:_currentGraphic fireDate:nil interval:-fadeOutDelay options:PGCompareArgumentPointer];
	if(window && [[self window] respondsToSelector:@selector(displayOverWindow:)]) [(PGBezelPanel *)[self window] displayOverWindow:window];
}
- (void)popGraphic:(PGAlertGraphic *)aGraphic
{
	NSParameterAssert(aGraphic);
	unsigned const i = [_graphicStack indexOfObject:aGraphic];
	if(NSNotFound == i) return;
	[_graphicStack removeObjectAtIndex:i];
	[self _updateCurrentGraphic];
}
- (void)popGraphicIdenticalTo:(PGAlertGraphic *)aGraphic
{
	NSParameterAssert(aGraphic);
	unsigned const i = [_graphicStack indexOfObjectIdenticalTo:aGraphic];
	if(NSNotFound == i) return;
	[_graphicStack removeObjectAtIndex:i];
	[self _updateCurrentGraphic];
}
- (void)popGraphicsOfType:(PGAlertGraphicType)type
{
	PGAlertGraphic *graphic;
	NSEnumerator *const graphicEnum = [[[_graphicStack copy] autorelease] objectEnumerator];
	while((graphic = [graphicEnum nextObject])) if([graphic graphicType] == type) [_graphicStack removeObjectIdenticalTo:graphic];
	[self _updateCurrentGraphic];
}

#pragma mark -

- (unsigned)frameCount
{
	return _frameCount;
}
- (void)animateOneFrame:(PGAlertView *)anAlertView
{
	NSParameterAssert(_currentGraphic);
	_frameCount++;
	_frameCount %= [_currentGraphic frameMax];
	[_currentGraphic animateOneFrame:self];
}

#pragma mark -

- (void)windowWillClose:(NSNotification *)aNotif
{
	[_frameTimer invalidate];
	_frameTimer = nil;
	[_graphicStack removeAllObjects];
}

#pragma mark Private Protocol

- (void)_updateCurrentGraphic
{
	if(![_graphicStack count]) {
		if([_currentGraphic fadeOutDelay]) [(PGBezelPanel *)[self window] fadeOut];
		else [[self window] close];
		return;
	}
	[_currentGraphic release];
	_currentGraphic = [[_graphicStack objectAtIndex:0] retain];
	[_frameTimer invalidate];
	_frameCount = 0;
	NSTimeInterval const animationDelay = [_currentGraphic animationDelay];
	_frameTimer = animationDelay > 0 ? [self PG_performSelector:@selector(animateOneFrame:) withObject:self fireDate:nil interval:animationDelay options:PGRetainTarget] : nil;
	[self setNeedsDisplay:YES];
}

#pragma mark PGBezelPanelContentView Protocol

- (NSRect)bezelPanel:(PGBezelPanel *)sender
          frameForContentRect:(NSRect)aRect
          scale:(float)scaleFactor
{
	float const scaledPanelSize = scaleFactor * PGAlertViewSize;
	return PGIntegralRect(NSMakeRect(
		NSMinX(aRect) + PGMarginSize,
		NSMaxY(aRect) - scaledPanelSize - PGMarginSize,
		scaledPanelSize,
		scaledPanelSize
	));
}

#pragma mark NSView

- (id)initWithFrame:(NSRect)aRect
{
	if((self = [super initWithFrame:aRect])) {
		_graphicStack = [[NSMutableArray alloc] init];
	}
	return self;
}

- (BOOL)isOpaque
{
	return YES;
}
- (void)drawRect:(NSRect)aRect
{
	[_currentGraphic drawInView:self];
}

- (void)viewWillMoveToWindow:(NSWindow *)aWindow
{
	[[self window] AE_removeObserver:self name:NSWindowWillCloseNotification];
	if(aWindow) [aWindow AE_addObserver:self selector:@selector(windowWillClose:) name:NSWindowWillCloseNotification];
	else [self windowWillClose:nil];
}

#pragma mark NSObject

- (void)dealloc
{
	[self PG_cancelPreviousPerformRequests];
	[self AE_removeObserver];
	[_graphicStack release];
	[_currentGraphic release];
	[_frameTimer invalidate];
	[super dealloc];
}

@end

@implementation PGAlertGraphic

#pragma mark Class Methods

+ (id)cannotGoRightGraphic
{
	return [[[PGCannotGoRightGraphic alloc] init] autorelease];
}
+ (id)cannotGoLeftGraphic
{
	return [[[PGCannotGoLeftGraphic alloc] init] autorelease];
}
+ (id)loopedRightGraphic
{
	return [[[PGLoopedRightGraphic alloc] init] autorelease];
}
+ (id)loopedLeftGraphic
{
	return [[[PGLoopedLeftGraphic alloc] init] autorelease];
}

#pragma mark Instance Methods

- (PGAlertGraphicType)graphicType
{
	return PGSingleImageGraphic;
}

#pragma mark -

- (void)drawInView:(PGAlertView *)anAlertView
{
	int count, i;
	NSRect const *rects;
	[anAlertView getRectsBeingDrawn:&rects count:&count];
	[[NSColor AE_bezelBackgroundColor] set];
	float const f = PGAlertViewSize / 300.0f;
	for(i = count; i--;) {
		NSRectFill(NSIntersectionRect(rects[i], PGIntegralRect(NSMakeRect(  0.0f * f, 50.0f * f,  50.0f * f, 200.0f * f))));
		NSRectFill(NSIntersectionRect(rects[i], PGIntegralRect(NSMakeRect( 50.0f * f,  0.0f * f, 200.0f * f, 300.0f * f))));
		NSRectFill(NSIntersectionRect(rects[i], PGIntegralRect(NSMakeRect(250.0f * f, 50.0f * f,  50.0f * f, 200.0f * f))));
	}
	NSRect const corners[] = {
		PGIntegralRect(NSMakeRect(250.0f * f, 250.0f * f, 50.0f * f, 50.0f * f)),
		PGIntegralRect(NSMakeRect(  0.0f * f, 250.0f * f, 50.0f * f, 50.0f * f)),
		PGIntegralRect(NSMakeRect(  0.0f * f,   0.0f * f, 50.0f * f, 50.0f * f)),
		PGIntegralRect(NSMakeRect(250.0f * f,   0.0f * f, 50.0f * f, 50.0f * f))
	};
	NSPoint const centers[] = {
		PGIntegralPoint(NSMakePoint(250.0f * f, 250.0f * f)),
		PGIntegralPoint(NSMakePoint( 50.0f * f, 250.0f * f)),
		PGIntegralPoint(NSMakePoint( 50.0f * f,  50.0f * f)),
		PGIntegralPoint(NSMakePoint(250.0f * f,  50.0f * f))
	};
	for(i = sizeof(corners) / sizeof(*corners); i--;) {
		NSRect const corner = corners[i];
		if(!PGIntersectsRectList(corner, rects, count)) continue;
		[[NSColor clearColor] set];
		NSRectFill(corners[i]);
		[[NSColor AE_bezelBackgroundColor] set];
		NSBezierPath *const path = [NSBezierPath bezierPath];
		[path moveToPoint:centers[i]];
		[path appendBezierPathWithArcWithCenter:centers[i] radius:50.0f * f startAngle:90 * i endAngle:90 * (i + 1)];
		[path closePath];
		[path fill];
	}

	NSShadow *const shadow = [[[NSShadow alloc] init] autorelease];
	[shadow setShadowBlurRadius:4];
	[shadow setShadowOffset:NSMakeSize(0, -1)];
	[shadow setShadowColor:[NSColor blackColor]];
	[shadow set];
}
- (void)flipHorizontally
{
	NSAffineTransform *const flip = [[[NSAffineTransform alloc] init] autorelease];
	[flip translateXBy:PGAlertViewSize yBy:0];
	[flip scaleXBy:-1 yBy:1];
	[flip concat];
}
- (NSTimeInterval)fadeOutDelay
{
	return 1.0f;
}

#pragma mark -

- (NSTimeInterval)animationDelay
{
	return 0;
}
- (unsigned)frameMax
{
	return 0;
}
- (void)animateOneFrame:(PGAlertView *)anAlertView {}

#pragma mark NSObject Protocol

- (unsigned)hash
{
	return [[self class] hash];
}
- (BOOL)isEqual:(id)anObject
{
	return [anObject isMemberOfClass:[self class]];
}

@end

@implementation PGCannotGoRightGraphic

#pragma mark PGAlertGraphic

- (void)drawInView:(PGAlertView *)anAlertView
{
	[super drawInView:anAlertView];

	float const f = PGAlertViewSize / 300.0f;
	float const small = 5.0f * f;
	float const large = 10.0f * f;
	[[NSColor AE_bezelForegroundColor] set];

	NSBezierPath *const arrow = [NSBezierPath bezierPath];
	[arrow appendBezierPathWithArcWithCenter:NSMakePoint(180.0f * f, 150.0f * f) radius:large startAngle:315 endAngle:45];
	[arrow appendBezierPathWithArcWithCenter:NSMakePoint(140.0f * f, 200.0f * f) radius:small startAngle:45 endAngle:90];
	[arrow appendBezierPathWithArcWithCenter:NSMakePoint(125.0f * f, 200.0f * f) radius:small startAngle:90 endAngle:180];
	[arrow appendBezierPathWithArcWithCenter:NSMakePoint(115.0f * f, 180.0f * f) radius:small startAngle:0 endAngle:270 clockwise:YES];
	[arrow appendBezierPathWithArcWithCenter:NSMakePoint( 75.0f * f, 170.0f * f) radius:small startAngle:90 endAngle:180];
	[arrow appendBezierPathWithArcWithCenter:NSMakePoint( 75.0f * f, 130.0f * f) radius:small startAngle:180 endAngle:270];
	[arrow appendBezierPathWithArcWithCenter:NSMakePoint(115.0f * f, 120.0f * f) radius:small startAngle:90 endAngle:0 clockwise:YES];
	[arrow appendBezierPathWithArcWithCenter:NSMakePoint(125.0f * f, 100.0f * f) radius:small startAngle:180 endAngle:270];
	[arrow appendBezierPathWithArcWithCenter:NSMakePoint(140.0f * f, 100.0f * f) radius:small startAngle:270 endAngle:315];
	[arrow fill];

	NSBezierPath *const wall = [NSBezierPath bezierPath];
	[wall setLineWidth:20.0f * f];
	[wall setLineCapStyle:NSRoundLineCapStyle];
	[wall moveToPoint:NSMakePoint(210.0f * f, 220.0f * f)];
	[wall lineToPoint:NSMakePoint(210.0f * f,  80.0f * f)];
	[wall stroke];
}

@end

@implementation PGCannotGoLeftGraphic

#pragma mark PGAlertGraphic

- (void)drawInView:(PGAlertView *)anAlertView
{
	[self flipHorizontally];
	[super drawInView:anAlertView];
}

@end

@implementation PGLoopedLeftGraphic

#pragma mark PGAlertGraphic

- (PGAlertGraphicType)graphicType
{
	return PGInterImageGraphic;
}
- (void)drawInView:(PGAlertView *)anAlertView
{
	[super drawInView:anAlertView];

	[[NSColor AE_bezelForegroundColor] set];

	NSBezierPath *const s = [NSBezierPath bezierPath];
	float const f = PGAlertViewSize / 300.0f;
	[s appendBezierPathWithArcWithCenter:NSMakePoint(105.0f * f, 155.0f * f) radius:65.0f * f startAngle: 90.0f endAngle:270.0f clockwise:NO];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(150.0f * f,  85.0f * f) radius: 5.0f * f startAngle: 90.0f endAngle:  0.0f clockwise:YES];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(160.0f * f,  65.0f * f) radius: 5.0f * f startAngle:180.0f endAngle:270.0f clockwise:NO];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(165.0f * f,  65.0f * f) radius: 5.0f * f startAngle:270.0f endAngle:-45.0f clockwise:NO];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(200.0f * f, 105.0f * f) radius:10.0f * f startAngle:-45.0f endAngle: 45.0f clockwise:NO];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(165.0f * f, 145.0f * f) radius: 5.0f * f startAngle: 45.0f endAngle: 90.0f clockwise:NO];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(160.0f * f, 145.0f * f) radius: 5.0f * f startAngle: 90.0f endAngle:180.0f clockwise:NO];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(150.0f * f, 125.0f * f) radius: 5.0f * f startAngle:  0.0f endAngle:270.0f clockwise:YES];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(105.0f * f, 155.0f * f) radius:35.0f * f startAngle:270.0f endAngle: 90.0f clockwise:YES];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(195.0f * f, 155.0f * f) radius:35.0f * f startAngle: 90.0f endAngle:  0.0f clockwise:YES];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(245.0f * f, 155.0f * f) radius:15.0f * f startAngle:180.0f endAngle:  0.0f clockwise:NO];
	[s appendBezierPathWithArcWithCenter:NSMakePoint(195.0f * f, 155.0f * f) radius:65.0f * f startAngle:  0.0f endAngle: 90.0f clockwise:NO];
	[s fill];
}
- (NSTimeInterval)fadeOutDelay
{
	return 1.0f;
}

@end

@implementation PGLoopedRightGraphic

#pragma mark PGAlertGraphic

- (void)drawInView:(PGAlertView *)anAlertView
{
	[self flipHorizontally];
	[super drawInView:anAlertView];
}

@end

@implementation PGLoadingGraphic

#pragma mark Class Methods

+ (id)loadingGraphic
{
	return [[[PGLoadingGraphic alloc] init] autorelease];
}

#pragma mark Instance methods

- (float)progress
{
	return _progress;
}
- (void)setProgress:(float)progress
{
	_progress = MIN(MAX(progress, 0), 1);
}

#pragma mark NSObject Protocol

- (unsigned)hash
{
	return (unsigned)self;
}
- (BOOL)isEqual:(id)anObject
{
	return anObject == self;
}

#pragma mark PGAlertGraphic

- (void)drawInView:(PGAlertView *)anAlertView
{
	[super drawInView:anAlertView];
	float const f = PGAlertViewSize / 300.0f;
	[NSBezierPath AE_drawSpinnerInRect:(_progress ? NSMakeRect(50.0f * f, 60.0f * f, 200.0f * f, 200.0f * f) : NSMakeRect(40.0f * f, 40.0f * f, 220.0f * f, 220.0f * f)) startAtPetal:[anAlertView frameCount]];
	if(!_progress) return;
	BOOL switched = NO;
	[[NSColor AE_bezelForegroundColor] set];
	unsigned i = 0;
	for(; i < 22; i++) {
		if(!switched && i >= _progress * 22) {
			NSShadow *const shadow = [[[NSShadow alloc] init] autorelease];
			[shadow setShadowColor:nil];
			[shadow set];
			[[[NSColor AE_bezelForegroundColor] colorWithAlphaComponent:0.25] set];
			switched = YES;
		}
		if(switched) [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(52.0f * f + i * 9.0f * f, 32.0f * f, 5.0f * f, 5.0f * f)] fill];
		else NSRectFill(NSMakeRect(51.0f * f + i * 9.0f * f, 30.0f * f, 7.0f * f, 9.0f * f));
	}
}
- (NSTimeInterval)fadeOutDelay
{
	return 0.0f;
}

#pragma mark -

- (NSTimeInterval)animationDelay
{
	return 1.0 / 12.0;
}
- (unsigned)frameMax
{
	return 12;
}
- (void)animateOneFrame:(PGAlertView *)anAlertView
{
	float const f = PGAlertViewSize / 300.0f;
	[anAlertView setNeedsDisplayInRect:NSMakeRect( 25.0f * f, 50.0f * f,  25.0f * f, 200.0f * f)];
	[anAlertView setNeedsDisplayInRect:NSMakeRect( 50.0f * f, 25.0f * f, 200.0f * f, 250.0f * f)];
	[anAlertView setNeedsDisplayInRect:NSMakeRect(250.0f * f, 50.0f * f,  25.0f * f, 200.0f * f)];
}

@end

@implementation PGBezierPathIconGraphic

#pragma mark Class Methods

+ (id)graphicWithIconType:(AEIconType)type
{
	return [[[self alloc] initWithIconType:type] autorelease];
}

#pragma mark Instance Methods

- (id)initWithIconType:(AEIconType)type
{
	if((self = [super init])) {
		_iconType = type;
	}
	return self;
}

#pragma mark PGAlertGraphic

- (void)drawInView:(PGAlertView *)anAlertView
{
	[super drawInView:anAlertView];
	NSRect const b = [anAlertView bounds];
	[[NSColor AE_bezelForegroundColor] set];
	[NSBezierPath AE_drawIcon:_iconType inRect:PGCenteredSizeInRect(NSMakeSize(PGAlertViewSize / 2.0f, PGAlertViewSize / 2.0f), b)];
}
- (NSTimeInterval)fadeOutDelay
{
	return 1.0f;
}

#pragma mark NSObject Protocol

- (unsigned)hash
{
	return [[self class] hash] ^ _iconType;
}
- (BOOL)isEqual:(id)anObject
{
	return [anObject isMemberOfClass:[self class]] && ((PGBezierPathIconGraphic *)anObject)->_iconType == _iconType;
}

@end
