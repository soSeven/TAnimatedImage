//
//  TAnimatedImage.m
//  TAnimatedImage
//
//  Created by liqi on 2018/3/14.
//  Copyright © 2018年 apple. All rights reserved.
//

#import "TAnimatedImage.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <ImageIO/ImageIO.h>
// tool
#import "TWeakProxy.h"

#define MEGABYTE (1024 * 1024)

const NSTimeInterval KTAnimatedImageDelayTimeIntervalMinimum = 0.2;

typedef NS_ENUM(NSUInteger, TAnimatedImageDataSizeCategory) {
    TAnimatedImageDataSizeCategoryAll = 10,
    TAnimatedImageDataSizeCategoryDefault = 75,
    TAnimatedImageDataSizeCategoryOnDemand = 250,
    TAnimatedImageDataSizeCategoryUnsupported
};

typedef NS_ENUM(NSUInteger, TAnimatedImageFrameCacheSize) {
    TAnimatedImageFrameCacheSizeNoLimit = 0,
    TAnimatedImageFrameCacheSizeLowMemory = 1,
    TAnimatedImageFrameCacheSizeGrowAfterMemoryWarning = 2,
    TAnimatedImageFrameCacheSizeDefault = 5
};

@interface TAnimatedImage ()

@property (nonatomic, assign, readonly) NSUInteger frameCacheSizeOptimal; // 根据策略控制缓存帧的最大数量

@property (nonatomic, assign, readonly, getter=isPredrawingEnabled) BOOL predrawingEnabled; // 是否对每帧图片重新绘制

@property (nonatomic, assign) NSUInteger frameCacheSizeMaxInternal; // 内部用于控制缓存帧的最大数量

@property (nonatomic, assign) NSUInteger requestedFrameIndex; // 当前获取的帧的索引

@property (nonatomic, assign) NSUInteger posterImageFrameIndex; // 封面帧的索引

@property (nonatomic, strong, readonly) NSMutableDictionary *cachedFramesForIndexes; // 缓存帧的图片数组

@property (nonatomic, strong, readonly) NSMutableIndexSet *cachedFrameIndexes; // 缓存帧的索引

@property (nonatomic, strong, readonly) NSMutableIndexSet *requestedFrameIndexes; // 正在请求帧的索引

@property (nonatomic, strong, readonly) NSIndexSet *allFramesIndexSet; // 全部帧的索引

@property (nonatomic, assign) NSUInteger memoryWarningCount; // 内存警告次数

@property (nonatomic, strong, readonly) dispatch_queue_t serialQueue; // 加载帧图片对列

@property (nonatomic, strong, readonly) __attribute__((NSObject)) CGImageSourceRef imageSource; // 图片源数据

@property (nonatomic, strong, readonly) TAnimatedImage *weakProxy; // 弱持有

@end

static NSHashTable *allAnimatedImagesWeak;

@implementation TAnimatedImage

- (NSUInteger)frameCacheSizeCurrent
{
    // 确定当前的缓存帧数
    
    // 1.根据 frameCacheSizeOptimal 获取 当前的缓存帧数
    NSUInteger frameCacheSizeCurrent = self.frameCacheSizeOptimal;
    
    // 2.根据 frameCacheSizeMax 对 当前的缓存帧数 进行 调整
    if (self.frameCacheSizeMax > TAnimatedImageFrameCacheSizeNoLimit) {
        frameCacheSizeCurrent = MIN(frameCacheSizeCurrent, self.frameCacheSizeMax);
    }
    
    // 3.根据 frameCacheSizeMaxInternal 对 当前的缓存帧数 进行 调整
    if (self.frameCacheSizeMaxInternal > TAnimatedImageFrameCacheSizeNoLimit) {
        frameCacheSizeCurrent = MIN(frameCacheSizeCurrent, self.frameCacheSizeMaxInternal);
    }
    
    return frameCacheSizeCurrent;
}

