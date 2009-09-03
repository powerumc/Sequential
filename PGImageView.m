/* Copyright © 2007-2009, The Sequential Project
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
#import "PGImageView.h"

// Views
@class PGClipView;

// Other
#import "PGGeometry.h"
#import "PGDelayedPerforming.h"

// Categories
#import "NSAffineTransformAdditions.h"
#import "NSObjectAdditions.h"
#include <tgmath.h>

#define PGAnimateSizeChanges true
#define PGMaxWindowSize      5000.0f // 10,000 is a hard limit imposed by the window server.
#define PGDebugDrawingModes  false

@interface PGImageView (Private)

- (void)_runAnimationTimer;
- (void)_animate;
- (BOOL)_drawsRoundedCorners;
- (void)_cache;
- (BOOL)_imageIsOpaque;
- (void)_drawWithFrame:(NSRect)aRect operation:(NSCompositingOperation)operation rects:(NSRect const *)rects count:(NSUInteger)count;
- (void)_drawCornersOnRect:(NSRect)r;
- (NSAffineTransform *)_transformWithRotationInDegrees:(CGFloat)val;
- (BOOL)_setSize:(NSSize)size;
- (void)_sizeTransitionOneFrame;
- (void)_updateFrameSize;

@end

@implementation PGImageView

#pragma mark +PGImageView

+ (NSArray *)pasteboardTypes
{
	return [NSArray arrayWithObjects:NSTIFFPboardType, nil];
}

#pragma mark +NSObject

+ (void)initialize
{
	if([PGImageView class] != self) return;
	[self exposeBinding:@"animates"];
	[self exposeBinding:@"antialiasWhenUpscaling"];
	[self exposeBinding:@"drawsRoundedCorners"];
}

#pragma mark -PGImageView

- (NSImageRep *)rep
{
	return [[_rep retain] autorelease];
}
- (PGOrientation)orientation
{
	return _orientation;
}
- (void)setImageRep:(NSImageRep *)rep
        orientation:(PGOrientation)orientation
        size:(NSSize)size
{
	[self setNeedsDisplay:YES]; // Always redisplay in case rep is a PDF.
	if(orientation == _orientation && rep == _rep && !_sizeTransitionTimer && NSEqualSizes(size, _immediateSize)) {
		if(_isPDF) [self _cache];
		return;
	}
	_orientation = orientation;
	if(rep != _rep) {
		[_image removeRepresentation:(_cached ? _cache : _rep)];
		_cached = NO;
		[_rep release];
		_rep = nil;
		[self setSize:size allowAnimation:NO];
		_rep = [rep retain];
		[_image addRepresentation:_rep];
		_isPDF = [_rep isKindOfClass:[NSPDFImageRep class]];
		_numberOfFrames = [_rep isKindOfClass:[NSBitmapImageRep class]] ? [[(NSBitmapImageRep *)_rep valueForProperty:NSImageFrameCount] unsignedIntegerValue] : 1;

		[self _runAnimationTimer];
	} else [self setSize:size allowAnimation:NO];
	[self _cache];
}

#pragma mark -

- (NSSize)size
{
	return _sizeTransitionTimer ? _size : _immediateSize;
}
- (void)setSize:(NSSize)size
        allowAnimation:(BOOL)flag
{
	if(!PGAnimateSizeChanges || !flag) {
		_size = size;
		return [self stopAnimatedSizeTransition];
	}
	if(NSEqualSizes(size, [self size])) return;
	_size = size;
	if(!_sizeTransitionTimer) _sizeTransitionTimer = [[self PG_performSelector:@selector(_sizeTransitionOneFrame) withObject:nil fireDate:nil interval:PGAnimationFramerate options:kNilOptions] retain];
}
- (void)stopAnimatedSizeTransition
{
	[_sizeTransitionTimer invalidate];
	[_sizeTransitionTimer release];
	_sizeTransitionTimer = nil;
	_lastSizeAnimationTime = 0.0f;
	[self _setSize:_size];
	if(!_cached) [self _cache];
	[self setNeedsDisplay:YES];
}
- (NSSize)originalSize
{
	return PGRotated90CC & _orientation ? NSMakeSize([_rep pixelsHigh], [_rep pixelsWide]) : NSMakeSize([_rep pixelsWide], [_rep pixelsHigh]);
}
- (CGFloat)averageScaleFactor
{
	NSSize const s = [self size];
	NSSize const o = [self originalSize];
	return (s.width / o.width + s.height / o.height) / 2.0f;
}

#pragma mark -

- (BOOL)usesCaching
{
	return _usesCaching;
}
- (void)setUsesCaching:(BOOL)flag
{
	if(flag == _usesCaching) return;
	_usesCaching = flag;
	if(flag && !_cached) [self _cache];
}

#pragma mark -

- (CGFloat)rotationInDegrees
{
	return _rotationInDegrees;
}
- (void)setRotationInDegrees:(CGFloat)val
{
	if(val == _rotationInDegrees) return;
	_rotationInDegrees = remainderf(val, 360.0f);
	[self _updateFrameSize];
	[self setNeedsDisplay:YES];
}
- (NSPoint)rotateByDegrees:(CGFloat)val
           adjustingPoint:(NSPoint)aPoint
{
	NSRect const b1 = [self bounds];
	NSPoint const p = PGOffsetPointByXY(aPoint, -NSMidX(b1), -NSMidY(b1)); // Our bounds are going to change to fit the rotated image. Any point we want to remain constant relative to the image, we have to make relative to the bounds' center, since that's where the image is drawn.
	[self setRotationInDegrees:[self rotationInDegrees] + val];
	NSRect const b2 = [self bounds];
	return [[self _transformWithRotationInDegrees:val] transformPoint:PGOffsetPointByXY(p, NSMidX(b2), NSMidY(b2))];
}

#pragma mark -

- (BOOL)canAnimateRep
{
	return _numberOfFrames > 1;
}
- (BOOL)animates
{
	return _animates;
}
- (void)setAnimates:(BOOL)flag
{
	if(flag == _animates) return;
	_animates = flag;
	if(!flag && [self antialiasWhenUpscaling]) [self setNeedsDisplay:YES];
	[self _runAnimationTimer];
}
- (void)pauseAnimation
{
	_pauseCount++;
	[self _runAnimationTimer];
}
- (void)resumeAnimation
{
	NSParameterAssert(_pauseCount);
	_pauseCount--;
	[self _runAnimationTimer];
}

#pragma mark -

- (BOOL)antialiasWhenUpscaling
{
	return _antialias;
}
- (void)setAntialiasWhenUpscaling:(BOOL)flag
{
	if(flag == _antialias) return;
	_antialias = flag;
	[self _cache];
	[self setNeedsDisplay:YES];
}
- (NSImageInterpolation)interpolation
{
	if(_sizeTransitionTimer || [self inLiveResize] || ([self canAnimateRep] && [self animates])) return NSImageInterpolationNone;
	if([self antialiasWhenUpscaling]) return NSImageInterpolationHigh;
	NSSize const imageSize = NSMakeSize([_rep pixelsWide], [_rep pixelsHigh]), viewSize = [self size];
	return imageSize.width < viewSize.width && imageSize.height < viewSize.height ? NSImageInterpolationNone : NSImageInterpolationHigh;
}

#pragma mark -

- (BOOL)drawsRoundedCorners
{
	return _drawsRoundedCorners;
}
- (void)setDrawsRoundedCorners:(BOOL)flag
{
	if(flag == _drawsRoundedCorners) return;
	_drawsRoundedCorners = flag;
	[self _cache];
	[self setNeedsDisplay:YES];
}

#pragma mark -

- (BOOL)writeToPasteboard:(NSPasteboard *)pboard types:(NSArray *)types
{
	if(![types containsObject:NSTIFFPboardType]) return NO;
	if(!_rep || ![_rep respondsToSelector:@selector(TIFFRepresentation)]) return NO;
	if(pboard) {
		[pboard addTypes:[NSArray arrayWithObject:NSTIFFPboardType] owner:nil];
		[pboard setData:[(NSBitmapImageRep *)_rep TIFFRepresentation] forType:NSTIFFPboardType];
	}
	return YES;
}

#pragma mark -

- (void)appDidHide:(NSNotification *)aNotif
{
	[self pauseAnimation];
}
- (void)appDidUnhide:(NSNotification *)aNotif
{
	[self resumeAnimation];
}

#pragma mark -PGImageView(Private)

- (void)_runAnimationTimer
{
	[self PG_cancelPreviousPerformRequestsWithSelector:@selector(_animate) object:nil];
	if([self canAnimateRep] && _animates && !_pauseCount) [self PG_performSelector:@selector(_animate) withObject:nil fireDate:nil interval:-[[(NSBitmapImageRep *)_rep valueForProperty:NSImageCurrentFrameDuration] doubleValue] options:kNilOptions];
}
- (void)_animate
{
	NSUInteger const i = [[(NSBitmapImageRep *)_rep valueForProperty:NSImageCurrentFrame] unsignedIntegerValue] + 1;
	[(NSBitmapImageRep *)_rep setProperty:NSImageCurrentFrame withValue:[NSNumber numberWithUnsignedInteger:(i < _numberOfFrames ? i : 0)]];
	[self setNeedsDisplay:YES];
	[self _runAnimationTimer];
}
- (BOOL)_drawsRoundedCorners
{
	if(!_drawsRoundedCorners) return NO;
	NSSize const s = _immediateSize;
	return s.width >= 16 && s.height >= 16;
}
- (void)_cache
{
	[self PG_cancelPreviousPerformRequestsWithSelector:@selector(_cache) object:nil];
	if(!_cache || !_rep || [self canAnimateRep]) return;
	[_image removeRepresentation:(_cached ? _cache : _rep)];
	_cached = NO;
	NSSize const pixelSize = NSMakeSize([_rep pixelsWide], [_rep pixelsHigh]);
	[_image setSize:pixelSize];
	[_image addRepresentation:_rep];
	if(![self usesCaching] || [self inLiveResize] || _sizeTransitionTimer) return;
	if(_immediateSize.width > PGMaxWindowSize || _immediateSize.height > PGMaxWindowSize) return;

	[_cache setSize:_immediateSize];
	[_cache setPixelsWide:_immediateSize.width];
	[_cache setPixelsHigh:_immediateSize.height];
	NSWindow *const cacheWindow = [_cache window];
	NSRect cacheWindowFrame = [cacheWindow frame];
	cacheWindowFrame.size.width = MAX(NSWidth(cacheWindowFrame), _immediateSize.width);
	cacheWindowFrame.size.height = MAX(NSHeight(cacheWindowFrame), _immediateSize.height);
	[cacheWindow setFrame:cacheWindowFrame display:NO];
	NSView *const view = [cacheWindow contentView];

	if(![view lockFocusIfCanDraw]) return (void)[self PG_performSelector:@selector(_cache) withObject:nil fireDate:nil interval:0.0f options:kNilOptions];
	NSRect const cacheRect = [_cache rect];
	if(_isPDF) {
		[[NSColor whiteColor] set];
		NSRectFill(cacheRect);
	}
	[self _drawWithFrame:cacheRect operation:(_isPDF ? NSCompositeSourceOver : NSCompositeCopy) rects:NULL count:0];
	if([self _drawsRoundedCorners]) [self _drawCornersOnRect:cacheRect];
	[view unlockFocus];

	[_image removeRepresentation:_rep];
	[_image setSize:_immediateSize];
	[_image addRepresentation:_cache];
	_cached = YES;
}
- (BOOL)_imageIsOpaque
{
	return (_isPDF && _cached) || [_rep isOpaque];
}
- (void)_drawWithFrame:(NSRect)aRect
        operation:(NSCompositingOperation)operation
        rects:(NSRect const *)rects
        count:(NSUInteger)count
{
	NSSize const imageSize = [_image size];
	NSSize const s = NSMakeSize(imageSize.width / _immediateSize.width, imageSize.height / _immediateSize.height);
	BOOL const actualSize = NSEqualSizes(s, NSMakeSize(1, 1));
	if(!actualSize) {
		[NSGraphicsContext saveGraphicsState];
		[[NSGraphicsContext currentContext] setImageInterpolation:[self interpolation]];
	}
	NSRect r = aRect;
	NSAffineTransform *transform = nil;
	if(!_cached && PGUpright != _orientation) {
		transform = [NSAffineTransform AE_transformWithRect:&r orientation:_orientation];
		[transform concat];
	}
	if(count && PGUpright == _orientation) {
		NSInteger i = count;
		while(i--) [_image drawInRect:rects[i] fromRect:NSMakeRect(NSMinX(rects[i]) * s.width, NSMinY(rects[i]) * s.height, NSWidth(rects[i]) * s.width, NSHeight(rects[i]) * s.height) operation:operation fraction:1.0f];
	} else [_image drawInRect:r fromRect:NSZeroRect operation:operation fraction:1];
	if(actualSize) {
		[transform invert];
		[transform concat];
	} else [NSGraphicsContext restoreGraphicsState];
}
- (void)_drawCornersOnRect:(NSRect)r
{
	static NSImage *tl = nil, *tr = nil, *br = nil, *bl = nil;
	if(!tl) tl = [[NSImage imageNamed:@"Corner-Top-Left"] retain];
	if(!tr) tr = [[NSImage imageNamed:@"Corner-Top-Right"] retain];
	if(!br) br = [[NSImage imageNamed:@"Corner-Bottom-Right"] retain];
	if(!bl) bl = [[NSImage imageNamed:@"Corner-Bottom-Left"] retain];
	[tl drawAtPoint:NSMakePoint(NSMinX(r), NSMaxY(r) - [tl size].height) fromRect:NSZeroRect operation:NSCompositeDestinationOut fraction:1];
	[tr drawAtPoint:NSMakePoint(NSMaxX(r) - [tr size].width, NSMaxY(r) - [tr size].height) fromRect:NSZeroRect operation:NSCompositeDestinationOut fraction:1];
	[br drawAtPoint:NSMakePoint(NSMaxX(r) - [br size].width, NSMinY(r)) fromRect:NSZeroRect operation:NSCompositeDestinationOut fraction:1];
	[bl drawAtPoint:NSMakePoint(NSMinX(r), NSMinY(r)) fromRect:NSZeroRect operation:NSCompositeDestinationOut fraction:1];
}
- (NSAffineTransform *)_transformWithRotationInDegrees:(CGFloat)val
{
	NSRect const b = [self bounds];
	NSAffineTransform *const t = [NSAffineTransform transform];
	[t translateXBy:NSMidX(b) yBy:NSMidY(b)];
	[t rotateByDegrees:val];
	[t translateXBy:-NSMidX(b) yBy:-NSMidY(b)];
	return t;
}
- (BOOL)_setSize:(NSSize)size
{
	if(NSEqualSizes(size, _immediateSize)) return NO;
	_immediateSize = size;
	[self _updateFrameSize];
	return YES;
}
- (void)_sizeTransitionOneFrame
{
	NSSize const r = NSMakeSize(_size.width - _immediateSize.width, _size.height - _immediateSize.height);
	CGFloat const dist = hypotf(r.width, r.height);
	CGFloat const factor = MIN(1.0f, MAX(0.33f, 20.0f / dist) * PGLagCounteractionSpeedup(&_lastSizeAnimationTime, PGAnimationFramerate));
	if(dist < 1 || ![self _setSize:NSMakeSize(_immediateSize.width + r.width * factor, _immediateSize.height + r.height * factor)]) [self stopAnimatedSizeTransition];
}
- (void)_updateFrameSize
{
	NSSize s = _immediateSize;
	CGFloat const r = [self rotationInDegrees] / 180.0f * (CGFloat)pi;
	if(r) s = NSMakeSize(ceil(fabs(cosf(r)) * s.width + fabs(sinf(r)) * s.height), ceil(fabs(cosf(r)) * s.height + fabs(sinf(r)) * s.width));
	if(NSEqualSizes(s, [self frame].size)) return;
	[super setFrameSize:s];
	[self _cache];
}

#pragma mark -NSView

- (id)initWithFrame:(NSRect)aRect
{
	if((self = [super initWithFrame:aRect])) {
		_image = [[NSImage alloc] init];
		[_image setScalesWhenResized:NO]; // NSImage seems to make copies of its reps when resizing despite this, so be careful..
		[_image setCacheMode:NSImageCacheNever]; // We do our own caching.
		[_image setDataRetained:YES]; // Seems appropriate.
		_usesCaching = YES;
		_antialias = YES;
		_drawsRoundedCorners = YES;
		[NSApp AE_addObserver:self selector:@selector(appDidHide:) name:NSApplicationDidHideNotification];
		[NSApp AE_addObserver:self selector:@selector(appDidUnhide:) name:NSApplicationDidUnhideNotification];
	}
	return self;
}

- (BOOL)isOpaque
{
	return [self _imageIsOpaque] && ![self _drawsRoundedCorners] && ![self rotationInDegrees];
}
- (void)drawRect:(NSRect)aRect
{
	if(!_rep) return;
	NSRect b = (NSRect){NSZeroPoint, _immediateSize};
	b.origin.x = round(NSMidX([self bounds]) - NSWidth(b) / 2);
	b.origin.y = round(NSMidY([self bounds]) - NSHeight(b) / 2);
	CGFloat const deg = [self rotationInDegrees];
	if(deg) {
		[NSGraphicsContext saveGraphicsState];
		[[self _transformWithRotationInDegrees:deg] concat];
	}
	BOOL const drawCorners = !_cached && [self _drawsRoundedCorners];
	if(drawCorners) CGContextBeginTransparencyLayer([[NSGraphicsContext currentContext] graphicsPort], NULL);
	NSInteger count = 0;
	NSRect const *rects = NULL;
	if(!deg) [self getRectsBeingDrawn:&rects count:&count];
	if(_isPDF && !_cached) {
		[[NSColor whiteColor] set];
		if(count) NSRectFillList(rects, count);
		else NSRectFill(b);
	}
	[self _drawWithFrame:b operation:([self isOpaque] ? NSCompositeCopy : NSCompositeSourceOver) rects:rects count:count];
#if PGDebugDrawingModes
	[(_cached ? [NSColor redColor] : [NSColor blueColor]) set];
	NSFrameRect(b); // Outer frame: Cached
	[([self isOpaque] ? [NSColor redColor] : [NSColor blueColor]) set];
	NSFrameRect(NSInsetRect(b, 2, 2)); // Middle frame 1: View opaque
	[([self _imageIsOpaque] ? [NSColor redColor] : [NSColor blueColor]) set];
	NSFrameRect(NSInsetRect(b, 4, 4)); // Middle frame 2: Image opaque
	[(deg ? [NSColor blueColor] : [NSColor redColor]) set];
	NSFrameRect(NSInsetRect(b, 6, 6)); // Inner frame: Rotated
#endif
	if(drawCorners) {
		[self _drawCornersOnRect:b];
		CGContextEndTransparencyLayer([[NSGraphicsContext currentContext] graphicsPort]);
	}
	if(deg) [NSGraphicsContext restoreGraphicsState];
}
- (void)setFrameSize:(NSSize)aSize
{
	PGAssertNotReached(@"-[PGImageView setFrameSize:] should not be invoked directly. Use -setSize: instead.");
}
- (void)viewDidEndLiveResize
{
	[super viewDidEndLiveResize];
	if(_cached) return;
	[self _cache];
	[self setNeedsDisplay:YES];
}
- (void)viewDidMoveToWindow
{
	if(![self window]) return; // Without a window to draw in, nothing else matters.
	NSWindowDepth const depth = [[self window] depthLimit];
	if(!_cache) {
		_cache = [[NSCachedImageRep alloc] initWithSize:NSMakeSize(1, 1) depth:depth separate:YES alpha:YES];
		NSView *const contentView = [[self window] contentView];
		if([contentView lockFocusIfCanDraw]) {
			[_cache drawInRect:NSMakeRect(0.0f, 0.0f, 1.0f, 1.0f)]; // This may look like voodoo, but somehow drawing the cache when it's small dramatically improves the speed of the initial draw when it's large.
			[contentView unlockFocus];
			[contentView setNeedsDisplayInRect:NSMakeRect(0.0f, 0.0f, 1.0f, 1.0f)]; // We didn't actually want to do that, so redraw it back to normal.
		}
	} else if([[_cache window] depthLimit] != depth) [[_cache window] setDepthLimit:depth];
	else return;
	[self _cache];
}

#pragma mark -NSView(PGClipViewAdditions)

- (BOOL)PG_acceptsClicksInClipView:(PGClipView *)sender
{
	return NO;
}
- (BOOL)PG_scalesContentWithFrameSizeInClipView:(PGClipView *)sender
{
	return YES;
}

#pragma mark -NSObject

- (id)init
{
	return [self initWithFrame:NSZeroRect];
}
- (void)dealloc
{
	[self PG_cancelPreviousPerformRequests];
	[self AE_removeObserver];
	[self stopAnimatedSizeTransition];
	[self unbind:@"animates"];
	[self unbind:@"antialiasWhenUpscaling"];
	[self unbind:@"drawsRoundedCorners"];
	[self setImageRep:nil orientation:PGUpright size:NSZeroSize];
	NSParameterAssert(!_rep);
	[_cache release];
	[self setAnimates:NO];
	[_image release];
	[super dealloc];
}

@end
