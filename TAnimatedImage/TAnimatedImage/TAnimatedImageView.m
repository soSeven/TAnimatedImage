//
//  TAnimatedImageView.m
//  TAnimatedImage
//
//  Created by liqi on 2018/3/16.
//  Copyright © 2018年 apple. All rights reserved.
//

#import "TAnimatedImageView.h"
#import "TWeakProxy.h"

@interface TAnimatedImageView ()

@property (nonatomic, strong, readwrite) UIImage *currentFrame; // 当前帧
@property (nonatomic, assign, readwrite) NSUInteger currentFrameIndex; // 当前帧位置

@property (nonatomic, assign) NSUInteger loopCountdown; // 循环次数计算
@property (nonatomic, assign) NSTimeInterval accumulator; // 展示时间累加
@property (nonatomic, strong) CADisplayLink *displayLink; // 定时器

@property (nonatomic, assign) BOOL shouldAnimate; // 是否需要动画
@property (nonatomic, assign) BOOL needsDisplayWhenImageBecomesAvailable; // 是否需要重绘

@end

@implementation TAnimatedImageView

#pragma mark - Initializers

- (instancetype)initWithImage:(UIImage *)image
{
    self = [super initWithImage:image];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithImage:(UIImage *)image highlightedImage:(UIImage *)highlightedImage
{
    self = [super initWithImage:image highlightedImage:highlightedImage];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit
{
    self.runloopMode = [[self class] defaultRunLoopMode];
    if (@available(iOS 11.0, *)) {
        self.accessibilityIgnoresInvertColors = YES;
    }
}

#pragma mark - Accessors
#pragma mark Public

- (void)setAnimatedImage:(TAnimatedImage *)animatedImage
{
    if (![_animatedImage isEqual:animatedImage]) {
        if (animatedImage) {
            super.image = nil;
            super.highlighted = NO;
            [self invalidateIntrinsicContentSize];
        }
        else {
            [self stopAnimating];
        }
        
        _animatedImage = animatedImage;
        
        self.currentFrame = animatedImage.posterImage;
        self.currentFrameIndex = 0;
        if (animatedImage.loopCount > 0) {
            self.loopCountdown = animatedImage.loopCount;
        }
        else {
            self.loopCountdown = NSUIntegerMax;
        }
        self.accumulator = 0.0;
        
        [self updateShouldAnimate];
        if (self.shouldAnimate) {
            [self startAnimating];
        }
        
        [self.layer setNeedsDisplay];
    }
}

#pragma mark - Life Cycle

- (void)dealloc
{
    [_displayLink invalidate];
}

#pragma mark - UIView Method Overrides
#pragma mark Observing View-Related Changes

- (void)didMoveToSuperview
{
    [super didMoveToSuperview];
    
    [self updateShouldAnimate];
    if (self.shouldAnimate) {
        [self startAnimating];
    }
    else {
        [self stopAnimating];
    }
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    
    [self updateShouldAnimate];
    if (self.shouldAnimate) {
        [self startAnimating];
    }
    else {
        [self stopAnimating];
    }
}

- (void)setAlpha:(CGFloat)alpha
{
    [super setAlpha:alpha];
    
    [self updateShouldAnimate];
    if (self.shouldAnimate) {
        [self startAnimating];
    }
    else {
        [self stopAnimating];
    }
}

#pragma mark Auto Layout

- (CGSize)intrinsicContentSize
{
    CGSize intrinsicContentSize = [super intrinsicContentSize];
    if (self.animatedImage) {
        intrinsicContentSize = self.image.size;
    }
    return intrinsicContentSize;
}

#pragma mark - UIImageView Method Overrides
#pragma mark Image Data

- (UIImage *)image
{
    UIImage *image = nil;
    if (self.animatedImage) {
        image = self.currentFrame;
    }
    else {
        image = super.image;
    }
    return image;
}

- (void)setImage:(UIImage *)image
{
    if (image) {
        self.animatedImage = nil;
    }
    super.image = image;
}

#pragma mark Animating Images

- (void)startAnimating
{
    if (self.animatedImage) {
        if (!self.displayLink) {
            TWeakProxy *weakProxy = [TWeakProxy proxyWithTarget:self];
            self.displayLink = [CADisplayLink displayLinkWithTarget:weakProxy selector:@selector(didplayDidRefresh:)];
            [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:self.runloopMode];
        }
        // 刷新速率
        const NSTimeInterval kDisplayRefreshRate = 60.0;
        // GIF播放时间数组的最大公约数与刷新速率相乘 与 1 进行比较 取最大值
        // 所以 (displayLink.duration * displayLink.frameInterval) 形成 一个单元时间
        // GIF播放时间数组 都为 一个单元时间 的倍数
        // 所以 利用刷新速率 可以 很好的 展示各帧画面的时间
        if ([self.displayLink respondsToSelector:@selector(preferredFramesPerSecond)]) {
            self.displayLink.preferredFramesPerSecond = MAX([self frameDelayGreatestCommonDivisor] * kDisplayRefreshRate, 1);
        }
        else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"
            self.displayLink.frameInterval = MAX([self frameDelayGreatestCommonDivisor] * kDisplayRefreshRate, 1);
#pragma clang diagnostic pop
        }
        
        self.displayLink.paused = NO;
    }
    else {
        [super startAnimating];
    }
}

- (void)stopAnimating
{
    if (self.animatedImage) {
        self.displayLink.paused = YES;
    }
    else {
        [super stopAnimating];
    }
}

- (BOOL)isAnimating
{
    BOOL isAnimating = NO;
    if (self.animatedImage) {
        isAnimating = self.displayLink && !self.displayLink.isPaused;
    }
    else {
        isAnimating = [super isAnimating];
    }
    return isAnimating;
}

// 求出两个数的最大公约数
static NSUInteger gcd(NSUInteger a, NSUInteger b)
{
    if (a < b) {
        return gcd(b, a);
    }
    else if (a == b) {
        return b;
    }
    
    while (true) {
        NSUInteger remainder = a % b;
        if (remainder == 0) {
            return b;
        }
        a = b;
        b = remainder;
    }
}

- (NSTimeInterval)frameDelayGreatestCommonDivisor
{
    // 最大公约数精度 ： 10
    const NSTimeInterval kGreatestCommonDivisorPrecision = 2.0 / KTAnimatedImageDelayTimeIntervalMinimum;
    // GIF中每帧图片的播放时间
    NSArray *delays = self.animatedImage.delayTimesForIndexes.allValues;
    // GIF中第一帧图片播放时间
    NSUInteger scaledGCD = lrint([delays.firstObject floatValue] * kGreatestCommonDivisorPrecision);
    // 求出这些播放时间的最大公约数
    for (NSNumber *value in delays) {
        scaledGCD = gcd(lrint([value floatValue] * kGreatestCommonDivisorPrecision), scaledGCD);
    }
    // 除以最大公约数精度，返回秒数
    return scaledGCD / kGreatestCommonDivisorPrecision;
}

- (void)setRunloopMode:(NSString *)runloopMode
{
    if (![@[NSDefaultRunLoopMode, NSRunLoopCommonModes] containsObject:runloopMode]) {
        _runloopMode = [[self class] defaultRunLoopMode];
    }
    else {
        _runloopMode = runloopMode;
    }
}

#pragma mark - RunLoop

+ (NSString *)defaultRunLoopMode
{
    return [NSProcessInfo processInfo].activeProcessorCount > 1 ? NSRunLoopCommonModes : NSDefaultRunLoopMode;
}

#pragma mark - Highlighted Image Unsupport

- (void)setHighlighted:(BOOL)highlighted
{
    if (!self.animatedImage) {
        [super setHighlighted:highlighted];
    }
}

#pragma mark - DisPlay

- (void)updateShouldAnimate
{
    BOOL isVisible = self.window && self.superview && ![self isHidden] && self.alpha > 0.0;
    self.shouldAnimate = self.animatedImage && isVisible;
}

- (void)didplayDidRefresh:(CADisplayLink *)displayLink
{
    if (!self.shouldAnimate) {
        return;
    }
    // 这一帧要展示的时间
    NSNumber *delayTimeNumber = [self.animatedImage.delayTimesForIndexes objectForKey:@(self.currentFrameIndex)];
    if (delayTimeNumber) {
        NSTimeInterval delayTime = [delayTimeNumber floatValue];
        UIImage *image = [self.animatedImage imageLazilyCachedAtIndex:self.currentFrameIndex];
        if (image) {
            // 当前帧
            self.currentFrame = image;
            if (self.needsDisplayWhenImageBecomesAvailable) {
                // 绘制这一帧
                [self.layer setNeedsDisplay];
                self.needsDisplayWhenImageBecomesAvailable = NO;
            }
            // 累加 已展示的时间
            NSTimeInterval unitOfTime = 0;
            if ([displayLink respondsToSelector:@selector(preferredFramesPerSecond)]) {
                unitOfTime = displayLink.duration * displayLink.preferredFramesPerSecond;
            }
            else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"
                unitOfTime = displayLink.duration * displayLink.frameInterval;
#pragma clang diagnostic pop
            }
            self.accumulator += unitOfTime;
            // 这里可以用 if语句
            // 使用 while语句 更好
            while (self.accumulator >= delayTime) {
                self.accumulator -= delayTime;
                // 绘制下一帧
                self.currentFrameIndex++;
                // 到最后一帧
                if (self.currentFrameIndex >= self.animatedImage.frameCount) {
                    // GIF已经循环一次
                    self.loopCountdown--;
                    if (self.loopCompletionBlock) {
                        self.loopCompletionBlock(self.loopCountdown);
                    }
                    if (self.loopCountdown == 0) {
                        // GIF已经完成
                        [self stopAnimating];
                        return;
                    }
                    self.currentFrameIndex = 0;
                }
                // 当前帧展示时间已经结束，绘制下一帧
                self.needsDisplayWhenImageBecomesAvailable = YES;
            }
        }
        else {
            
        }
    }
    else {
        // 绘制下一帧
        self.currentFrameIndex++;
    }
}

#pragma mark - CALayerDelegate

- (void)displayLayer:(CALayer *)layer
{
    layer.contents = (__bridge id)self.image.CGImage;
}

@end
