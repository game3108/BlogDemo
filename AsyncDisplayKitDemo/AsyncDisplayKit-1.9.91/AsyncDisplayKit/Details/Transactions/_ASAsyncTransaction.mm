//
//  _ASAsyncTransaction.mm
//  AsyncDisplayKit
//
//  Copyright (c) 2014-present, Facebook, Inc.  All rights reserved.
//  This source code is licensed under the BSD-style license found in the
//  LICENSE file in the root directory of this source tree. An additional grant
//  of patent rights can be found in the PATENTS file in the same directory.
//

#import "_ASAsyncTransaction.h"
#import "_ASAsyncTransactionGroup.h"
#import "ASAssert.h"
#import "ASThread.h"
#import <list>
#import <map>

NSInteger const ASDefaultTransactionPriority = 0;

@interface ASDisplayNodeAsyncTransactionOperation : NSObject
- (instancetype)initWithOperationCompletionBlock:(asyncdisplaykit_async_transaction_operation_completion_block_t)operationCompletionBlock;
@property (nonatomic, copy) asyncdisplaykit_async_transaction_operation_completion_block_t operationCompletionBlock;
@property (nonatomic, strong) id<NSObject> value; // set on bg queue by the operation block
@end

@implementation ASDisplayNodeAsyncTransactionOperation

- (instancetype)initWithOperationCompletionBlock:(asyncdisplaykit_async_transaction_operation_completion_block_t)operationCompletionBlock
{
  if ((self = [super init])) {
    _operationCompletionBlock = [operationCompletionBlock copy];
  }
  return self;
}

- (void)dealloc
{
  ASDisplayNodeAssertNil(_operationCompletionBlock, @"Should have been called and released before -dealloc");
}

- (void)callAndReleaseCompletionBlock:(BOOL)canceled;
{
  if (_operationCompletionBlock) {
    _operationCompletionBlock(self.value, canceled);
    // Guarantee that _operationCompletionBlock is released on _callbackQueue:
    // 确保_operationCompletionBlock是在_callbackQueue上释放
    self.operationCompletionBlock = nil;
  }
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"<ASDisplayNodeAsyncTransactionOperation: %p - value = %@", self, self.value];
}

@end

// Lightweight operation queue for _ASAsyncTransaction that limits number of spawned threads
// 情况的操作队列，给_ASAsyncTransaction限制产生的线程数量
class ASAsyncTransactionQueue
{
public:
  
  // Similar to dispatch_group_t
  // 类似dispatch_group_t
  class Group
  {
  public:
    // call when group is no longer needed; after last scheduled operation the group will delete itself
    // 当group不在需要的时候调用，在最后的有计划的操作里，group会删除它自己
    virtual void release() = 0;
    
    // schedule block on given queue
    // 有计划的block在给定的queue上
    virtual void schedule(NSInteger priority, dispatch_queue_t queue, dispatch_block_t block) = 0;
    
    // dispatch block on given queue when all previously scheduled blocks finished executing
    // 分发block到给定的queue当所有之前的有计划的block完成执行
    virtual void notify(dispatch_queue_t queue, dispatch_block_t block) = 0;
    
    // used when manually executing blocks
    // 手动执行block
    virtual void enter() = 0;
    virtual void leave() = 0;
    
    // wait until all scheduled blocks finished executing
    // 等待知道所有计划的block完成执行
    virtual void wait() = 0;
    
  protected:
    virtual ~Group() { }; // call release() instead
  };
  
  // Create new group
  Group *createGroup();
  
  static ASAsyncTransactionQueue &instance();
  
private:
  
  struct GroupNotify
  {
    dispatch_block_t _block;
    dispatch_queue_t _queue;
  };
  
  class GroupImpl : public Group
  {
  public:
    GroupImpl(ASAsyncTransactionQueue &queue)
      : _pendingOperations(0)
      , _releaseCalled(false)
      , _queue(queue)
    {
    }
    
    virtual void release();
    virtual void schedule(NSInteger priority, dispatch_queue_t queue, dispatch_block_t block);
    virtual void notify(dispatch_queue_t queue, dispatch_block_t block);
    virtual void enter();
    virtual void leave();
    virtual void wait();
    
