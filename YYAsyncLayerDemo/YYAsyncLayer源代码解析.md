## 前言
本文CSDN地址：http://blog.csdn.net/game3108/article/details/53023941
本文的中文注释代码demo更新在我的[github](https://github.com/game3108/YYAsyncLayerDemo)上。

在研究iOS UI性能优化上，异步绘制一直是一个离不开的话题。最近在研究Facebook的开源框架AsyncDisplayKit的时候，找到了YYKit作者所实现的[YYAsyncLayer](https://github.com/ibireme/YYAsyncLayer)。从这个项目了解异步绘制的方法。


## 项目结构

YYAsyncLayer项目较为简单，一共就三个文件：

* YYSentinel：线程安全的计数器。
* YYTransaction：注册runloop调用。
* YYAsyncLayer：异步绘制的CALayer子类。

其中YYTransaction涉及了runloop的内容，具体runloop的了解，可以从作者的另一篇文章[深入理解RunLoop](http://blog.ibireme.com/2015/05/18/runloop/)了解。

以下将分别介绍下面3个文件。

## 源代码
### YYSentinel
YYSentinel使用原子性操作函数，进行计数。
```
/**
 线程安全的计数器
 */
@interface YYSentinel : NSObject
/**
 当前计数
 */
@property (readonly) int32_t value;
/**
 原子性增加值

 @return 新值
 */
- (int32_t)increase;

@end

#import <libkern/OSAtomic.h>
@implementation YYSentinel {
    int32_t _value;
}

- (int32_t)value {
    return _value;
}

- (int32_t)increase {
    //使用OSAtomic增加值
    return OSAtomicIncrement32(&_value);
}

@end
```
### YYTransaction
YYTransaction的逻辑也并不复杂：将target和相应selector存入一个set中（重写hash与isEqual用于set判断），并且在runloop中注册kCFRunLoopBeforeWaiting与kCFRunLoopExit事件，将优先级定义为0，即在Core Animation执行完毕后，执行相应的display方法，去模拟Core Animation的绘制机制，进行相应异步绘制的方法。
YYTransaction.h声明
```
@interface YYTransaction : NSObject

/**
 创建和返回一个transaction通过一个定义的target和selector

 @param target   执行target，target会在runloop结束前被retain
 @param selector target的selector

 @return 1个新的transaction，或者有错误时返回nil
 */
+ (YYTransaction *)transactionWithTarget:(id)target selector:(SEL)selector;

/**
 加入transaction到runloop
 */
- (void)commit;

@end
```
YYTransaction.m实现
```
@interface YYTransaction()
@property (nonatomic, strong) id target;
@property (nonatomic, assign) SEL selector;
@end

static NSMutableSet *transactionSet = nil;

//runloop循环的回调
static void YYRunLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
    if (transactionSet.count == 0) return;
    NSSet *currentSet = transactionSet;
//获取完上一次需要执行的方法后，将所有方法清空
    transactionSet = [NSMutableSet new];
    //遍历set。执行里面的selector
    [currentSet enumerateObjectsUsingBlock:^(YYTransaction *transaction, BOOL *stop) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [transaction.target performSelector:transaction.selector];
#pragma clang diagnostic pop
    }];
}

static void YYTransactionSetup() {
    static dispatch_once_t onceToken;
    //gcd只运行一次
    dispatch_once(&onceToken, ^{
        transactionSet = [NSMutableSet new];
        CFRunLoopRef runloop = CFRunLoopGetMain();
        CFRunLoopObserverRef observer;
        
        //注册runloop监听，在等待与退出前进行
        observer = CFRunLoopObserverCreate(CFAllocatorGetDefault(),
                                           kCFRunLoopBeforeWaiting | kCFRunLoopExit,
                                           true,      // repeat
                                           0xFFFFFF,  // after CATransaction(2000000)
                                           YYRunLoopObserverCallBack, NULL);
        //将监听加在所有mode上
        CFRunLoopAddObserver(runloop, observer, kCFRunLoopCommonModes);
        CFRelease(observer);
    });
}


@implementation YYTransaction


+ (YYTransaction *)transactionWithTarget:(id)target selector:(SEL)selector{
    if (!target || !selector) return nil;
    YYTransaction *t = [YYTransaction new];
    t.target = target;
    t.selector = selector;
    return t;
}

- (void)commit {
    if (!_target || !_selector) return;
    //初始化runloop监听
    YYTransactionSetup();
    //添加行为到set中
    [transactionSet addObject:self];
}

//hash值返回
- (NSUInteger)hash {
    long v1 = (long)((void *)_selector);
    long v2 = (long)_target;
    return v1 ^ v2;
}
//isEqual返回
- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isMemberOfClass:self.class]) return NO;
    YYTransaction *other = object;
    return other.selector == _selector && other.target == _target;
}

@end
```
###YYAsyncLayer
YYAsyncLayer为了异步绘制而继承CALayer的子类。通过使用Core Graphic相关方法，在子线程中绘制内容Context，绘制完成后，回到主线程对layer.contents进行直接显示。控制了渲染线程的数量以及通过原子计数YYSentinel控制了取消异步渲染的内容。通过delegate回调，可以使得不同的delegate对象在block中绘制需要的内容。
YYAsyncLayer.h声明
```
/**
 YYAsyncLayer是异步渲染的CALayer子类
 */
@interface YYAsyncLayer : CALayer
//是否异步渲染
@property BOOL displaysAsynchronously;
@end

/**
 YYAsyncLayer's的delegate协议，一般是uiview。必须实现这个方法
 */
@protocol YYAsyncLayerDelegate <NSObject>
@required
//当layer的contents需要更新的时候，返回一个新的展示任务
- (YYAsyncLayerDisplayTask *)newAsyncDisplayTask;
@end

/**
 YYAsyncLayer在后台渲染contents的显示任务类
 */
@interface YYAsyncLayerDisplayTask : NSObject

/**
 这个block会在异步渲染开始的前调用，只在主线程调用。
 */
@property (nullable, nonatomic, copy) void (^willDisplay)(CALayer *layer);

/**
 这个block会调用去显示layer的内容
 */
@property (nullable, nonatomic, copy) void (^display)(CGContextRef context, CGSize size, BOOL(^isCancelled)(void));

/**
 这个block会在异步渲染结束后调用，只在主线程调用。
 */
@property (nullable, nonatomic, copy) void (^didDisplay)(CALayer *layer, BOOL finished);

@end
```
YYAsyncLayer.m实现
```
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

```

## 用法
这里举作者在github里写的简单例子：
在设置内容与``layoutSubviews``内添加YYTransaction，并且实现了``- (YYAsyncLayerDisplayTask *)newAsyncDisplayTask``方法去实现相应的三个block，这样，一个异步绘制的YYLabel就完成了。

```
@interface YYLabel : UIView
@property NSString *text;
@property UIFont *font;
@end

@implementation YYLabel

- (void)setText:(NSString *)text {
    _text = text.copy;
    [[YYTransaction transactionWithTarget:self selector:@selector(contentsNeedUpdated)] commit];
}

- (void)setFont:(UIFont *)font {
    _font = font;
    [[YYTransaction transactionWithTarget:self selector:@selector(contentsNeedUpdated)] commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [[YYTransaction transactionWithTarget:self selector:@selector(contentsNeedUpdated)] commit];
}

- (void)contentsNeedUpdated {
    // do update
    [self.layer setNeedsDisplay];
}

#pragma mark - YYAsyncLayer

+ (Class)layerClass {
    return YYAsyncLayer.class;
}

- (YYAsyncLayerDisplayTask *)newAsyncDisplayTask {

    // capture current state to display task
    NSString *text = _text;
    UIFont *font = _font;

    YYAsyncLayerDisplayTask *task = [YYAsyncLayerDisplayTask new];
    task.willDisplay = ^(CALayer *layer) {
        //...
    };

    task.display = ^(CGContextRef context, CGSize size, BOOL(^isCancelled)(void)) {
        if (isCancelled()) return;
        NSArray *lines = CreateCTLines(text, font, size.width);
        if (isCancelled()) return;

        for (int i = 0; i < lines.count; i++) {
            CTLineRef line = line[i];
            CGContextSetTextPosition(context, 0, i * font.pointSize * 1.5);
            CTLineDraw(line, context);
            if (isCancelled()) return;
        }
    };

    task.didDisplay = ^(CALayer *layer, BOOL finished) {
        if (finished) {
            // finished
        } else {
            // cancelled
        }
    };

    return task;
}
@end
```

## 总结
YYAsyncLayer内使用YYTransaction在 RunLoop 中注册了一个 Observer，监视的事件和 Core Animation 一样，但优先级比 CA 要低。当 RunLoop 进入休眠前、CA 处理完事件后，YYTransaction 就会执行该 loop 内提交的所有任务。
在YYAsyncLayer中，通过重写CALayer显示display方法，向delegate请求一个异步绘制的任务，并且在子线程中绘制Core Graphic对象，最后再回到主线程中设置layer.contents内容。

附上作者的部分解读：
>YYAsyncLayer 是 CALayer 的子类，当它需要显示内容（比如调用了 [layer setNeedDisplay]）时，它会向 delegate，也就是 UIView 请求一个异步绘制的任务。在异步绘制时，Layer 会传递一个 BOOL(^isCancelled)() 这样的 block，绘制代码可以随时调用该 block 判断绘制任务是否已经被取消。

## 参考资料
1.[iOS 保持界面流畅的技巧](http://blog.ibireme.com/2015/11/12/smooth_user_interfaces_for_ios/)
2.[深入理解RunLoop](http://blog.ibireme.com/2015/05/18/runloop/)
