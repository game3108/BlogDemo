//
//  _ASAsyncTransactionContainer.m
//  AsyncDisplayKit
//
//  Copyright (c) 2014-present, Facebook, Inc.  All rights reserved.
//  This source code is licensed under the BSD-style license found in the
//  LICENSE file in the root directory of this source tree. An additional grant
//  of patent rights can be found in the PATENTS file in the same directory.
//

#import "_ASAsyncTransactionContainer+Private.h"

#import "_ASAsyncTransaction.h"
#import "_ASAsyncTransactionGroup.h"
#import <objc/runtime.h>

static const char *ASDisplayNodeAssociatedTransactionsKey = "ASAssociatedTransactions";
static const char *ASDisplayNodeAssociatedCurrentTransactionKey = "ASAssociatedCurrentTransaction";

@implementation CALayer (ASAsyncTransactionContainerTransactions)

//使用associateObject返回transaction对象
- (_ASAsyncTransaction *)asyncdisplaykit_currentAsyncLayerTransaction
{
  return objc_getAssociatedObject(self, ASDisplayNodeAssociatedCurrentTransactionKey);
}

//使用associateObject存储transaction对象
- (void)asyncdisplaykit_setCurrentAsyncLayerTransaction:(_ASAsyncTransaction *)transaction
{
  objc_setAssociatedObject(self, ASDisplayNodeAssociatedCurrentTransactionKey, transaction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

//使用associateObject返回hashtable对象
- (NSHashTable *)asyncdisplaykit_asyncLayerTransactions
{
  return objc_getAssociatedObject(self, ASDisplayNodeAssociatedTransactionsKey);
}

//使用associateObject存储hashtable对象
- (void)asyncdisplaykit_setAsyncLayerTransactions:(NSHashTable *)transactions
{
  objc_setAssociatedObject(self, ASDisplayNodeAssociatedTransactionsKey, transactions, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// No-ops in the base class. Mostly exposed for testing.
// 在基类没有操作，大多数用来测试
- (void)asyncdisplaykit_asyncTransactionContainerWillBeginTransaction:(_ASAsyncTransaction *)transaction {}
- (void)asyncdisplaykit_asyncTransactionContainerDidCompleteTransaction:(_ASAsyncTransaction *)transaction {}
@end

static const char *ASAsyncTransactionIsContainerKey = "ASTransactionIsContainer";

@implementation CALayer (ASDisplayNodeAsyncTransactionContainer)

- (BOOL)asyncdisplaykit_isAsyncTransactionContainer
{
  CFBooleanRef isContainerBool = (__bridge CFBooleanRef)objc_getAssociatedObject(self, ASAsyncTransactionIsContainerKey);
  BOOL isContainer = (isContainerBool == kCFBooleanTrue);
  return isContainer;
}

- (void)asyncdisplaykit_setAsyncTransactionContainer:(BOOL)isContainer
{
  objc_setAssociatedObject(self, ASAsyncTransactionIsContainerKey, (id)(isContainer ? kCFBooleanTrue : kCFBooleanFalse), OBJC_ASSOCIATION_ASSIGN);
}

- (ASAsyncTransactionContainerState)asyncdisplaykit_asyncTransactionContainerState
{
  return ([self.asyncdisplaykit_asyncLayerTransactions count] == 0) ? ASAsyncTransactionContainerStateNoTransactions : ASAsyncTransactionContainerStatePendingTransactions;
}

- (void)asyncdisplaykit_cancelAsyncTransactions
{
  // If there was an open transaction, commit and clear the current transaction. Otherwise:
  // (1) The run loop observer will try to commit a canceled transaction which is not allowed
  // (2) We leave the canceled transaction attached to the layer, dooming future operations
  // 如果这里是一个open的transaction，提交并清除当前的transaction，否则
  // (1) runloop的观察者会尝试去提交一个已经取消了的transaction，这个是不允许的
  // (2) 我们留下了一个取消的transaction链接到layer上，阻止未来的操作
  _ASAsyncTransaction *currentTransaction = self.asyncdisplaykit_currentAsyncLayerTransaction;
  [currentTransaction commit];
  self.asyncdisplaykit_currentAsyncLayerTransaction = nil;

  for (_ASAsyncTransaction *transaction in [self.asyncdisplaykit_asyncLayerTransactions copy]) {
    [transaction cancel];
  }
}

- (void)asyncdisplaykit_asyncTransactionContainerStateDidChange
{
  id delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(asyncdisplaykit_asyncTransactionContainerStateDidChange)]) {
    [delegate asyncdisplaykit_asyncTransactionContainerStateDidChange];
  }
}

- (_ASAsyncTransaction *)asyncdisplaykit_asyncTransaction
{
  _ASAsyncTransaction *transaction = self.asyncdisplaykit_currentAsyncLayerTransaction;
  if (transaction == nil) {
    NSHashTable *transactions = self.asyncdisplaykit_asyncLayerTransactions;
    if (transactions == nil) {
      transactions = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
      self.asyncdisplaykit_asyncLayerTransactions = transactions;
    }
    transaction = [[_ASAsyncTransaction alloc] initWithCallbackQueue:dispatch_get_main_queue() completionBlock:^(_ASAsyncTransaction *completedTransaction, BOOL cancelled) {
      [transactions removeObject:completedTransaction];
      [self asyncdisplaykit_asyncTransactionContainerDidCompleteTransaction:completedTransaction];
      if ([transactions count] == 0) {
        [self asyncdisplaykit_asyncTransactionContainerStateDidChange];
      }
    }];
    [transactions addObject:transaction];
    self.asyncdisplaykit_currentAsyncLayerTransaction = transaction;
    [self asyncdisplaykit_asyncTransactionContainerWillBeginTransaction:transaction];
    if ([transactions count] == 1) {
      [self asyncdisplaykit_asyncTransactionContainerStateDidChange];
    }
  }
  [[_ASAsyncTransactionGroup mainTransactionGroup] addTransactionContainer:self];
  return transaction;
}

- (CALayer *)asyncdisplaykit_parentTransactionContainer
{
  CALayer *containerLayer = self;
  while (containerLayer && !containerLayer.asyncdisplaykit_isAsyncTransactionContainer) {
    containerLayer = containerLayer.superlayer;
  }
  return containerLayer;
}

@end

@implementation UIView (ASDisplayNodeAsyncTransactionContainer)

- (BOOL)asyncdisplaykit_isAsyncTransactionContainer
{
  return self.layer.asyncdisplaykit_isAsyncTransactionContainer;
}

- (void)asyncdisplaykit_setAsyncTransactionContainer:(BOOL)asyncTransactionContainer
{
  self.layer.asyncdisplaykit_asyncTransactionContainer = asyncTransactionContainer;
}

- (ASAsyncTransactionContainerState)asyncdisplaykit_asyncTransactionContainerState
{
  return self.layer.asyncdisplaykit_asyncTransactionContainerState;
}

- (void)asyncdisplaykit_cancelAsyncTransactions
{
  [self.layer asyncdisplaykit_cancelAsyncTransactions];
}

- (void)asyncdisplaykit_asyncTransactionContainerStateDidChange
{
  // No-op in the base class.
}

@end
