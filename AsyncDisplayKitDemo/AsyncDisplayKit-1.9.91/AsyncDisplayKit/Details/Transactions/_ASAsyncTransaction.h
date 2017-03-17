//
//  _ASAsyncTransaction.h
//  AsyncDisplayKit
//
//  Copyright (c) 2014-present, Facebook, Inc.  All rights reserved.
//  This source code is licensed under the BSD-style license found in the
//  LICENSE file in the root directory of this source tree. An additional grant
//  of patent rights can be found in the PATENTS file in the same directory.
//

#import <Foundation/Foundation.h>


@class _ASAsyncTransaction;

typedef void(^asyncdisplaykit_async_transaction_completion_block_t)(_ASAsyncTransaction *completedTransaction, BOOL canceled);
typedef id<NSObject>(^asyncdisplaykit_async_transaction_operation_block_t)(void);
typedef void(^asyncdisplaykit_async_transaction_operation_completion_block_t)(id<NSObject> value, BOOL canceled);
typedef void(^asyncdisplaykit_async_transaction_complete_async_operation_block_t)(id<NSObject> value);
typedef void(^asyncdisplaykit_async_transaction_async_operation_block_t)(asyncdisplaykit_async_transaction_complete_async_operation_block_t completeOperationBlock);

/**
 State is initially ASAsyncTransactionStateOpen.
 Every transaction MUST be committed. It is an error to fail to commit a transaction.
 A committed transaction MAY be canceled. You cannot cancel an open (uncommitted) transaction.
 */

/**
 每一个业务必须要提交。不提交就是错误。
 一个已经提交的业务可能被取消，你不可能取消一个ASAsyncTransactionStateOpen的业务
 */
typedef NS_ENUM(NSUInteger, ASAsyncTransactionState) {
  ASAsyncTransactionStateOpen = 0,
  ASAsyncTransactionStateCommitted,
  ASAsyncTransactionStateCanceled,
  ASAsyncTransactionStateComplete
};

extern NSInteger const ASDefaultTransactionPriority;

/**
 @summary ASAsyncTransaction provides lightweight transaction semantics for asynchronous operations.

 @desc ASAsyncTransaction provides the following properties:

 - Transactions group an arbitrary number of operations, each consisting of an execution block and a completion block.
 - The execution block returns a single object that will be passed to the completion block.
 - Execution blocks added to a transaction will run in parallel on the global background dispatch queues;
   the completion blocks are dispatched to the callback queue.
 - Every operation completion block is guaranteed to execute, regardless of cancelation.
   However, execution blocks may be skipped if the transaction is canceled.
 - Operation completion blocks are always executed in the order they were added to the transaction, assuming the
   callback queue is serial of course.
 */

/**ASAsyncTransaction提供轻量的异步操作的业务
 
 ASAsyncTransaction提供以下特性
 
 业务组提供任意数量的操作，每一个包含一个执行的block和完成的block
 执行block返回单个可以传给完成block的对象
 执行block添加到业务将会在一个全局的线程里并行
 完成block将会在毁掉的线程里调用
 每一个操作完成block确定会被执行，除非被取消了
 然而，执行block在业务被取消的时候会被跳过
 操作完成block经常按顺序被加入到业务中，确保回调线程是一系列的操作
 -
 */
@interface _ASAsyncTransaction : NSObject

/**
 @summary Initialize a transaction that can start collecting async operations.

 @see initWithCallbackQueue:commitBlock:completionBlock:executeConcurrently:
 @param callbackQueue The dispatch queue that the completion blocks will be called on.
 @param completionBlock A block that is called when the transaction is completed. May be NULL.
 */

/**
 @summary 初始化一个业务可以开始异步操作

 @param callbackQueue 完成block将会执行的回调线程
 @param completionBlock 当业务完成后会被执行的block，可能是空
 */
- (instancetype)initWithCallbackQueue:(dispatch_queue_t)callbackQueue
                      completionBlock:(asyncdisplaykit_async_transaction_completion_block_t)completionBlock;

/**
 @summary Block the main thread until the transaction is complete, including callbacks.
 
 @desc This must be called on the main thread.
 */