- (void)setFrameCacheSizeMax:(NSUInteger)frameCacheSizeMax
{
    if (_frameCacheSizeMax != frameCacheSizeMax) {
        BOOL willFrameCacheSizeShrink = (frameCacheSizeMax < self.frameCacheSizeCurrent);
        
        _frameCacheSizeMax = frameCacheSizeMax;
        
        if (willFrameCacheSizeShrink) {
            [self purgeFrameCacheIfNeeded];
        }
    }
}

- (void)setFrameCacheSizeMaxInternal:(NSUInteger)frameCacheSizeMaxInternal
{
    if (_frameCacheSizeMaxInternal != frameCacheSizeMaxInternal) {
        BOOL willFrameCacheSizeShrink = (frameCacheSizeMaxInternal < self.frameCacheSizeMaxInternal);
        
        _frameCacheSizeMaxInternal = frameCacheSizeMaxInternal;
        
        if (willFrameCacheSizeShrink) {
            [self purgeFrameCacheIfNeeded];
        }
    }
}

#pragma mark - Life Cycle

+ (void)initialize
{
    // 类方法 只执行一次
    if (self == [TAnimatedImage class]) {
        allAnimatedImagesWeak = [NSHashTable weakObjectsHashTable];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
            NSAssert([NSThread isMainThread], @"接收到通知，没有在主线程");
            NSArray *images = nil;
            @synchronized(allAnimatedImagesWeak) {
                images = [[allAnimatedImagesWeak allObjects] copy];
            }
            [images makeObjectsPerformSelector:@selector(didReceiveMemoryWarning:) withObject:note];
        }];
    }
}

- (instancetype)init
{
    TAnimatedImage *animatedImage = [self initWithAnimatedGIFData:nil];
    return animatedImage;
}

- (instancetype)initWithAnimatedGIFData:(NSData *)data
{
    return [self initWithAnimatedGIFData:data optimalFrameCacheSize:0 predrawingEnabled:YES];
}

