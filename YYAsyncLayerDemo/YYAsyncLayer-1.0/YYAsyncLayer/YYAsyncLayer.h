//
//  YYAsyncLayer.h
//  YYKit <https://github.com/ibireme/YYKit>
//
//  Created by ibireme on 15/4/11.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#if __has_include(<YYAsyncLayer/YYAsyncLayer.h>)
FOUNDATION_EXPORT double YYAsyncLayerVersionNumber;
FOUNDATION_EXPORT const unsigned char YYAsyncLayerVersionString[];
#import <YYAsyncLayer/YYSentinel.h>
#import <YYAsyncLayer/YYTransaction.h>
#else
#import "YYSentinel.h"
#import "YYTransaction.h"
#endif

@class YYAsyncLayerDisplayTask;

NS_ASSUME_NONNULL_BEGIN

/**
 The YYAsyncLayer class is a subclass of CALayer used for render contents asynchronously.
 
 @discussion When the layer need update it's contents, it will ask the delegate
 for a async display task to render the contents in a background queue.
 */

/**
 YYAsyncLayer是异步渲染的CALayer子类
 */
@interface YYAsyncLayer : CALayer
/// Whether the render code is executed in background. Default is YES.
//是否异步渲染
@property BOOL displaysAsynchronously;
@end


/**
 The YYAsyncLayer's delegate protocol. The delegate of the YYAsyncLayer (typically a UIView)
 must implements the method in this protocol.
 */

/**
 YYAsyncLayer's的delegate协议，一般是uiview。必须实现这个方法
 */
@protocol YYAsyncLayerDelegate <NSObject>
@required
/// This method is called to return a new display task when the layer's contents need update.
//当layer的contents需要更新的时候，返回一个新的展示任务
- (YYAsyncLayerDisplayTask *)newAsyncDisplayTask;
@end


/**
 A display task used by YYAsyncLayer to render the contents in background queue.
 */

/**
 YYAsyncLayer在后台渲染contents的显示任务类
 */
@interface YYAsyncLayerDisplayTask : NSObject

/**
 This block will be called before the asynchronous drawing begins.
 It will be called on the main thread.
 
 @param layer  The layer.
 */

/**
 这个block会在异步渲染开始的前调用，只在主线程调用。
 */
@property (nullable, nonatomic, copy) void (^willDisplay)(CALayer *layer);

/**
 This block is called to draw the layer's contents.
 
 @discussion This block may be called on main thread or background thread,
 so is should be thread-safe.
 
 @param context      A new bitmap content created by layer.
 @param size         The content size (typically same as layer's bound size).
 @param isCancelled  If this block returns `YES`, the method should cancel the
 drawing process and return as quickly as possible.
 */

/**
 这个block会调用去显示layer的内容
 */
@property (nullable, nonatomic, copy) void (^display)(CGContextRef context, CGSize size, BOOL(^isCancelled)(void));

/**
 This block will be called after the asynchronous drawing finished.
 It will be called on the main thread.
 
 @param layer  The layer.
 @param finished  If the draw process is cancelled, it's `NO`, otherwise it's `YES`;
 */

/**
 这个block会在异步渲染结束后调用，只在主线程调用。
 */
@property (nullable, nonatomic, copy) void (^didDisplay)(CALayer *layer, BOOL finished);

@end

NS_ASSUME_NONNULL_END
