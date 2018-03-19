//
//  TWeakProxy.h
//  Examda
//
//  Created by liqi on 2018/3/14.
//  Copyright © 2018年 长沙二三三网络科技有限公司. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 1.对象A 和 对象B 之间互相持有，会造成循环引用
     ___              ___
    |   | ——————————>|   |
    | A |            | B |
    |___| <——————————|___|
 
 2.可以创建一个临时 对象C，对 对象A 引弱用，然后 对象B 持有 对象C 来避免循环引用
     ___                          ___
    |   | ——————————————————————>|   |
    | A |             ___        | B |
    |___| <- - - - - |   |<——————|___|
                     | C |
                     |___|
 
 常用的比如： NSTimer or CADisplayLink.
 
 sample code:
 
 @implementation View {
    NSTimer *_timer;
 }
 
 - (void)initTimer {
    TWeakProxy *proxy = [TWeakProxy proxyWithTarget:self];
    _timer = [NSTimer timerWithTimeInterval:0.1 target:proxy selector:@selector(change:) userInfo:nil repeats:YES];
 }
 
 - (void)change:(NSTimer *)timer {...}
 @end
 */

@interface TWeakProxy : NSProxy

/**
 要弱引用的目标对象
 */
@property (nullable, nonatomic, weak, readonly) id target;

/**
 为 目标对象 创建一个 弱引用代理
 
 @param target 目标对象
 @return 弱引用代理
 */
- (instancetype)initWithTarget:(nullable id)target;

/**
 为 目标对象 创建一个 弱引用代理

 @param target 目标对象
 @return 弱引用代理
 */
+ (instancetype)proxyWithTarget:(nullable id)target;

@end

NS_ASSUME_NONNULL_END