- (instancetype)initWithAnimatedGIFData:(NSData *)data
                  optimalFrameCacheSize:(NSUInteger)optimalFrameCacheSize
                      predrawingEnabled:(BOOL)isPredrawingEnabled
{
    BOOL hasData = ([data length] > 0);
    if (!hasData) {
        return nil;
    }
    self = [super init];
    if (self) {
        _data = data;
        
        // 是否解码
        _predrawingEnabled = isPredrawingEnabled;
        
        // 缓存的帧图片
        _cachedFramesForIndexes = [[NSMutableDictionary alloc] init];
        // 缓存的帧索引
        _cachedFrameIndexes = [[NSMutableIndexSet alloc] init];
        
        // 当前获取的帧索引
        _requestedFrameIndexes = [[NSMutableIndexSet alloc] init];
        
        // kCGImageSourceShouldCache 为 NO,可以避免系统对图片进行缓存
        _imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)data,
                                                   (__bridge CFDictionaryRef)@{(NSString *)kCGImageSourceShouldCache:@NO});
        // 是否能成功创建图片源
        if (!_imageSource) {
            return nil;
        }
        
        // 判断是否是GIF
        CFStringRef imageSourceContainerType = CGImageSourceGetType(_imageSource);
        BOOL isGIFData = UTTypeConformsTo(imageSourceContainerType, kUTTypeGIF);
        if (!isGIFData) {
            return nil;
        }
        
        // Get `LoopCount`
        // Note: 0 means repeating the animation indefinitely.
        // Image properties example:
        // {
        //     FileSize = 314446;
        //     "{GIF}" = {
        //         HasGlobalColorMap = 1;
        //         LoopCount = 0;
        //     };
        // }
        
        // 读取图片数据
        NSDictionary *imageProperties = (__bridge_transfer NSDictionary *)CGImageSourceCopyProperties(_imageSource, NULL);
        _loopCount = [[[imageProperties objectForKey:(id)kCGImagePropertyGIFDictionary] objectForKey:(id)kCGImagePropertyGIFLoopCount] unsignedIntegerValue];
        
        size_t imageCount = CGImageSourceGetCount(_imageSource);
        NSUInteger skippedFrameCount = 0;
        NSMutableDictionary *delayTimesForIndexesMutable = [NSMutableDictionary dictionaryWithCapacity:imageCount];
        for (size_t i = 0; i < imageCount; i++) {
            @autoreleasepool {
                CGImageRef frameImageRef = CGImageSourceCreateImageAtIndex(_imageSource, i, NULL);
                if (frameImageRef) {
                    UIImage *frameImage = [UIImage imageWithCGImage:frameImageRef];
                    if (frameImage) {
                        // 封面帧图片
                        if (!self.posterImage) {
                            _posterImage = frameImage;
                            _size = _posterImage.size;
                            _posterImageFrameIndex = i;
                            [self.cachedFramesForIndexes setObject:self.posterImage forKey:@(self.posterImageFrameIndex)];
                            [self.cachedFrameIndexes addIndex:self.posterImageFrameIndex];
                        }
                        
                        // Frame properties example:
                        // {
                        //     ColorModel = RGB;
                        //     Depth = 8;
                        //     PixelHeight = 960;
                        //     PixelWidth = 640;
                        //     "{GIF}" = {
                        //         DelayTime = "0.4";
                        //         UnclampedDelayTime = "0.4";
                        //     };
                        // }
                        NSDictionary *frameProperties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(_imageSource, i, NULL);
                        NSDictionary *framePropertiesGIF = [frameProperties objectForKey:(id)kCGImagePropertyGIFDictionary];
                        
                        NSNumber *delayTime = [frameProperties objectForKey:(id)kCGImagePropertyGIFUnclampedDelayTime];
                        if (!delayTime) {
                            delayTime = [framePropertiesGIF objectForKey:(id)kCGImagePropertyGIFDelayTime];
                        }
                        
                        const NSTimeInterval kDelayTimeIntervalDefault = 0.1;
                        if (!delayTime) {
                            if (i == 0) {
                                delayTime = @(kDelayTimeIntervalDefault);
                            }
                            else {
                                delayTime = delayTimesForIndexesMutable[@(i - 1)];
                            }
                        }
                        
                        if ([delayTime floatValue] <
                            ((float)KTAnimatedImageDelayTimeIntervalMinimum - FLT_EPSILON)) {
                            delayTime = @(kDelayTimeIntervalDefault);
                        }
                        delayTimesForIndexesMutable[@(i)] = delayTime;
                    }
                    else {
                        skippedFrameCount++;
                    }
                    CFRelease(frameImageRef);
                }
                else {
                    skippedFrameCount++;
                }
            }
        }
        _delayTimesForIndexes = [delayTimesForIndexesMutable copy];
        _frameCount = imageCount;
        
        if (self.frameCount == 0) {
            return nil;
        }
        else if (self.frameCount == 1) {
            
        }
        else {
            
        }
        
        if (optimalFrameCacheSize == 0) {
            // 图片大小 确定 缓存策略
            CGFloat animatedImageDataSize = CGImageGetBytesPerRow(self.posterImage.CGImage) * self.size.height * (self.frameCount - skippedFrameCount) / MEGABYTE;
            if (animatedImageDataSize <= TAnimatedImageDataSizeCategoryAll) {
                // 当小于 10M 时缓存全部帧
                _frameCacheSizeOptimal = self.frameCount;
            }
            else if (animatedImageDataSize <= TAnimatedImageDataSizeCategoryDefault) {
                // 当小于 75M 时缓存5帧
                _frameCacheSizeOptimal = TAnimatedImageFrameCacheSizeDefault;
            }
            else {
                // 太大 时缓存1帧
                _frameCacheSizeOptimal = TAnimatedImageFrameCacheSizeLowMemory;
            }
        }
        else {
            // 自定义缓存帧数
            _frameCacheSizeOptimal = optimalFrameCacheSize;
        }
        // 缓存帧数 应小于等于 总帧数
        _frameCacheSizeOptimal = MIN(_frameCacheSizeOptimal, self.frameCount);
        
        _allFramesIndexSet = [[NSIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, self.frameCount)];
        
        _weakProxy = (id)[TWeakProxy proxyWithTarget:self];
        
        @synchronized(allAnimatedImagesWeak) {
            [allAnimatedImagesWeak addObject:self];
        }
    }
    return self;
}

