//
//  TAnimatedImageView.h
//  TAnimatedImage
//
//  Created by liqi on 2018/3/16.
//  Copyright © 2018年 apple. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "TAnimatedImage.h"

NS_ASSUME_NONNULL_BEGIN

@interface TAnimatedImageView : UIImageView

/**
 GIF Image
 */
@property (nonatomic, strong, nullable) TAnimatedImage *animatedImage;

/**
 当前播放帧
 */
@property (nonatomic, strong, readonly, nullable) UIImage *currentFrame;

/**
 当前播放帧的位置
 */
@property (nonatomic, assign, readonly) NSUInteger currentFrameIndex;

/**
 NSRunLoopModes 设置模式
 */
@property (nonatomic, copy, nullable) NSString *runloopMode;

/**
 GIF播放完成回调(无限循环没有回调)
 */
@property (nonatomic, copy, nullable) void(^loopCompletionBlock)(NSUInteger loopCountRemaining);

@end

NS_ASSUME_NONNULL_END
