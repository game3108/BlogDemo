## 前言
本文的中文注释代码demo更新在我的[github](https://github.com/game3108/BlogDemo/tree/master/YYModelDemo)上。

对于Model对象转换框架，之前有过[JSONModel源代码解析](http://www.jianshu.com/p/64ce3927eb62)。而这次来分析的框架，则是性能更佳优秀的[YYModel](https://github.com/ibireme/YYModel)。
YYModel有比大多数同类框架，有着很好的性能优势（下图为作者在github的贴图）。
![性能对比](http://upload-images.jianshu.io/upload_images/1829891-6ee8698b642c99b9.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

**在看源代码的过程中，也发现了一些不错的YYModel源代码的分析。本文主要结合一些其中的分析，加上个人的见解，写在这里，算是个人学习和记录。本文预计会分成3篇来完成，**

## YYModel使用
YYModel的使用相对于JSOMModel更佳简单，不需要类去继承JSONModel：
对Manually的方式，和JSONModel的解析方法，在文章[JSONModel源代码解析](http://www.jianshu.com/p/64ce3927eb62)中已经有过，这边只介绍YYModel的方式：

如果有这样一组json数据：
```
{
"number":"13612345678", 
"name":"Germany",
 "age": 49
}
```
那我们会去建立相应的Object对象
```
@interface TestObject : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *number;
@property (nonatomic, assign) NSInteger age;
@end
```
调用
```
// 从 JSON 转为 Model:
TestObject *testObject = [TestObject yy_modelWithJSON:json];

//从 Model 转为 JSON:
NSDictionary *json = [testObject yy_modelToJSONObject];
```
就可以进行类型的转化。

**显然，相较于JSONModel每个model类都必须继承于JSONModel类的作法，YYModel更佳方便和快捷**

## 整体结构
YYModel本身的目录结构十分精简：
![YYModel目录](http://upload-images.jianshu.io/upload_images/1829891-6bec1ddc5f880c8f.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

**包括：**
* **文件YYModel.h:**导入YYModel头文件
* **文件NSObject+YYModel:**YYModel主体Extension
* **文件YYClassInfo:**Class解析类

**代码结构引用[YYModel 源码历险记<一> 代码结构](http://www.jianshu.com/users/aa41dad549af/latest_articles)的一张图：**

![Paste_Image.png](http://upload-images.jianshu.io/upload_images/1829891-b70669bd99f1b149.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

**文件YYClassInfo中包含：**
* ``@interface YYClassIvarInfo : NSObject``:对Class的Ivar进行解析与构造
* ``@interface YYClassMethodInfo : NSObject``:对Class的Method进行解析与构造
* ``@interface YYClassPropertyInfo : NSObject``:对Class的Property进行解析与构造
* ``@interface YYClassInfo : NSObject``:通过以上三种解析，对Class进行解析与构造

**文件NSObject+YYModel中包含：**
* ``@interface _YYModelPropertyMeta : NSObject``：对Model的property进行解析与构造(.m中的private类)
* ``@interface _YYModelMeta : NSObject``：对Model进行解析与构造(.m中的private类)
* ``@interface NSObject (YYModel)``：NSObject的YYModel Extension
* ``@interface NSArray (YYModel)``：NSArray的YYModel Extension
* ``@interface NSDictionary (YYModel)``：NSDictionary的YYModel Extension
* ``@protocol YYModel <NSObject>``:接口YYModel

**此次分析，将会先看一下``yy_modelWithJSON``方法的调用，讲一下大体代码思路，然后就分别分析YYModel.h，YYClassInfo，NSObject+YYModel源代码，相当于从下而上进行分析。**

## 大体思路
```
//先转化json对象到dictionary，再调用yy_modelWithDictionary
+ (instancetype)yy_modelWithJSON:(id)json {
    NSDictionary *dic = [self _yy_dictionaryWithJSON:json];
    return [self yy_modelWithDictionary:dic];
}
```
其中``_yy_dictionaryWithJSON``就是将id的json对象转成dictionary
```
//解析model属性并附值
+ (instancetype)yy_modelWithDictionary:(NSDictionary *)dictionary {
    if (!dictionary || dictionary == (id)kCFNull) return nil;
    if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
    
    Class cls = [self class];
    //解析class得到modelmeta对象
    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:cls];
    //本地class类型映射
    if (modelMeta->_hasCustomClassFromDictionary) {
        cls = [cls modelCustomClassForDictionary:dictionary] ?: cls;
    }
    
    NSObject *one = [cls new];
    //附值函数
    if ([one yy_modelSetWithDictionary:dictionary]) return one;
    return nil;
}
```

**大致的思路就是先通过``_yy_dictionaryWithJSON``将json对象转成dictionary，然后调用``yy_modelWithDictionary``，解析获得解析出来的_YYModelMeta对象（有缓存），判断是否有本地的class类型映射，最后再通过``yy_modelSetWithDictionary``进行附值，返回model对象。**


## YYModel.h
YYModel.h本身只是个倒入项目的头文件，代码如下：
```
#import <Foundation/Foundation.h>

#if __has_include(<YYModel/YYModel.h>)
FOUNDATION_EXPORT double YYModelVersionNumber;
FOUNDATION_EXPORT const unsigned char YYModelVersionString[];
#import <YYModel/NSObject+YYModel.h>
#import <YYModel/YYClassInfo.h>
#else
#import "NSObject+YYModel.h"
#import "YYClassInfo.h"
#endif
```
头文件并不难理解，先试判断是否包含``__has_include``，然后再引入正确的文件。
在[YYModel 源码解读（一）之YYModel.h](http://www.cnblogs.com/machao/p/5514921.html)中有引入引号与左右括号有一段拓展，这边也记录一下：

 \#include / #import 语句有两种方式包含头文件，分别是使用双引号" "与左右尖括号< >。其区别是（对于不是使用完全文件路径名的）头文件的搜索顺序不同

使用双引号" "的头文件的搜索顺序：
* 包含该#include语句的源文件所在目录；
* 包含该#include语句的源文件的已经打开的头文件的逆序；
* 编译选项-I所指定的目录
* 环境变量include所定义的目录

使用左右尖括号< >的头文件的搜索顺序：
* 编译选项-I所指定的目录
* 环境变量include所定义的目录

## 小结
本文主要大体介绍了一下YYModel的整体结构，代码调用思路以及头文件YYModel.h代码。针对核心的NSObject+YYModel与YYClassInfo会分篇完成。

## 参考资料
[本文csdn地址](http://blog.csdn.net/game3108/article/details/52388089)
1.[iOS JSON 模型转换库评测](http://blog.ibireme.com/2015/10/23/ios_model_framework_benchmark/)
2.[郑钦洪_：YYModel 源码历险记](http://www.jianshu.com/p/9d9119d3d1e3)
3.[YYModel 源码解读](http://www.cnblogs.com/machao/p/5514921.html)
