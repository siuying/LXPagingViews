// PagingView.m
//
// Copyright (c) 2012 Stan Chang Khin Boon (http://lxcid.com/)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "PagingView.h"
#import "ReusableView.h"
#import "PeepingPagingView.h"

// Set to 1 to print debug statement while paging view is laying out subviews.
#define DEBUG_LAYOUT 0

@interface PagingView ()

@property (nonatomic, assign) NSUInteger numberOfItems;
@property (nonatomic, strong) NSMutableArray *visibleReusableViews;
@property (nonatomic, assign, getter = isReferencingSuperview) BOOL referencingSuperview;
@property (nonatomic, assign) NSUInteger selectedPageIndexBeforeRotation;

- (void)layoutSubviewsFromIndex:(NSUInteger)theFromIndex toIndex:(NSUInteger)theToIndex;

@end

@implementation PagingView

@synthesize reusableViews = _reusableViews;
@synthesize dataSource = _dataSource;
@synthesize needsReloadData = _needsReloadData;
@synthesize ignoreInputsForSelection = _ignoreInputsForSelection;

@synthesize numberOfItems = _numberOfItems;
@synthesize visibleReusableViews = _visibleReusableViews;
@synthesize referencingSuperview = _referencingSuperview;
@synthesize selectedPageIndexBeforeRotation = _selectedPageIndexBeforeRotation;
@synthesize reusableViewsEnabled = _reusableViewsEnabled;

- (id<PagingViewDelegate>)delegate {
    return (id<PagingViewDelegate>)[super delegate];
}

- (void)setDelegate:(id<PagingViewDelegate>)theDelegate {
    [super setDelegate:theDelegate];
}

- (NSUInteger)selectedPageIndex {
    if ((!self.ignoreInputsForSelection) && ((self.isTracking) || (self.isDragging) || (self.isDecelerating))) {
        return NSNotFound;
    } else {
        return (NSUInteger)(self.contentOffset.x / CGRectGetWidth(self.frame));
    }
}

- (UIView<ReusableView> *)selectedPage {
    NSUInteger theSelectedPageIndex = self.selectedPageIndex;
    if (theSelectedPageIndex != NSNotFound) {
        CGFloat theMinX = theSelectedPageIndex * CGRectGetWidth(self.frame);
        CGFloat theMaxX = theMinX + CGRectGetWidth(self.frame);
        for (UIView<ReusableView> *theReusableView in self.visibleReusableViews) {
            CGPoint theCenter = theReusableView.center;
            if ((theMinX <= theCenter.x) && (theMaxX >= theCenter.y)) {
                return theReusableView;
            }
        }
    }
    return nil;
}

- (void)setSelectedPageIndex:(NSUInteger)theSelectedPageIndex {
    self.contentOffset = CGPointMake((theSelectedPageIndex * CGRectGetWidth(self.frame)), 0.0f);
}

- (void)setSelectedPageIndex:(NSUInteger)theSelectedPageIndex animated:(BOOL)theAnimated {
    if (theAnimated) {
        [self scrollRectToVisible:CGRectMake((theSelectedPageIndex * CGRectGetWidth(self.frame)), CGRectGetMinY(self.frame), CGRectGetWidth(self.frame), CGRectGetHeight(self.frame)) animated:YES];
    } else {
        [self setSelectedPageIndex:theSelectedPageIndex];
    }
}

- (NSUInteger)indexOfVisiblePage:(UIView<ReusableView> *)thePage {
    if ([self.visibleReusableViews containsObject:thePage]) {
        return (NSUInteger)(thePage.frame.origin.x / CGRectGetWidth(self.frame));
    } else {
        return NSNotFound;
    }
}

- (UIView<ReusableView> *)visiblePageAtIndex:(NSUInteger)theInteger {
    __block UIView<ReusableView> *thePageInQuery = nil;
    [self.visibleReusableViews enumerateObjectsUsingBlock:^(id theObject, NSUInteger theIndex, BOOL *theStop) {
        if ([self indexOfVisiblePage:(UIView<ReusableView> *)theObject] == theInteger) {
            thePageInQuery = (UIView<ReusableView> *)theObject;
            *theStop = YES;
        }
    }];
    return thePageInQuery;
}

- (id)initWithFrame:(CGRect)theFrame {
    self = [super initWithFrame:theFrame];
    if (self) {
        _reusableViews = [[NSMutableDictionary alloc] init];
        self.pagingEnabled = YES;
        self.showsHorizontalScrollIndicator = NO;
        self.showsVerticalScrollIndicator = NO;
        self.scrollsToTop = NO;
        self.needsReloadData = YES;
        self.reusableViewsEnabled = YES;
        
        self.visibleReusableViews = [[NSMutableArray alloc] init];
        
        [self addObserver:self forKeyPath:@"needsReloadData" options:NSKeyValueObservingOptionNew context:NULL];
    }
    return self;
}