    int _pendingOperations;
    std::list<GroupNotify> _notifyList;
    ASDN::Condition _condition;
    BOOL _releaseCalled;
    ASAsyncTransactionQueue &_queue;
  };
  
  struct Operation
  {
    dispatch_block_t _block;
    GroupImpl *_group;
    NSInteger _priority;
  };
    
  struct DispatchEntry // entry for each dispatch queue 每一个分发queue的入口
  {
    typedef std::list<Operation> OperationQueue;
    typedef std::list<OperationQueue::iterator> OperationIteratorList; // each item points to operation queue
    typedef std::map<NSInteger, OperationIteratorList> OperationPriorityMap; // sorted by priority

    OperationQueue _operationQueue;
    OperationPriorityMap _operationPriorityMap;
    int _threadCount;
      
    Operation popNextOperation(bool respectPriority);  // assumes locked mutex
    void pushOperation(Operation operation);           // assumes locked mutex
  };
  
  std::map<dispatch_queue_t, DispatchEntry> _entries;
  ASDN::Mutex _mutex;
};

ASAsyncTransactionQueue::Group* ASAsyncTransactionQueue::createGroup()
{
  Group *res = new GroupImpl(*this);
  return res;
}

void ASAsyncTransactionQueue::GroupImpl::release()
{
  ASDN::MutexLocker locker(_queue._mutex);
  
  if (_pendingOperations == 0)  {
    delete this;
  } else {
    _releaseCalled = true;
  }
}

ASAsyncTransactionQueue::Operation ASAsyncTransactionQueue::DispatchEntry::popNextOperation(bool respectPriority)
{
  NSCAssert(!_operationQueue.empty() && !_operationPriorityMap.empty(), @"No scheduled operations available");

  OperationQueue::iterator queueIterator;
  OperationPriorityMap::iterator mapIterator;
  
  if (respectPriority) {
    mapIterator = --_operationPriorityMap.end();  // highest priority "bucket" 高优先级的bucket
    queueIterator = *mapIterator->second.begin();
  } else {
    queueIterator = _operationQueue.begin();
    mapIterator = _operationPriorityMap.find(queueIterator->_priority);
  }
  
  // no matter what, first item in "bucket" must match item in queue
  // 无论是什么，第一个在bucket的东西必须匹配在queue里的东西
  NSCAssert(mapIterator->second.front() == queueIterator, @"Queue inconsistency");
  
  Operation res = *queueIterator;
  _operationQueue.erase(queueIterator);
  
  mapIterator->second.pop_front();
  if (mapIterator->second.empty()) {
    _operationPriorityMap.erase(mapIterator);
  }

  return res;
}

void ASAsyncTransactionQueue::DispatchEntry::pushOperation(ASAsyncTransactionQueue::Operation operation)
{
  _operationQueue.push_back(operation);

  OperationIteratorList &list = _operationPriorityMap[operation._priority];
  list.push_back(--_operationQueue.end());
}

void ASAsyncTransactionQueue::GroupImpl::schedule(NSInteger priority, dispatch_queue_t queue, dispatch_block_t block)
{
  ASAsyncTransactionQueue &q = _queue;
  ASDN::MutexLocker locker(q._mutex);
  
  DispatchEntry &entry = q._entries[queue];
  
  Operation operation;
  operation._block = block;
  operation._group = this;
  operation._priority = priority;
  entry.pushOperation(operation);
  
  ++_pendingOperations; // enter group
  
  NSUInteger maxThreads = [NSProcessInfo processInfo].activeProcessorCount * 2;

  // Bit questionable maybe - we can give main thread more CPU time during tracking;
  // 可能是bit的疑问 我们可以给主线程更多的cpu时间
  if ([[NSRunLoop mainRunLoop].currentMode isEqualToString:UITrackingRunLoopMode])
    --maxThreads;
  
  if (entry._threadCount < maxThreads) { // we need to spawn another thread 我们需要去分配更多的线程

    // first thread will take operations in queue order (regardless of priority), other threads will respect priority
    // 第一个线程将会按顺序选择操作（尽量有优先级），其他线程会按照优先级来
    bool respectPriority = entry._threadCount > 0;
    ++entry._threadCount;
    
    dispatch_async(queue, ^{
      ASDN::MutexLocker lock(q._mutex);
      
      // go until there are no more pending operations
      // 运行直到没有更多的相关操作
      while (!entry._operationQueue.empty()) {
        Operation operation = entry.popNextOperation(respectPriority);
        {
          ASDN::MutexUnlocker unlock(q._mutex);
          if (operation._block) {
            operation._block();
          }
          operation._group->leave();
          operation._block = nil; // the block must be freed while mutex is unlocked block必须在没有锁的时候释放
        }
      }
      --entry._threadCount;
      
      if (entry._threadCount == 0) {
        NSCAssert(entry._operationQueue.empty() || entry._operationPriorityMap.empty(), @"No working threads but operations are still scheduled"); // this shouldn't happen
        q._entries.erase(queue);
      }
    });
  }
}