/**
 @summary 阻塞主线程直到业务执行完毕，包括回调
 
 @desc 这个只能在主线程被调用
 */
- (void)waitUntilComplete;

/**
 The dispatch queue that the completion blocks will be called on.
 */

/**
 完成block会被调用的线程queue
 */
@property (nonatomic, readonly, retain) dispatch_queue_t callbackQueue;

/**
 A block that is called when the transaction is completed.
 */


/**
 业务完成的调用block
 */
@property (nonatomic, readonly, copy) asyncdisplaykit_async_transaction_completion_block_t completionBlock;

/**
 The state of the transaction.
 @see ASAsyncTransactionState
 */

/**
 业务的状态
 @see ASAsyncTransactionState
 */
@property (nonatomic, readonly, assign) ASAsyncTransactionState state;

/**
 @summary Adds a synchronous operation to the transaction.  The execution block will be executed immediately.

 @desc The block will be executed on the specified queue and is expected to complete synchronously.  The async
 transaction will wait for all operations to execute on their appropriate queues, so the blocks may still be executing
 async if they are running on a concurrent queue, even though the work for this block is synchronous.

 @param block The execution block that will be executed on a background queue.  This is where the expensive work goes.
 @param queue The dispatch queue on which to execute the block.
 @param completion The completion block that will be executed with the output of the execution block when all of the
 operations in the transaction are completed. Executed and released on callbackQueue.
 */

/**
 @summary 添加一个同步操作到业务。执行block将会直接执行
 
 @desc block将会在特定的线程执行并且同步的完成。异步业务将会等到所有操作执行它们在它们合适的线程，因此blocks仍然会异步执行，
 如果它们在并发线程执行，尽管block的操作是同步的
 
 @param block 执行block将会在后台线程执行。这个最昂贵的工作的地方。
 @param queue 执行block的queue
 @param completion 完成block，将会执行在输出的执行block当所有操作在业务中已经完成。执行和释放在回调queue上
 */
- (void)addOperationWithBlock:(asyncdisplaykit_async_transaction_operation_block_t)block
                        queue:(dispatch_queue_t)queue
                   completion:(asyncdisplaykit_async_transaction_operation_completion_block_t)completion;

/**
 @summary Adds a synchronous operation to the transaction.  The execution block will be executed immediately.
 
 @desc The block will be executed on the specified queue and is expected to complete synchronously.  The async
 transaction will wait for all operations to execute on their appropriate queues, so the blocks may still be executing
 async if they are running on a concurrent queue, even though the work for this block is synchronous.
 
 @param block The execution block that will be executed on a background queue.  This is where the expensive work goes.
 @param priority Execution priority; Tasks with higher priority will be executed sooner
 @param queue The dispatch queue on which to execute the block.
 @param completion The completion block that will be executed with the output of the execution block when all of the
 operations in the transaction are completed. Executed and released on callbackQueue.
 */


/**
 @summary 添加一个同步操作到业务。执行block将会直接执行
 
 @desc block将会在特定的线程执行并且同步的完成。block将会被一个能够执行一次的完成block提交。这个很有用对网络下载和其他操作有异步api

 @param block 执行block将会在后台线程执行。这个最昂贵的工作的地方。
 @param priority 执行优先级。高优先级的任务会先执行
 @param queue 执行block的queue
 @param completion 完成block，将会执行在输出的执行block当所有操作在业务中已经完成。执行和释放在回调queue上
 */
- (void)addOperationWithBlock:(asyncdisplaykit_async_transaction_operation_block_t)block
                     priority:(NSInteger)priority
                        queue:(dispatch_queue_t)queue
                   completion:(asyncdisplaykit_async_transaction_operation_completion_block_t)completion;


/**
 @summary Adds an async operation to the transaction.  The execution block will be executed immediately.

 @desc The block will be executed on the specified queue and is expected to complete asynchronously.  The block will be
 supplied with a completion block that can be executed once its async operation is completed.  This is useful for
 network downloads and other operations that have an async API.

 WARNING: Consumers MUST call the completeOperationBlock passed into the work block, or objects will be leaked!

 @param block The execution block that will be executed on a background queue.  This is where the expensive work goes.
 @param queue The dispatch queue on which to execute the block.
 @param completion The completion block that will be executed with the output of the execution block when all of the
 operations in the transaction are completed. Executed and released on callbackQueue.
 */