- (void)dealloc {
    if ([self respondsToSelector:@selector(removeObserver:forKeyPath:context:)]) {
        [self removeObserver:self forKeyPath:@"needsReloadData" context:NULL];
    } else {
        [self removeObserver:self forKeyPath:@"needsReloadData"];
    }
}

- (void)removeAllVisibleReusableViews {
    [self.visibleReusableViews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    self.numberOfItems = 0;
}

- (void)reloadDataIfNecessary {
    if (self.needsReloadData) {
        [self removeAllVisibleReusableViews];
        self.numberOfItems = [self.dataSource numberOfItemsInPagingView:self];
        CGSize theContentSize = self.frame.size;
        theContentSize.width *= self.numberOfItems;
        self.contentSize = theContentSize;
        if ([self.delegate respondsToSelector:@selector(pagingViewSelectedPageIndex:)]) {
            self.selectedPageIndex = [(id<PagingViewDelegate>)self.delegate pagingViewSelectedPageIndex:self];
        }
        self.needsReloadData = NO;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self reloadDataIfNecessary];
    
    CGRect theVisibleBounds = self.bounds;
    if (self.isReferencingSuperview) {
        theVisibleBounds = [self convertRect:self.superview.bounds fromView:self.superview];
    }
    CGFloat theMinimumVisibleX = CGRectGetMinX(theVisibleBounds);
    CGFloat theMaximumVisibleX = CGRectGetMaxX(theVisibleBounds);
    
    CGFloat thePageWidth = CGRectGetWidth(self.frame);
    if (self.numberOfItems > 0) {
        NSUInteger theFromIndex = MAX(0, (NSInteger)floorf(theMinimumVisibleX / thePageWidth));
        NSUInteger theToIndex = MIN((NSInteger)floorf((theMaximumVisibleX - 0.1f) / thePageWidth), MAX(0, self.numberOfItems - 1));
        [self layoutSubviewsFromIndex:theFromIndex toIndex:theToIndex];
    }
}

- (void)layoutSubviewsFromIndex:(NSUInteger)theFromIndex toIndex:(NSUInteger)theToIndex {
#if DEBUG_LAYOUT
    NSLog(@"Layout subviews from %u to %u", theFromIndex, theToIndex);
#endif
    
    if (self.contentSize.width <= 0.0f) { // No content!
        return;
    }
    
    CGFloat thePageWidth = CGRectGetWidth(self.frame);
    CGFloat thePageHeight = CGRectGetHeight(self.frame);
    
    // Remove reusable views that is out of sight.
    NSMutableArray *theVisibleReusableViewsToBeRemoved = [[NSMutableArray alloc] init];
    [self.visibleReusableViews enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        UIView<ReusableView> *theReusableView = (UIView<ReusableView> *)obj;
        NSUInteger theIndex = (NSUInteger)floorf(CGRectGetMinX(theReusableView.frame) / thePageWidth);
        if ((theIndex < theFromIndex) || (theIndex > theToIndex)) {
            [theVisibleReusableViewsToBeRemoved addObject:theReusableView];
        }
    }];
    
#if DEBUG_LAYOUT
    if ([theVisibleReusableViewsToBeRemoved count] > 0) {
        NSLog(@"Removing %u views", [theVisibleReusableViewsToBeRemoved count]);
    }
#endif
    
    [theVisibleReusableViewsToBeRemoved makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    if ([self.visibleReusableViews count] == 0) { // At minimum must have a view for reference for the logic to work.
        CGFloat theMinX = theFromIndex * thePageWidth;
        CGRect theRect = CGRectMake(theMinX, 0.0f, thePageWidth, thePageHeight);
        UIView<ReusableView> *theReusableView = [self.dataSource pagingView:self reusableViewForPageIndex:theFromIndex withFrame:theRect];
        if (!CGRectContainsRect(theRect, theReusableView.frame)) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:[NSString stringWithFormat:
                                                   @"theReusableView's frame (%@) must be contained by the given frame (%@)",
                                                   NSStringFromCGRect(theReusableView.frame),
                                                   NSStringFromCGRect(theRect)]
                                         userInfo:nil];
        }
        [self.visibleReusableViews insertObject:theReusableView atIndex:0];
        [self addSubview:theReusableView];
    }
    
    UIView<ReusableView> *theLeftMostReusableView = [self.visibleReusableViews objectAtIndex:0];
    NSUInteger theLeftMostPageIndex = (NSUInteger)floorf(CGRectGetMinX(theLeftMostReusableView.frame) / thePageWidth);
    while ((theLeftMostPageIndex != 0) && (theLeftMostPageIndex > theFromIndex)) {
        theLeftMostPageIndex = MAX(0, theLeftMostPageIndex - 1);
        CGFloat theMinX = theLeftMostPageIndex * thePageWidth;
        CGRect theRect = CGRectMake(theMinX, 0.0f, thePageWidth, thePageHeight);
        UIView<ReusableView> *theReusableView = [self.dataSource pagingView:self reusableViewForPageIndex:theLeftMostPageIndex withFrame:theRect];
        if (!CGRectContainsRect(theRect, theReusableView.frame)) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:[NSString stringWithFormat:
                                                   @"theReusableView's frame (%@) must be contained by the given frame (%@)",
                                                   NSStringFromCGRect(theReusableView.frame),
                                                   NSStringFromCGRect(theRect)]
                                         userInfo:nil];
        }
        [self.visibleReusableViews insertObject:theReusableView atIndex:0];
        [self addSubview:theReusableView];
    }
    
    UIView<ReusableView> *theRightMostReusableView = [self.visibleReusableViews lastObject];
    NSUInteger theRightMostPageIndex = (NSUInteger)floorf(CGRectGetMinX(theRightMostReusableView.frame) / thePageWidth);
    while ((theRightMostPageIndex != MAX(0, self.numberOfItems - 1)) && (theRightMostPageIndex < theToIndex)) {
        theRightMostPageIndex = MIN(theRightMostPageIndex + 1, MAX(0, self.numberOfItems - 1));
        CGFloat theMinX = theRightMostPageIndex * thePageWidth;
        CGRect theRect = CGRectMake(theMinX, 0.0f, thePageWidth, thePageHeight);
        UIView<ReusableView> *theReusableView = [self.dataSource pagingView:self reusableViewForPageIndex:theRightMostPageIndex withFrame:theRect];
        if (!CGRectContainsRect(theRect, theReusableView.frame)) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:[NSString stringWithFormat:
                                                   @"theReusableView's frame (%@) must be contained by the given frame (%@)",
                                                   NSStringFromCGRect(theReusableView.frame),
                                                   NSStringFromCGRect(theRect)]
                                         userInfo:nil];
        }
        [self.visibleReusableViews addObject:theReusableView];
        [self addSubview:theReusableView];
    }
}

