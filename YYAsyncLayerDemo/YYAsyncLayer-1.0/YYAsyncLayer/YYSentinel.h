//
//  YYSentinel.h
//  YYKit <https://github.com/ibireme/YYKit>
//
//  Created by ibireme on 15/4/13.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 YYSentinel is a thread safe incrementing counter. 
 It may be used in some multi-threaded situation.
 */

/**
 线程安全的计数器
 */
@interface YYSentinel : NSObject

/// Returns the current value of the counter.

/**
 当前计数
 */
@property (readonly) int32_t value;

/// Increase the value atomically.
/// @return The new value.

/**
 原子性增加值

 @return 新值
 */
- (int32_t)increase;

@end

NS_ASSUME_NONNULL_END