void ASAsyncTransactionQueue::GroupImpl::notify(dispatch_queue_t queue, dispatch_block_t block)
{
  ASDN::MutexLocker locker(_queue._mutex);
  
  if (_pendingOperations == 0) {
    dispatch_async(queue, block);
  } else {
    GroupNotify notify;
    notify._block = block;
    notify._queue = queue;
    _notifyList.push_back(notify);
  }
}

void ASAsyncTransactionQueue::GroupImpl::enter()
{
  ASDN::MutexLocker locker(_queue._mutex);
  ++_pendingOperations;
}

void ASAsyncTransactionQueue::GroupImpl::leave()
{
  ASDN::MutexLocker locker(_queue._mutex);
  --_pendingOperations;
  
  if (_pendingOperations == 0) {
    std::list<GroupNotify> notifyList;
    _notifyList.swap(notifyList);
    
    for (GroupNotify & notify : notifyList) {
      dispatch_async(notify._queue, notify._block);
    }
    
    _condition.signal();
    
    // there was attempt to release the group before, but we still
    // had operations scheduled so now is good time
    // 试图去释放group之前，我们仍然需要按照计划操作，所以这个是个合适的时间
    if (_releaseCalled) {
      delete this;
    }
  }
}

void ASAsyncTransactionQueue::GroupImpl::wait()
{
  ASDN::MutexLocker locker(_queue._mutex);
  while (_pendingOperations > 0) {
    _condition.wait(_queue._mutex);
  }
}

ASAsyncTransactionQueue & ASAsyncTransactionQueue::instance()
{
  static ASAsyncTransactionQueue *instance = new ASAsyncTransactionQueue();
  return *instance;
}

@implementation _ASAsyncTransaction
{
  ASAsyncTransactionQueue::Group *_group;
  NSMutableArray *_operations;
}

#pragma mark -
#pragma mark Lifecycle

- (instancetype)initWithCallbackQueue:(dispatch_queue_t)callbackQueue
                      completionBlock:(void(^)(_ASAsyncTransaction *, BOOL))completionBlock
{
  if ((self = [self init])) {
    if (callbackQueue == NULL) {
      callbackQueue = dispatch_get_main_queue();
    }
    _callbackQueue = callbackQueue;
    _completionBlock = [completionBlock copy];

    __atomic_store_n(&_state, ASAsyncTransactionStateOpen, __ATOMIC_SEQ_CST);
  }
  return self;
}

- (void)dealloc
{
  // Uncommitted transactions break our guarantees about releasing completion blocks on callbackQueue.
  // 没有提交的业务停止必须保证在释放完成block在回调线程上
  ASDisplayNodeAssert(__atomic_load_n(&_state, __ATOMIC_SEQ_CST) != ASAsyncTransactionStateOpen, @"Uncommitted ASAsyncTransactions are not allowed");
  if (_group) {
    _group->release();
  }
}

#pragma mark -
#pragma mark Transaction Management

- (void)addAsyncOperationWithBlock:(asyncdisplaykit_async_transaction_async_operation_block_t)block
                             queue:(dispatch_queue_t)queue
                        completion:(asyncdisplaykit_async_transaction_operation_completion_block_t)completion
{
  [self addAsyncOperationWithBlock:block
                          priority:ASDefaultTransactionPriority
                             queue:queue
                        completion:completion];
}