/**
 @summary 添加一个异步操作到业务。执行block将会直接执行
 
 @desc block将会在特定的线程执行并且同步的完成。block将会被一个能够执行一次的完成block提交。这个很有用对网络下载和其他操作有异步api

 @param block 执行block将会在后台线程执行。这个最昂贵的工作的地方。
 @param queue 执行block的queue
 @param completion 完成block，将会执行在输出的执行block当所有操作在业务中已经完成。执行和释放在回调queue上
 */
- (void)addAsyncOperationWithBlock:(asyncdisplaykit_async_transaction_async_operation_block_t)block
                             queue:(dispatch_queue_t)queue
                        completion:(asyncdisplaykit_async_transaction_operation_completion_block_t)completion;

/**
 @summary Adds an async operation to the transaction.  The execution block will be executed immediately.
 
 @desc The block will be executed on the specified queue and is expected to complete asynchronously.  The block will be
 supplied with a completion block that can be executed once its async operation is completed.  This is useful for
 network downloads and other operations that have an async API.
 
 WARNING: Consumers MUST call the completeOperationBlock passed into the work block, or objects will be leaked!
 
 @param block The execution block that will be executed on a background queue.  This is where the expensive work goes.
 @param priority Execution priority; Tasks with higher priority will be executed sooner
 @param queue The dispatch queue on which to execute the block.
 @param completion The completion block that will be executed with the output of the execution block when all of the
 operations in the transaction are completed. Executed and released on callbackQueue.
 */
/**
 @summary 添加一个异步操作到业务。执行block将会直接执行
 
 @desc block将会在特定的线程执行并且同步的完成。block将会被一个能够执行一次的完成block提交。这个很有用对网络下载和其他操作有异步api
 
 @param block 执行block将会在后台线程执行。这个最昂贵的工作的地方。
 @param priority 执行优先级。高优先级的任务会先执行
 @param queue 执行block的queue
 @param completion 完成block，将会执行在输出的执行block当所有操作在业务中已经完成。执行和释放在回调queue上
 */
- (void)addAsyncOperationWithBlock:(asyncdisplaykit_async_transaction_async_operation_block_t)block
                          priority:(NSInteger)priority
                             queue:(dispatch_queue_t)queue
                        completion:(asyncdisplaykit_async_transaction_operation_completion_block_t)completion;



/**
 @summary Adds a block to run on the completion of the async transaction.

 @param completion The completion block that will be executed with the output of the execution block when all of the
 operations in the transaction are completed. Executed and released on callbackQueue.
 */

/**
 @summary 添加一个block到完成的异步业务

 @param completion 完成block，将会执行在输出的执行block当所有操作在业务中已经完成。执行和释放在回调queue上
 */
- (void)addCompletionBlock:(asyncdisplaykit_async_transaction_completion_block_t)completion;

/**
 @summary Cancels all operations in the transaction.

 @desc You can only cancel a committed transaction.

 All completion blocks are always called, regardless of cancelation. Execution blocks may be skipped if canceled.
 */

/**
 @summmary 取消所有操作在业务里
 
 @desc 你只能一个已经提交的业务
 
 所有完成的block都已经被调用了，尽管取消了。执行block会在取消的时候跳过
 */
- (void)cancel;

/**
 @summary Marks the end of adding operations to the transaction.

 @desc You MUST commit every transaction you create. It is an error to create a transaction that is never committed.

 When all of the operations that have been added have completed the transaction will execute their completion
 blocks.

 If no operations were added to this transaction, invoking commit will execute the transaction's completion block synchronously.
 */

/**
 @summary 标注添加操作到业务的终止
 
 @desc 你必须提交每一个你创建的业务。如果创建了业务没有被提交过就是错误
 
 当所有的操作已经完成了业务将会执行完成block
 
 如果没有操作添加到这个业务中，调用将会同步的执行业务的完成block
 */
- (void)commit;

@end
