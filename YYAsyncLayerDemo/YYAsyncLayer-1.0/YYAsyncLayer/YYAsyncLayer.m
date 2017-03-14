//
//  YYAsyncLayer.m
//  YYKit <https://github.com/ibireme/YYKit>
//
//  Created by ibireme on 15/4/11.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "YYAsyncLayer.h"
#import "YYSentinel.h"

#if __has_include("YYDispatchQueuePool.h")
#import "YYDispatchQueuePool.h"
#else
#import <libkern/OSAtomic.h>
#endif

/// Global display queue, used for content rendering.
//全局显示线程，给content渲染用
static dispatch_queue_t YYAsyncLayerGetDisplayQueue() {
    //如果存在YYDispatchQueuePool
#ifdef YYDispatchQueuePool_h
    return YYDispatchQueueGetForQOS(NSQualityOfServiceUserInitiated);
#else
#define MAX_QUEUE_COUNT 16
    static int queueCount;
    static dispatch_queue_t queues[MAX_QUEUE_COUNT];
    static dispatch_once_t onceToken;
    static int32_t counter = 0;
    dispatch_once(&onceToken, ^{
        //处理器数量，最多创建16个serial线程
        queueCount = (int)[NSProcessInfo processInfo].activeProcessorCount;
        queueCount = queueCount < 1 ? 1 : queueCount > MAX_QUEUE_COUNT ? MAX_QUEUE_COUNT : queueCount;
        if ([UIDevice currentDevice].systemVersion.floatValue >= 8.0) {
            for (NSUInteger i = 0; i < queueCount; i++) {
                dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
                queues[i] = dispatch_queue_create("com.ibireme.yykit.render", attr);
            }
        } else {
            for (NSUInteger i = 0; i < queueCount; i++) {
                queues[i] = dispatch_queue_create("com.ibireme.yykit.render", DISPATCH_QUEUE_SERIAL);
                dispatch_set_target_queue(queues[i], dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
            }
        }
    });
    //循环获取相应的线程
    int32_t cur = OSAtomicIncrement32(&counter);
    if (cur < 0) cur = -cur;
    return queues[(cur) % queueCount];
#undef MAX_QUEUE_COUNT
#endif
}

//释放线程
static dispatch_queue_t YYAsyncLayerGetReleaseQueue() {
#ifdef YYDispatchQueuePool_h
    return YYDispatchQueueGetForQOS(NSQualityOfServiceDefault);
#else
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
#endif
}


@implementation YYAsyncLayerDisplayTask
@end


@implementation YYAsyncLayer {
    //计数，用于取消异步绘制
    YYSentinel *_sentinel;
}

#pragma mark - Override

+ (id)defaultValueForKey:(NSString *)key {
    if ([key isEqualToString:@"displaysAsynchronously"]) {
        return @(YES);
    } else {
        return [super defaultValueForKey:key];
    }
}

- (instancetype)init {
    self = [super init];
    static CGFloat scale; //global
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        scale = [UIScreen mainScreen].scale;
    });
    self.contentsScale = scale;
    _sentinel = [YYSentinel new];
    _displaysAsynchronously = YES;
    return self;
}


- (void)dealloc {
    [_sentinel increase];
}

//需要重新渲染的时候，取消原来没有完成的异步渲染
- (void)setNeedsDisplay {
    [self _cancelAsyncDisplay];
    [super setNeedsDisplay];
}


/**
 重写展示方法，设置contents内容
 */
- (void)display {
    super.contents = super.contents;
    [self _displayAsync:_displaysAsynchronously];
}

#pragma mark - Private


- (void)_displayAsync:(BOOL)async {
    //获取delegate对象，这边默认是CALayer的delegate，持有它的uiview
    __strong id<YYAsyncLayerDelegate> delegate = self.delegate;
    //delegate的初始化方法
    YYAsyncLayerDisplayTask *task = [delegate newAsyncDisplayTask];
    //没有展示block，就直接调用其他两个block返回
    if (!task.display) {
        if (task.willDisplay) task.willDisplay(self);
        self.contents = nil;
        if (task.didDisplay) task.didDisplay(self, YES);
        return;
    }
    
    //异步
    if (async) {
        //先调用willdisplay
        if (task.willDisplay) task.willDisplay(self);
        //获取计数
        YYSentinel *sentinel = _sentinel;
        int32_t value = sentinel.value;
        //用计数判断是否已经取消
        BOOL (^isCancelled)() = ^BOOL() {
            return value != sentinel.value;
        };
        CGSize size = self.bounds.size;
        BOOL opaque = self.opaque;
        CGFloat scale = self.contentsScale;
        //长宽<1，直接清除contents内容
        if (size.width < 1 || size.height < 1) {
            //获取contents内容
            CGImageRef image = (__bridge_retained CGImageRef)(self.contents);
            //清除内容
            self.contents = nil;
            //如果是图片就release图片
            if (image) {
                dispatch_async(YYAsyncLayerGetReleaseQueue(), ^{
                    CFRelease(image);
                });
            }
            //已经展示完成block，finish为yes
            if (task.didDisplay) task.didDisplay(self, YES);
            return;
        }
        
        //异步线程调用
        dispatch_async(YYAsyncLayerGetDisplayQueue(), ^{
            //是否取消
            if (isCancelled()) return;
            //创建Core Graphic bitmap context
            UIGraphicsBeginImageContextWithOptions(size, opaque, scale);
            CGContextRef context = UIGraphicsGetCurrentContext();
            //返回context进行展示
            task.display(context, size, isCancelled);
            //如果取消，停止渲染
            if (isCancelled()) {
                //结束context，并且展示完成block，finish为no
                UIGraphicsEndImageContext();
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (task.didDisplay) task.didDisplay(self, NO);
                });
                return;
            }
            //获取当前画布
            UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
            //结束context
            UIGraphicsEndImageContext();
            //如果取消停止渲染
            if (isCancelled()) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (task.didDisplay) task.didDisplay(self, NO);
                });
                return;
            }
            //返回主线程
            dispatch_async(dispatch_get_main_queue(), ^{
                //如果取消，停止渲染
                if (isCancelled()) {
                    if (task.didDisplay) task.didDisplay(self, NO);
                } else {
                    //主线程设置contents内容进行展示
                    self.contents = (__bridge id)(image.CGImage);
                    //已经展示完成block，finish为yes
                    if (task.didDisplay) task.didDisplay(self, YES);
                }
            });
        });
    } else {
        //同步展示，直接increase，停止异步展示
        [_sentinel increase];
        if (task.willDisplay) task.willDisplay(self);
        //直接创建Core Graphic bitmap context
        UIGraphicsBeginImageContextWithOptions(self.bounds.size, self.opaque, self.contentsScale);
        CGContextRef context = UIGraphicsGetCurrentContext();
        task.display(context, self.bounds.size, ^{return NO;});
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        //进行展示
        self.contents = (__bridge id)(image.CGImage);
        if (task.didDisplay) task.didDisplay(self, YES);
    }
}

- (void)_cancelAsyncDisplay {
    [_sentinel increase];
}

@end
