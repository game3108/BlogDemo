//
//  _ASAsyncTransactionContainer.h
//  AsyncDisplayKit
//
//  Copyright (c) 2014-present, Facebook, Inc.  All rights reserved.
//  This source code is licensed under the BSD-style license found in the
//  LICENSE file in the root directory of this source tree. An additional grant
//  of patent rights can be found in the PATENTS file in the same directory.
//

#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>


@class _ASAsyncTransaction;

typedef NS_ENUM(NSUInteger, ASAsyncTransactionContainerState) {
  /**
   The async container has no outstanding transactions.
   Whatever it is displaying is up-to-date.
   */
  /**
   异步container没有好的业务
   无论是否正在显示
   */
  ASAsyncTransactionContainerStateNoTransactions = 0,
  /**
   The async container has one or more outstanding async transactions.
   Its contents may be out of date or showing a placeholder, depending on the configuration of the contained ASDisplayLayers.
   */
  /**
   异步container有一个或者更多的杰出的异步业务
   它的内容可能已经过时或者显示了占位符，依赖包含的ASDisplayLayers的设置
   */
  ASAsyncTransactionContainerStatePendingTransactions,
};

@protocol ASDisplayNodeAsyncTransactionContainer

/**
 @summary If YES, the receiver is marked as a container for async display, grouping all of the async display calls
 in the layer hierarchy below the receiver together in a single ASAsyncTransaction.

 @default NO
 */

/**
 @summary 如果是yes，接受者会被标记为异步显示的容易，组合所有在接受者下面的异步显示图层层次的显示回调在单独的ASAsyncTransaction
 
 @default NO
 */
@property (nonatomic, assign, getter=asyncdisplaykit_isAsyncTransactionContainer, setter=asyncdisplaykit_setAsyncTransactionContainer:) BOOL asyncdisplaykit_asyncTransactionContainer;

/**
 @summary The current state of the receiver; indicates if it is currently performing asynchronous operations or if all operations have finished/canceled.
 */

/**
 @summary 当前接受者的状态。表明它当前提供异步操作或者所有操作已经完结/取消
 */
@property (nonatomic, readonly, assign) ASAsyncTransactionContainerState asyncdisplaykit_asyncTransactionContainerState;

/**
 @summary Cancels all async transactions on the receiver.
 */

/**
 @summary 取消所有接受者的异步业务
 */
- (void)asyncdisplaykit_cancelAsyncTransactions;

/**
 @summary Invoked when the asyncdisplaykit_asyncTransactionContainerState property changes.
 @desc You may want to override this in a CALayer or UIView subclass to take appropriate action (such as hiding content while it renders).
 */

/**
 @summary 调用当asyncdisplaykit_asyncTransactionContainerState参数表话
 @desc 你也许需要重写这个在一个CALayer或者UIView的子类去采用合适的动作(比如隐藏content当它渲染的时候)
 */
- (void)asyncdisplaykit_asyncTransactionContainerStateDidChange;

@end

@interface CALayer (ASDisplayNodeAsyncTransactionContainer) <ASDisplayNodeAsyncTransactionContainer>
/**
 @summary Returns the current async transaction for this container layer. A new transaction is created if one
 did not already exist. This method will always return an open, uncommitted transaction.
 @desc asyncdisplaykit_isAsyncTransactionContainer does not need to be YES for this to return a transaction.
 */

/**
 @summary 返回当前这个容器layer的异步业务。一个新的业务将会被创建如果一个不确实存在。这个方法将会一直返回一个开放的，没有提交的业务。
 @desc asyncdisplaykit_isAsyncTransactionContainer不需要去设置为yes区返回一个业务
 */
@property (nonatomic, readonly, strong) _ASAsyncTransaction *asyncdisplaykit_asyncTransaction;

/**
 @summary Goes up the superlayer chain until it finds the first layer with asyncdisplaykit_isAsyncTransactionContainer=YES (including the receiver) and returns it.
 Returns nil if no parent container is found.
 */

/**
 @summary 上升到父类图层链知道它发现的asyncdisplaykit_isAsyncTransactionContainer=YES的第一个图层（包括接受者）然后返回它
 如果没有父类容器被发现则返回nil
 */
@property (nonatomic, readonly, strong) CALayer *asyncdisplaykit_parentTransactionContainer;
@end

@interface UIView (ASDisplayNodeAsyncTransactionContainer) <ASDisplayNodeAsyncTransactionContainer>
@end