+ (instancetype)animatedImageWithGIFData:(NSData *)data
{
    TAnimatedImage *animatedImage = [[TAnimatedImage alloc] initWithAnimatedGIFData:data];
    return animatedImage;
}

- (void)dealloc
{
    if (_weakProxy) {
        [NSObject cancelPreviousPerformRequestsWithTarget:_weakProxy];
    }
    
    if (_imageSource) {
        CFRelease(_imageSource);
    }
}

#pragma mark Frame Caching

// 得到接下来需要缓存的帧图片索引
- (NSMutableIndexSet *)frameIndexesToCache
{
    NSMutableIndexSet *indexesToCache = nil;
    if (self.frameCacheSizeCurrent == self.frameCount) {
        // 现在 缓存的帧图片数量 与 总帧数相等， 则全部缓存
        indexesToCache = [self.allFramesIndexSet mutableCopy];
    }
    else {
        indexesToCache = [[NSMutableIndexSet alloc] init];
        // EX:
        // 假设 frameCacheSizeCurrent = 5, frameCount = 10, requestedFrameIndex = 7
        // 则 firstLength = 3, firstRange = [7, 8 , 9]
        // 则 secondLength = 2, firstRange = [0, 1]
        // 则需要缓存的帧图片索引 [7, 8 , 9, 0, 1]
        NSUInteger firstLength = MIN(self.frameCacheSizeCurrent, self.frameCount - self.requestedFrameIndex);
        NSRange firstRange = NSMakeRange(self.requestedFrameIndex, firstLength);
        [indexesToCache addIndexesInRange:firstRange];
        NSUInteger secondLength = self.frameCacheSizeCurrent - firstLength;
        if (secondLength > 0) {
            NSRange secondRange = NSMakeRange(0, secondLength);
            [indexesToCache addIndexesInRange:secondRange];
        }
        // 同时添加封面帧图片
        [indexesToCache addIndex:self.posterImageFrameIndex];
    }
    return indexesToCache;
}

- (void)purgeFrameCacheIfNeeded
{
    if ([self.cachedFrameIndexes count] > self.frameCacheSizeCurrent) {
        // 已缓存帧数量 大于 当前最大缓存数量时
        NSMutableIndexSet *indexesToPurge = [self.cachedFrameIndexes mutableCopy];
        // 移除需要缓存的
        [indexesToPurge removeIndexes:[self frameIndexesToCache]];
        // 遍历不需要缓存的，进行数据移除操作
        [indexesToPurge enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull stop) {
            for (NSUInteger i = range.location; i < NSMaxRange(range); i++) {
                [self.cachedFrameIndexes removeIndex:i];
                [self.cachedFramesForIndexes removeObjectForKey:@(i)];;
            }
        }];
    }
}

#pragma mark Memory Warning

- (void)growFrameCacheSizeAfterMemoryWarning:(NSNumber *)frameCacheSize
{
    self.frameCacheSizeMaxInternal = [frameCacheSize unsignedIntegerValue];
    const NSTimeInterval kResetDelay = 3.0;
    // 当内存警告小于等于3次时，接收到内存警告 2 + 3 秒后，调高缓存
    [self.weakProxy performSelector:@selector(resetFrameCacheSizeMaxInternal) withObject:nil afterDelay:kResetDelay];
}

