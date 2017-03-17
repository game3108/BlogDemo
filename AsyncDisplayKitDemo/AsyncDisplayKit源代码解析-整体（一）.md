##前言
本文csdn地址：http://blog.csdn.net/game3108/article/details/54316576

本文的中文注释代码demo更新在我的[github](https://github.com/game3108/AsyncDisplayKitDemo)上。

![](http://upload-images.jianshu.io/upload_images/1829891-a548fcbe964fe7b2.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

[AsyncDisplayKit](https://github.com/facebook/AsyncDisplayKit) 是 Facebook 开源的一个用于保持 iOS 界面流畅的框架。主要作者是 Scott Goodson([github](https://github.com/appleguy))。
本文主要是从理论和源代码角度分析一下整个ASDK库，其中参考了很多参考资料中的内容，加以整理和复习。

##发展历史
>AsyncDisplayKit(ASDK)是2012年由Facebook开始着手开发，并于2014年出品的高性能显示类库，主要作者是Scott Goodson。Scott曾经参与了多个iOS版本系统的开发，包括UIKit以及一些系统原生app，后来加入Facebook并参与了ASDK的开发并应用到Paper，因此该库有机会从相对底层的角度来进行一系列的优化。

想要了解 ASDK 的原理和细节，最好从下面几个视频开始：
* 2014.10.15 [NSLondon - Scott Goodson - Behind AsyncDisplayKit](https://www.youtube.com/watch?v=-IPMNWqA638)
* 2015.03.02 [MCE 2015 - Scott Goodson - Effortless Responsiveness with AsyncDisplayKit](https://www.youtube.com/watch?v=ZPL4Nse76oY)
* 2015.10.25 [AsyncDisplayKit 2.0: Intelligent User Interfaces - NSSpain 2015](https://www.youtube.com/watch?v=RY_X7l1g79Q)

##解决的问题
很多时候用户在操作app的时候，会感觉到不适那么流畅，有所卡顿。
ASDK主要就是解决的问题就是操作页面过程中的保持帧率在60fps（理想状态下）的问题。

造成卡顿的原因有很多，总结一句话基本上就是：
**CPU或GPU消耗过大，导致在一次同步信号之间没有准备完成，没有内容提交，导致掉帧的问题。**

具体的原理，在[提升 iOS 界面的渲染性能](https://zhuanlan.zhihu.com/p/22255533?refer=iOS-Source-Code)文章中介绍的十分详细了，这里也不多阐述了。

##优化原理
从ASDK的视频与tutorial上，可以整理出三个ASDK主要优化的方面：
1. **布局**：
iOS自带的Autolayout在布局性能上存在瓶颈，并且只能在主线程进行计算。（参考[Auto Layout Performance on iOS](http://floriankugler.com/2013/04/22/auto-layout-performance-on-ios/)）因此ASDK弃用了Autolayout，自己参考自家的[ComponentKit](https://github.com/facebook/componentkit)设计了一套布局方式。
2. **渲染**
对于大量文本，图片等的渲染，UIKit组件只能在主线程并且可能会造成GPU绘制的资源紧张。ASDK使用了一些方法，比如图层的预混合等，并且异步的在后台绘制图层，不阻塞主线程的运行。
3. **系统对象创建于销毁**
UIKit组件封装了CALayer图层的对象，在创建、调整、销毁的时候，都会在主线程消耗资源。ASDK自己设计了一套Node机制，也能够调用。

**实际上，从上面的一些解释也可以看出，ASDK最大的特点就是"异步"。
将消耗时间的渲染、图片解码、布局以及其它 UI 操作等等全部移出主线程，这样主线程就可以对用户的操作及时做出反应，来达到流畅运行的目的。
**

##ASDisplayNode的整体设计
>AsyncDisplayKit’s basic unit is the node. ASDisplayNode is an abstraction over UIView, which in turn is an abstraction over CALayer. Unlike views, which can only be used on the main thread, nodes are thread-safe: you can instantiate and configure entire hierarchies of them in parallel on background threads.

**这段是ASDK官网上的原话。可以看出ASDK的核心就是ASDisplayNode。在介绍ASDisplayNode前，需要介绍一下目前UIView于CALayer的关系。**

####**UIView与CALayer的关系：**
UIView持有CALayer，显示依靠CALayer。
CALayer的delegate是UIView，可以回调通知UIView的变化。
UIView 和 CALayer 都不是线程安全的，并且只能在主线程创建、访问和销毁。
![UIKit](http://upload-images.jianshu.io/upload_images/1829891-95216433f17f5663.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

####**ASDisplayNode**
ASNode(ASDisplayNode以下同)仿照这样的关系，通过view去持有UIView，并且让UIView通过.node回调自己。在ASNode中封装了常见的视图属性，让开发者直接去调用ASNode进行开发。
![ASNode](http://upload-images.jianshu.io/upload_images/1829891-2856dad933bdbb07.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

并且ASNode可以设置layer backed属性，就是不需要响应触摸事件。这时候ASNode将直接操作CALayer进行显示，更加优化了性能。
![Paste_Image.png](http://upload-images.jianshu.io/upload_images/1829891-48ea650c31bffafd.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

ASNode本身是线程安全的，所以它允许在后台线程进行创建和修改。

这里借用一下[提升 iOS 界面的渲染性能](https://zhuanlan.zhihu.com/p/22255533?refer=iOS-Source-Code)中的一段话：
>Node 刚创建时，并不会在内部新建 UIView 和 CALayer，直到第一次在主线程访问 view 或 layer 属性时，它才会在内部生成对应的对象。当它的属性（比如frame/transform）改变后，它并不会立刻同步到其持有的 view 或 layer 去，而是把被改变的属性保存到内部的一个中间变量，稍后在需要时，再通过某个机制一次性设置到内部的 view 或 layer。

ASDK整体提供了十分多的Node组件，比如Button,Cell等等，利用这些组件，开发者可以绕过UIKit进行开发。这里贴一张官网上的层级图
![node层级](http://upload-images.jianshu.io/upload_images/1829891-0af8aaec7339657f.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

####渲染过程
ASDisplayNode的渲染过程主要有以下几步：

1. 初始化ASDisplayNode对应的 UIView 或者 CALayer
2. 在当前视图进入视图层级时执行 setNeedsDisplay；
3. display 方法执行时，向后台线程派发绘制事务；
4. 在Runloop中注册observer，在每个 RunLoop 结束时回调。

这边的细化会在之后介绍源代码的时候介绍。

##其他内容

ASDK还包含以下内容：

* ASLayout的布局功能
* ASAsyncTransaction的异步绘制控制
* ASViewController结点容器
* ASTableView/ASCollectionView以及对应的控制器ASRangeController／ASDataController

##总结
本文大体上介绍了一下AsyncDisplayKit的整体流程和优化方法，之后的几章将从源代码角度去分析ASDK的渲染过程。

##参考资料
1.[AsyncDisplayKit源码分析](http://awhisper.github.io/2016/05/06/AsyncDisplayKit%E6%BA%90%E7%A0%81%E5%88%86%E6%9E%90/)
2.[AsyncDisplayKit介绍](https://medium.com/@jasonyuh/asyncdisplaykit%E4%BB%8B%E7%BB%8D-%E4%B8%80-6b871d29e005#.ka94bjlbh)
3.[提升 iOS 界面的渲染性能](https://zhuanlan.zhihu.com/p/22255533?refer=iOS-Source-Code)
4.[iOS 保持界面流畅的技巧](http://blog.ibireme.com/2015/11/12/smooth_user_interfaces_for_ios/)
5.[AsyncDisplayKit Getting Started](http://asyncdisplaykit.org/guide/)
6.[AsyncDisplayKit Tutorial: Node Hierarchies](http://www.raywenderlich.com/107310/asyncdisplaykit-tutorial-node-hierarchies)