#pragma mark - Enqueue/Dequeue method

- (void)enqueueReusableView:(UIView<ReusableView> *)theReusableView {
    if (!self.isReusableViewsEnabled) {
        return;
    }
    NSMutableArray *theQueue = [self.reusableViews objectForKey:theReusableView.reuseIdentifier];
    if (theQueue == nil) {
        theQueue = [[NSMutableArray alloc] init];
        [self.reusableViews setObject:theQueue forKey:theReusableView.reuseIdentifier];
    }
    [theQueue insertObject:theReusableView atIndex:0];
}

- (UIView<ReusableView> *)dequeueReusableViewWithIdentifier:(NSString *)theIdentifier {
    NSMutableArray *theQueue = [self.reusableViews objectForKey:theIdentifier];
    if (theQueue == nil) {
        return nil;
    }
    UIView<ReusableView> *theLastReusableView = [theQueue lastObject];
    if (theLastReusableView == nil) {
        return nil;
    }
    [theQueue removeObject:theLastReusableView];
    [theLastReusableView prepareForReuse];
    return theLastReusableView;
}

- (void)willRemoveSubview:(UIView *)theSubview {
    [self.visibleReusableViews removeObject:theSubview];
    [self enqueueReusableView:(UIView<ReusableView> *)theSubview];
}

- (void)willMoveToSuperview:(UIView *)theNewSuperview {
    if ([theNewSuperview isKindOfClass:[PeepingPagingView class]]) {
        self.referencingSuperview = YES;
        self.clipsToBounds = NO;
    } else {
        self.referencingSuperview = NO;
        self.clipsToBounds = YES;
    }
}

#pragma mark - Key-Value Observing methods

- (void)observeValueForKeyPath:(NSString *)theKeyPath ofObject:(id)theObject change:(NSDictionary *)theChange context:(void *)theContext {
    if ([theObject isEqual:self]) {
        if ([theKeyPath isEqualToString:@"needsReloadData"]) {
            NSKeyValueChange theKeyValueChangeKind = [[theChange objectForKey:NSKeyValueChangeKindKey] unsignedIntegerValue];
            switch (theKeyValueChangeKind) {
                case NSKeyValueChangeSetting: {
                    if (self.needsReloadData) {
                        [self setNeedsLayout];
                    }
                } break;
                default: {
                } break;
            }
        }
    }
}

#pragma mark - Rotation methods

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)theToInterfaceOrientation duration:(NSTimeInterval)theDuration {
    self.selectedPageIndexBeforeRotation = self.selectedPageIndex;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)theInterfaceOrientation duration:(NSTimeInterval)theDuration {
    self.needsReloadData = YES;
    [self setNeedsLayout];
    [self layoutIfNeeded];
    self.selectedPageIndex = self.selectedPageIndexBeforeRotation;
    self.selectedPageIndexBeforeRotation = 0;
}

@end
