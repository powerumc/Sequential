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
#import <Cocoa/Cocoa.h>

// Other
#import "PGGeometryTypes.h"

@interface PGThumbnailView : NSView
{
	@private
	IBOutlet id dataSource;
	IBOutlet id delegate;
	id _representedObject;
	PGOrientation _thumbnailOrientation;
	NSArray *_items;
	NSMutableSet *_selection;
}

- (id)dataSource;
- (void)setDataSource:(id)obj;
- (id)delegate;
- (void)setDelegate:(id)obj;
- (id)representedObject;
- (void)setRepresentedObject:(id)obj;
- (PGOrientation)thumbnailOrientation;
- (void)setThumbnailOrientation:(PGOrientation)orientation;

- (NSArray *)items;
- (NSSet *)selection;
- (void)setSelection:(NSSet *)items;
- (void)scrollToFirstSelectedItem;

- (NSUInteger)indexOfItemAtPoint:(NSPoint)p;
- (NSRect)frameOfItemAtIndex:(NSUInteger)index withMargin:(BOOL)flag;

- (void)reloadData;
- (void)sizeToFit;

- (void)systemColorsDidChange:(NSNotification *)aNotif;

@end

@interface NSObject (PGThumbnailViewDataSource)

- (NSArray *)itemsForThumbnailView:(PGThumbnailView *)sender;
- (NSImage *)thumbnailView:(PGThumbnailView *)sender thumbnailForItem:(id)item;
- (BOOL)thumbnailView:(PGThumbnailView *)sender canSelectItem:(id)item;
- (NSString *)thumbnailView:(PGThumbnailView *)sender labelForItem:(id)item;
- (NSColor *)thumbnailView:(PGThumbnailView *)sender labelColorForItem:(id)item;
- (NSRect)thumbnailView:(PGThumbnailView *)sender highlightRectForItem:(id)item; // A rect within {{0, 0}, {1, 1}}.
- (BOOL)thumbnailView:(PGThumbnailView *)sender shouldRotateThumbnailForItem:(id)item;

@end

@interface NSObject (PGThumbnailViewDelegate)

- (void)thumbnailViewSelectionDidChange:(PGThumbnailView *)sender;

@end
