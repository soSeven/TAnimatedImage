//
//  TAnimatedImage.h
//  TAnimatedImage
//
//  Created by liqi on 2018/3/14.
//  Copyright © 2018年 apple. All rights reserved.
//

#import <UIKit/UIKit.h>

UIKIT_EXTERN const NSTimeInterval KTAnimatedImageDelayTimeIntervalMinimum;

NS_ASSUME_NONNULL_BEGIN

@interface TAnimatedImage : NSObject

/**
 GIF动画的封面帧图片
 */
@property (nonatomic, strong, readonly, nullable) UIImage *posterImage;

/**
 GIF动画的封面帧图片size
 */
@property (nonatomic, assign, readonly) CGSize size;

/**
 GIF动画的播放循环次数
 */
@property (nonatomic, assign, readonly) NSUInteger loopCount;

/**
 GIF动画中每帧图片的展示时间
 */
@property (nonatomic, strong, readonly) NSDictionary *delayTimesForIndexes;

/**
 GIF动画中图片帧的数量
 */
@property (nonatomic, assign, readonly) NSUInteger frameCount;

/**
 当前被缓存的帧图片的总数量
 */
@property (nonatomic, assign, readonly) NSUInteger frameCacheSizeCurrent;

/**
 允许缓存的帧图片的最大数量
 */
@property (nonatomic, assign) NSUInteger frameCacheSizeMax;

/**
 GIF二进制数据
 */
@property (nonatomic, strong, readonly, nullable) NSData *data;

/**
 初始化 TAnimatedImage

 @param data GIF数据
 @param optimalFrameCacheSize 需要缓存的帧数
 @param isPredrawingEnabled 是否对每帧图片重新绘制
 @return TAnimatedImage
 */
- (instancetype)initWithAnimatedGIFData:(nullable NSData *)data
                  optimalFrameCacheSize:(NSUInteger)optimalFrameCacheSize
                      predrawingEnabled:(BOOL)isPredrawingEnabled NS_DESIGNATED_INITIALIZER;

/**
 初始化 TAnimatedImage
 根据GIF大小，定制 缓存的帧数
 对每帧图片重新绘制 isPredrawingEnabled = YES
 
 @param data GIF数据
 @return TAnimatedImage
 */
- (instancetype)initWithAnimatedGIFData:(nullable NSData *)data;


/**
 初始化 TAnimatedImage
 根据GIF大小，定制 缓存的帧数
 对每帧图片重新绘制 isPredrawingEnabled = YES
 
 @param data GIF数据
 @return TAnimatedImage
 */
+ (instancetype)animatedImageWithGIFData:(nullable NSData *)data;

/**
 根据 索引 从缓存中加载 索引位置的帧图片

 @param index 索引
 @return 索引位置的帧图片
 */
- (UIImage *)imageLazilyCachedAtIndex:(NSUInteger)index;

/**
 类方法 计算 TAnimatedImage 图片的 大小
 如果是 TAnimatedImage，取封面帧图片的大小

 @param image 计算对象
 @return 图片的大小
 */
+ (CGSize)sizeForImage:(id)image;

@end

NS_ASSUME_NONNULL_END