- (void)addAsyncOperationWithBlock:(asyncdisplaykit_async_transaction_async_operation_block_t)block
                          priority:(NSInteger)priority
                             queue:(dispatch_queue_t)queue
                        completion:(asyncdisplaykit_async_transaction_operation_completion_block_t)completion
{
  ASDisplayNodeAssertMainThread();
  ASDisplayNodeAssert(__atomic_load_n(&_state, __ATOMIC_SEQ_CST) == ASAsyncTransactionStateOpen, @"You can only add operations to open transactions");

  [self _ensureTransactionData];

  ASDisplayNodeAsyncTransactionOperation *operation = [[ASDisplayNodeAsyncTransactionOperation alloc] initWithOperationCompletionBlock:completion];
  [_operations addObject:operation];
  _group->schedule(priority, queue, ^{
    @autoreleasepool {
      if (__atomic_load_n(&_state, __ATOMIC_SEQ_CST) != ASAsyncTransactionStateCanceled) {
        _group->enter();
        block(^(id<NSObject> value){
          operation.value = value;
          _group->leave();
        });
      }
    }
  });
}

- (void)addOperationWithBlock:(asyncdisplaykit_async_transaction_operation_block_t)block
                        queue:(dispatch_queue_t)queue
                   completion:(asyncdisplaykit_async_transaction_operation_completion_block_t)completion
{
    [self addOperationWithBlock:block
                       priority:ASDefaultTransactionPriority
                          queue:queue
                     completion:completion];
}

- (void)addOperationWithBlock:(asyncdisplaykit_async_transaction_operation_block_t)block
                     priority:(NSInteger)priority
                        queue:(dispatch_queue_t)queue
                   completion:(asyncdisplaykit_async_transaction_operation_completion_block_t)completion
{
  ASDisplayNodeAssertMainThread();
  ASDisplayNodeAssert(__atomic_load_n(&_state, __ATOMIC_SEQ_CST) == ASAsyncTransactionStateOpen, @"You can only add operations to open transactions");

  [self _ensureTransactionData];

  ASDisplayNodeAsyncTransactionOperation *operation = [[ASDisplayNodeAsyncTransactionOperation alloc] initWithOperationCompletionBlock:completion];
  [_operations addObject:operation];
  _group->schedule(priority, queue, ^{
    @autoreleasepool {
      if (__atomic_load_n(&_state, __ATOMIC_SEQ_CST) != ASAsyncTransactionStateCanceled) {
        operation.value = block();
      }
    }
  });
}

- (void)addCompletionBlock:(asyncdisplaykit_async_transaction_completion_block_t)completion
{
  __weak __typeof__(self) weakSelf = self;
  [self addOperationWithBlock:^(){return (id<NSObject>)nil;} queue:_callbackQueue completion:^(id<NSObject> value, BOOL canceled) {
    __typeof__(self) strongSelf = weakSelf;
    completion(strongSelf, canceled);
  }];
}

- (void)cancel
{
  ASDisplayNodeAssertMainThread();
  ASDisplayNodeAssert(__atomic_load_n(&_state, __ATOMIC_SEQ_CST) != ASAsyncTransactionStateOpen, @"You can only cancel a committed or already-canceled transaction");
  __atomic_store_n(&_state, ASAsyncTransactionStateCanceled, __ATOMIC_SEQ_CST);
}

- (void)commit
{
  ASDisplayNodeAssertMainThread();
  ASDisplayNodeAssert(__atomic_load_n(&_state, __ATOMIC_SEQ_CST) == ASAsyncTransactionStateOpen, @"You cannot double-commit a transaction");
  __atomic_store_n(&_state, ASAsyncTransactionStateCommitted, __ATOMIC_SEQ_CST);
  
  if ([_operations count] == 0) {
    // Fast path: if a transaction was opened, but no operations were added, execute completion block synchronously.
    // 第一步：如果一个业务已经开始，没有操作被添加，则同步执行完成block
    if (_completionBlock) {
      _completionBlock(self, NO);
    }
  } else {
    ASDisplayNodeAssert(_group != NULL, @"If there are operations, dispatch group should have been created");
    
    _group->notify(_callbackQueue, ^{
      // _callbackQueue is the main queue in current practice (also asserted in -waitUntilComplete).
      // This code should be reviewed before taking on significantly different use cases.
      // _callbackQueue是在当前实践中的主queue（也会在-waitUntilComplete中判断）
      // 这个代码应该在操作不同的用户操作的时候被调用
      ASDisplayNodeAssertMainThread();
      [self completeTransaction];
    });
  }
}