- (void)resetFrameCacheSizeMaxInternal
{
    self.frameCacheSizeMaxInternal = TAnimatedImageFrameCacheSizeNoLimit;
}

- (void)didReceiveMemoryWarning:(NSNotification *)notification
{
    self.memoryWarningCount++;
    [NSObject cancelPreviousPerformRequestsWithTarget:self.weakProxy selector:@selector(growFrameCacheSizeAfterMemoryWarning:) object:@(TAnimatedImageFrameCacheSizeGrowAfterMemoryWarning)];
    [NSObject cancelPreviousPerformRequestsWithTarget:self.weakProxy selector:@selector(resetFrameCacheSizeMaxInternal) object:nil];
    
    // 接收到内存警告时，调低缓存
    self.frameCacheSizeMaxInternal = TAnimatedImageFrameCacheSizeLowMemory;
    
    const NSUInteger kGrowAttemptsMax = 2;
    const NSTimeInterval kGrowDelay = 2.0;
    // 当内存警告小于等于3次时，接收到内存警告2秒后，调高缓存
    if ((self.memoryWarningCount - 1) <= kGrowAttemptsMax) {
        [self.weakProxy performSelector:@selector(growFrameCacheSizeAfterMemoryWarning:) withObject:@(TAnimatedImageFrameCacheSizeGrowAfterMemoryWarning) afterDelay:kGrowDelay];
    }
}

#pragma mark - Public Methods

// 添加帧图片到缓存
- (void)addFrameIndexesToCache:(NSIndexSet *)frameIndexesToAddToCache
{
    NSRange firstRange = NSMakeRange(self.requestedFrameIndex, self.frameCount - self.requestedFrameIndex);
    NSRange secondRange = NSMakeRange(0, self.requestedFrameIndex);
    if (firstRange.length + secondRange.length != self.frameCount) {
        
    }
    
    // 添加帧图片到 正在获取的数组中
    [self.requestedFrameIndexes addIndexes:frameIndexesToAddToCache];
    
    if (!self.serialQueue) {
        _serialQueue = dispatch_queue_create("com.t.framecachingqueue", DISPATCH_QUEUE_SERIAL);
    }
    
    TAnimatedImage * __weak weakSelf = self;
    dispatch_async(self.serialQueue, ^{
        void (^frameRangeBlock) (NSRange, BOOL *) = ^(NSRange range, BOOL *stop) {
            for (NSUInteger i = range.location; i < NSMaxRange(range); i++) {
                UIImage *image = [weakSelf imageAtIndex:i];
                if (image && weakSelf) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        weakSelf.cachedFramesForIndexes[@(i)] = image;
                        [weakSelf.cachedFrameIndexes addIndex:i];
                        [weakSelf.requestedFrameIndexes removeIndex:i];
                    });
                }
            }
        };
        [frameIndexesToAddToCache enumerateRangesInRange:firstRange options:0 usingBlock:frameRangeBlock];
        [frameIndexesToAddToCache enumerateRangesInRange:secondRange options:0 usingBlock:frameRangeBlock];
    });
}

- (UIImage *)imageLazilyCachedAtIndex:(NSUInteger)index
{
    if (index >= self.frameCount) {
        return nil;
    }
    self.requestedFrameIndex = index;
    
    if ([self.cachedFrameIndexes count] < self.frameCount) {
        // 得到要缓存的帧图片
        NSMutableIndexSet *frameIndexesToAddToCacheMutable = [self frameIndexesToCache];
        // 移除已经缓存的帧图片
        [frameIndexesToAddToCacheMutable removeIndexes:self.cachedFrameIndexes];
        // 移除正在获取的帧图片
        [frameIndexesToAddToCacheMutable removeIndexes:self.requestedFrameIndexes];
        // 移除封面帧图片
        [frameIndexesToAddToCacheMutable removeIndex:self.posterImageFrameIndex];
        NSIndexSet *frameIndexesToAddToCache = [frameIndexesToAddToCacheMutable copy];
        // 最后添加要缓存的帧图片
        if ([frameIndexesToAddToCache count] > 0) {
            [self addFrameIndexesToCache:frameIndexesToAddToCache];
        }
    }
    
    UIImage *image = self.cachedFramesForIndexes[@(index)];
    
    [self purgeFrameCacheIfNeeded];
    
    return image;
}

