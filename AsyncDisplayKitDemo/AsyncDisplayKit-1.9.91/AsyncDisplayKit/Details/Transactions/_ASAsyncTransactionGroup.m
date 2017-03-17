//
//  _ASAsyncTransactionGroup.m
//  AsyncDisplayKit
//
//  Copyright (c) 2014-present, Facebook, Inc.  All rights reserved.
//  This source code is licensed under the BSD-style license found in the
//  LICENSE file in the root directory of this source tree. An additional grant
//  of patent rights can be found in the PATENTS file in the same directory.
//

#import "ASAssert.h"

#import "_ASAsyncTransaction.h"
#import "_ASAsyncTransactionGroup.h"
#import "_ASAsyncTransactionContainer+Private.h"

//runloop回调
static void _transactionGroupRunLoopObserverCallback(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info);

@interface _ASAsyncTransactionGroup ()
//注册runloop回调
+ (void)registerTransactionGroupAsMainRunloopObserver:(_ASAsyncTransactionGroup *)transactionGroup;
//提交一次业务请求
- (void)commit;
@end

@implementation _ASAsyncTransactionGroup {
  //包含的图层
  NSHashTable *_containerLayers;
}

//单例
+ (_ASAsyncTransactionGroup *)mainTransactionGroup
{
  //主线程判断
  ASDisplayNodeAssertMainThread();
  static _ASAsyncTransactionGroup *mainTransactionGroup;

  if (mainTransactionGroup == nil) {
    mainTransactionGroup = [[_ASAsyncTransactionGroup alloc] init];
    //将group注册到runloop
    [self registerTransactionGroupAsMainRunloopObserver:mainTransactionGroup];
  }
  return mainTransactionGroup;
}

+ (void)registerTransactionGroupAsMainRunloopObserver:(_ASAsyncTransactionGroup *)transactionGroup
{
  //主线程判断
  ASDisplayNodeAssertMainThread();
  static CFRunLoopObserverRef observer;
  ASDisplayNodeAssert(observer == NULL, @"A _ASAsyncTransactionGroup should not be registered on the main runloop twice");
  // defer the commit of the transaction so we can add more during the current runloop iteration
  //推迟业务的提交是的我们可以添加更多的在当前runloop循环中
  CFRunLoopRef runLoop = CFRunLoopGetCurrent();
  //注册runloop的kCFRunLoopBeforeWaiting与kCFRunLoopExit事件
  CFOptionFlags activities = (kCFRunLoopBeforeWaiting | // before the run loop starts sleeping
                              kCFRunLoopExit);          // before exiting a runloop run
  CFRunLoopObserverContext context = {
    0,           // version
    (__bridge void *)transactionGroup,  // info
    &CFRetain,   // retain
    &CFRelease,  // release
    NULL         // copyDescription
  };
  //构建observer
  observer = CFRunLoopObserverCreate(NULL,        // allocator
                                     activities,  // activities
                                     YES,         // repeats
                                     INT_MAX,     // order after CA transaction commits
                                     &_transactionGroupRunLoopObserverCallback,  // callback
                                     &context);   // context
  //添加observer到kCFRunLoopCommonModes
  CFRunLoopAddObserver(runLoop, observer, kCFRunLoopCommonModes);
  CFRelease(observer);
}

- (instancetype)init
{
  if ((self = [super init])) {
    _containerLayers = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
  }
  return self;
}

- (void)addTransactionContainer:(CALayer *)containerLayer
{
  ASDisplayNodeAssertMainThread();
  ASDisplayNodeAssert(containerLayer != nil, @"No container");
  //添加图层
  [_containerLayers addObject:containerLayer];
}

//提交绘画
- (void)commit
{
  ASDisplayNodeAssertMainThread();

  if ([_containerLayers count]) {
    //存储hashtable
    NSHashTable *containerLayersToCommit = _containerLayers;
    //重制原来的hashtable
    _containerLayers = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];

    //遍历layer
    for (CALayer *containerLayer in containerLayersToCommit) {
      // Note that the act of committing a transaction may open a new transaction,
      // so we must nil out the transaction we're committing first.
      // 注意提交一个业务的操作可能会打开一个新的业务
      // 因此我们必须设置业务为空当我们提交业务的时候
      _ASAsyncTransaction *transaction = containerLayer.asyncdisplaykit_currentAsyncLayerTransaction;
      containerLayer.asyncdisplaykit_currentAsyncLayerTransaction = nil;
      //业务提交
      [transaction commit];
    }
  }
}

+ (void)commit
{
  //提交group内的业务逻辑
  [[_ASAsyncTransactionGroup mainTransactionGroup] commit];
}

@end

//回调函数提交业务逻辑
static void _transactionGroupRunLoopObserverCallback(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info)
{
  ASDisplayNodeCAssertMainThread();
  _ASAsyncTransactionGroup *group = (__bridge _ASAsyncTransactionGroup *)info;
  [group commit];
}