- (void)completeTransaction
{
  if (__atomic_load_n(&_state, __ATOMIC_SEQ_CST) != ASAsyncTransactionStateComplete) {
    BOOL isCanceled = (__atomic_load_n(&_state, __ATOMIC_SEQ_CST) == ASAsyncTransactionStateCanceled);
    for (ASDisplayNodeAsyncTransactionOperation *operation in _operations) {
      [operation callAndReleaseCompletionBlock:isCanceled];
    }
    
    // Always set _state to Complete, even if we were cancelled, to block any extraneous
    // calls to this method that may have been scheduled for the next runloop
    // (e.g. if we needed to force one in this runloop with -waitUntilComplete, but another was already scheduled)
    // 经常设置 _state到完成，尽量我们取消了，对阻止任何的无效消耗
    // 调用这个方法可以计划下一个runloop
    // （比如我们需要强制一个-waitUntilComplete在此次runloop循环，但另一个已经按照计划运行）
    __atomic_store_n(&_state, ASAsyncTransactionStateComplete, __ATOMIC_SEQ_CST);

    if (_completionBlock) {
      _completionBlock(self, isCanceled);
    }
  }
}

- (void)waitUntilComplete
{
  ASDisplayNodeAssertMainThread();
  if (__atomic_load_n(&_state, __ATOMIC_SEQ_CST) != ASAsyncTransactionStateComplete) {
    if (_group) {
      ASDisplayNodeAssertTrue(_callbackQueue == dispatch_get_main_queue());
      _group->wait();
      
      // At this point, the asynchronous operation may have completed, but the runloop
      // observer has not committed the batch of transactions we belong to.  It's important to
      // commit ourselves via the group to avoid double-committing the transaction.
      // This is only necessary when forcing display work to complete before allowing the runloop
      // to continue, e.g. in the implementation of -[ASDisplayNode recursivelyEnsureDisplay].
      // 在这个点上，异步操作可能已经完成，但runloop的观察者还没有提交属于此的系列的业务
      // 这很重要去提交我们自己的group去防止两次提交业务
      // 这个也是必要的当强制显示工作去完成在允许runloop去操作之前
      // 比如：在实现-[ASDisplayNode recursivelyEnsureDisplay]的时候
      if (__atomic_load_n(&_state, __ATOMIC_SEQ_CST) == ASAsyncTransactionStateOpen) {
        [_ASAsyncTransactionGroup commit];
        ASDisplayNodeAssert(__atomic_load_n(&_state, __ATOMIC_SEQ_CST) != ASAsyncTransactionStateOpen, @"Transaction should not be open after committing group");
      }
      // If we needed to commit the group above, -completeTransaction may have already been run.
      // It is designed to accommodate this by checking _state to ensure it is not complete.
      // 如果我们需要提交group之前，-completeTransaction也许已经跑过了
      // 如果这边设计成适应这个通过判断_state去确保没有完成
      [self completeTransaction];
    }
  }
}

#pragma mark -
#pragma mark Helper Methods

- (void)_ensureTransactionData
{
  // Lazily initialize _group and _operations to avoid overhead in the case where no operations are added to the transaction
  // 懒加载初始化 _group 和 _operations 去阻止特例开销当没有操作被添加到业务中
  if (_group == NULL) {
    _group = ASAsyncTransactionQueue::instance().createGroup();
  }
  if (_operations == nil) {
    _operations = [[NSMutableArray alloc] init];
  }
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"<_ASAsyncTransaction: %p - _state = %lu, _group = %p, _operations = %@>", self, (unsigned long)__atomic_load_n(&_state, __ATOMIC_SEQ_CST), _group, _operations];
}

@end