+ (CGSize)sizeForImage:(id)image
{
    CGSize imageSize = CGSizeZero;
    if (!image) {
        return imageSize;
    }
    
    if ([image isKindOfClass:[UIImage class]]) {
        UIImage *uiImage = (UIImage *)image;
        imageSize = uiImage.size;
    }
    else if ([image isKindOfClass:[TAnimatedImage class]]) {
        TAnimatedImage *animatedImage = (TAnimatedImage *)image;
        imageSize = animatedImage.size;
    }
    else {
        
    }
    
    return imageSize;
}

#pragma mark - Private Methods
#pragma mark Frame Loading

+ (UIImage *)predrawnImageFromImage:(UIImage *)imageToPredraw
{
    CGColorSpaceRef colorSpaceDeviceRGBRef = CGColorSpaceCreateDeviceRGB();
    if (!colorSpaceDeviceRGBRef) {
        return imageToPredraw;
    }
    size_t numberOfComponents = CGColorSpaceGetNumberOfComponents(colorSpaceDeviceRGBRef) + 1;
    
    void *data = NULL;
    size_t width = imageToPredraw.size.width;
    size_t height = imageToPredraw.size.height;
    size_t bitsPerComponent = CHAR_BIT;
    
    size_t bitsPerPixel = (bitsPerComponent * numberOfComponents);
    size_t bytesPerPixel = (bitsPerPixel / BYTE_SIZE);
    size_t bytesPerRow = (bytesPerPixel * width);
    
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
    
    CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(imageToPredraw.CGImage);
    if (alphaInfo == kCGImageAlphaNone || alphaInfo == kCGImageAlphaOnly) {
        alphaInfo = kCGImageAlphaNoneSkipFirst;
    }
    else if (alphaInfo == kCGImageAlphaFirst) {
        alphaInfo = kCGImageAlphaPremultipliedFirst;
    }
    else if (alphaInfo == kCGImageAlphaLast) {
        alphaInfo = kCGImageAlphaPremultipliedLast;
    }
    
    bitmapInfo |= alphaInfo;
    
    CGContextRef bitmapContextRef = CGBitmapContextCreate(data, width, height, bitsPerComponent, bytesPerRow, colorSpaceDeviceRGBRef, bitmapInfo);
    CGColorSpaceRelease(colorSpaceDeviceRGBRef);
    
    if (!bitmapContextRef) {
        return imageToPredraw;
    }
    
    CGContextDrawImage(bitmapContextRef, CGRectMake(0.0, 0.0, imageToPredraw.size.width, imageToPredraw.size.height), imageToPredraw.CGImage);
    CGImageRef predrawnImageRef = CGBitmapContextCreateImage(bitmapContextRef);
    UIImage *predrawnImage = [UIImage imageWithCGImage:predrawnImageRef scale:imageToPredraw.scale orientation:imageToPredraw.imageOrientation];
    CGImageRelease(predrawnImageRef);
    CGContextRelease(bitmapContextRef);
    
    if (!predrawnImage) {
        return imageToPredraw;
    }
    
    return predrawnImage;
}

- (UIImage *)imageAtIndex:(NSUInteger)index
{
    CGImageRef imageRef = CGImageSourceCreateImageAtIndex(_imageSource, index, NULL);
    
    if (!imageRef) {
        return nil;
    }
    
    UIImage *image = [UIImage imageWithCGImage:imageRef];
    CFRelease(imageRef);
    
    if (self.isPredrawingEnabled) {
        image = [[self class] predrawnImageFromImage:image];
    }
    
    return image;
}

@end
