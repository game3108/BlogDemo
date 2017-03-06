##前言
本文的中文注释代码demo更新在我的[github](https://github.com/game3108/BlogDemo/tree/master/YYModelDemo)上。

 上篇 [YYModel源代码分析（一）整体介绍
](http://www.jianshu.com/p/5428552be6ce) 主要写了YYModel的整体结构，代码调用思路以及头文件YYModel.h代码。本篇会主要集中在YYClassInfo文件上。文章内容会包含一些与JSONModel的比较，想了解JSONModel，可以参考[JSONModel源代码解析](http://www.jianshu.com/p/64ce3927eb62)。

##主体分层
YYClassInfo主要分为以下几部分：

* ``typedef NS_OPTIONS(NSUInteger, YYEncodingType)``与``YYEncodingType YYEncodingGetType(const char *typeEncoding);``方法
* ``@interface YYClassIvarInfo : NSObject``
* ``@interface YYClassMethodInfo : NSObject``
* ``@interface YYClassPropertyInfo : NSObject``
* ``@interface YYClassInfo : NSObject``

以下将分别分析每一部分的源代码。

##YYClassInfo源代码

### (1).typedef NS_OPTIONS(NSUInteger, YYEncodingType)与YYEncodingType YYEncodingGetType(const char *typeEncoding)方法
####相关知识

在这边，对于YYEncodingType的了解，需要知道一个很重要的概念：

[Type Encodings](https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html)
> To assist the runtime system, the compiler encodes the return and argument types for each method in a character string and associates the string with the method selector. The coding scheme it uses is also useful in other contexts and so is made publicly available with the@encode()
 compiler directive. When given a type specification, @encode()
 returns a string encoding that type. The type can be a basic type such as an int
, a pointer, a tagged structure or union, or a class name—any type, in fact, that can be used as an argument to the Csizeof()
 operator.


看过我JSONModel解析的人，应该比较了解这一块，property attribute的解析就是通过type encode解析出来的string进行的解析。

**但在这里的type encoding相对于JSONModel中的使用，会更general一些:**
* **JSONModel是只针对于Class的property变量，所以在解析的时候，将Ivar默认包含在property中，通过property的property attribute一并解析出来。**
* **YYModel中，包含了Class的property变量，还加上了Class的Method方法与Ivar的实例变量。对于Ivar来说，可能还存在在方法参数中，所以说所需要解析的类型会更加多一些。**


####代码
在YYClassInfo.h中，先定义了一个NS_OPTIONS：
```
typedef NS_OPTIONS(NSUInteger, YYEncodingType) {
    //0~8位：变量类型
    YYEncodingTypeMask       = 0xFF, ///< mask of type value
    YYEncodingTypeUnknown    = 0, ///< unknown
    YYEncodingTypeVoid       = 1, ///< void
    YYEncodingTypeBool       = 2, ///< bool
    YYEncodingTypeInt8       = 3, ///< char / BOOL
    YYEncodingTypeUInt8      = 4, ///< unsigned char
    YYEncodingTypeInt16      = 5, ///< short
    YYEncodingTypeUInt16     = 6, ///< unsigned short
    YYEncodingTypeInt32      = 7, ///< int
    YYEncodingTypeUInt32     = 8, ///< unsigned int
    YYEncodingTypeInt64      = 9, ///< long long
    YYEncodingTypeUInt64     = 10, ///< unsigned long long
    YYEncodingTypeFloat      = 11, ///< float
    YYEncodingTypeDouble     = 12, ///< double
    YYEncodingTypeLongDouble = 13, ///< long double
    YYEncodingTypeObject     = 14, ///< id
    YYEncodingTypeClass      = 15, ///< Class
    YYEncodingTypeSEL        = 16, ///< SEL
    YYEncodingTypeBlock      = 17, ///< block
    YYEncodingTypePointer    = 18, ///< void*
    YYEncodingTypeStruct     = 19, ///< struct
    YYEncodingTypeUnion      = 20, ///< union
    YYEncodingTypeCString    = 21, ///< char*
    YYEncodingTypeCArray     = 22, ///< char[10] (for example)
    
    //8~16位：方法类型
    YYEncodingTypeQualifierMask   = 0xFF00,   ///< mask of qualifier
    YYEncodingTypeQualifierConst  = 1 << 8,  ///< const
    YYEncodingTypeQualifierIn     = 1 << 9,  ///< in
    YYEncodingTypeQualifierInout  = 1 << 10, ///< inout
    YYEncodingTypeQualifierOut    = 1 << 11, ///< out
    YYEncodingTypeQualifierBycopy = 1 << 12, ///< bycopy
    YYEncodingTypeQualifierByref  = 1 << 13, ///< byref
    YYEncodingTypeQualifierOneway = 1 << 14, ///< oneway
    
    //16~24位：property修饰类型
    YYEncodingTypePropertyMask         = 0xFF0000, ///< mask of property
    YYEncodingTypePropertyReadonly     = 1 << 16, ///< readonly
    YYEncodingTypePropertyCopy         = 1 << 17, ///< copy
    YYEncodingTypePropertyRetain       = 1 << 18, ///< retain
    YYEncodingTypePropertyNonatomic    = 1 << 19, ///< nonatomic
    YYEncodingTypePropertyWeak         = 1 << 20, ///< weak
    YYEncodingTypePropertyCustomGetter = 1 << 21, ///< getter=
    YYEncodingTypePropertyCustomSetter = 1 << 22, ///< setter=
    YYEncodingTypePropertyDynamic      = 1 << 23, ///< @dynamic
};
```
该NS_OPTIONS主要定义了3个大类encode type:
* YYEncodingTypeMask:
变量类型，因为类型只会有一种，所以就用数字站位
* YYEncodingTypeQualifierMask:
方法中的参数变量修饰符，理论上只有解析Method的参数才能解析到
* YYEncodingTypePropertyMask
property修饰符类型

这边对于YYEncodingTypeQualifierMask和YYEncodingTypePropertyMask因为存在多种可能的情况，使用了位移(<<)的方式，通过与(&)YYEncodingTypeQualifierMask和YYEncodingTypePropertyMask的方式，判断是否包含某个值。

获取Ivar类型的函数如下：
```
//解析Ivar的type encode string
YYEncodingType YYEncodingGetType(const char *typeEncoding) {
    char *type = (char *)typeEncoding;
    if (!type) return YYEncodingTypeUnknown;
    size_t len = strlen(type);
    if (len == 0) return YYEncodingTypeUnknown;
    
    YYEncodingType qualifier = 0;
    bool prefix = true;
    while (prefix) {
        //方法参数Ivar中的解析，理论上解析不到该类参数
        switch (*type) {
            case 'r': {
                qualifier |= YYEncodingTypeQualifierConst;
                type++;
            } break;
            case 'n': {
                qualifier |= YYEncodingTypeQualifierIn;
                type++;
            } break;
            case 'N': {
                qualifier |= YYEncodingTypeQualifierInout;
                type++;
            } break;
            case 'o': {
                qualifier |= YYEncodingTypeQualifierOut;
                type++;
            } break;
            case 'O': {
                qualifier |= YYEncodingTypeQualifierBycopy;
                type++;
            } break;
            case 'R': {
                qualifier |= YYEncodingTypeQualifierByref;
                type++;
            } break;
            case 'V': {
                qualifier |= YYEncodingTypeQualifierOneway;
                type++;
            } break;
            default: { prefix = false; } break;
        }
    }

    len = strlen(type);
    if (len == 0) return YYEncodingTypeUnknown | qualifier;
    
    //返回值类型解析
    switch (*type) {
        case 'v': return YYEncodingTypeVoid | qualifier;
        case 'B': return YYEncodingTypeBool | qualifier;
        case 'c': return YYEncodingTypeInt8 | qualifier;
        case 'C': return YYEncodingTypeUInt8 | qualifier;
        case 's': return YYEncodingTypeInt16 | qualifier;
        case 'S': return YYEncodingTypeUInt16 | qualifier;
        case 'i': return YYEncodingTypeInt32 | qualifier;
        case 'I': return YYEncodingTypeUInt32 | qualifier;
        case 'l': return YYEncodingTypeInt32 | qualifier;
        case 'L': return YYEncodingTypeUInt32 | qualifier;
        case 'q': return YYEncodingTypeInt64 | qualifier;
        case 'Q': return YYEncodingTypeUInt64 | qualifier;
        case 'f': return YYEncodingTypeFloat | qualifier;
        case 'd': return YYEncodingTypeDouble | qualifier;
        case 'D': return YYEncodingTypeLongDouble | qualifier;
        case '#': return YYEncodingTypeClass | qualifier;
        case ':': return YYEncodingTypeSEL | qualifier;
        case '*': return YYEncodingTypeCString | qualifier;
        case '^': return YYEncodingTypePointer | qualifier;
        case '[': return YYEncodingTypeCArray | qualifier;
        case '(': return YYEncodingTypeUnion | qualifier;
        case '{': return YYEncodingTypeStruct | qualifier;
        case '@': {
            if (len == 2 && *(type + 1) == '?')
                return YYEncodingTypeBlock | qualifier;     //OC Block
            else
                return YYEncodingTypeObject | qualifier;    //OC对象
        }
        default: return YYEncodingTypeUnknown | qualifier;
    }
}
```
该函数也是通过获得的type encode的string，对照着表进行解析，因为是解析Ivar,所以也只包含了YYEncodingTypeMask和YYEncodingTypeQualifierMask。而YYEncodingTypePropertyMask会包含在property的解析中。


### (2).@interface YYClassIvarInfo : NSObject

####相关知识
我下载了runtime的源代码objc4-680.tar.gz，以下代码基于该版本。该版本包含旧代码与新代码，以下全部基于新代码。

**Ivar:**An opaque type that represents an instance variable(实例变量，跟某个对象关联，不能被静态方法使用，与之想对应的是class variable).
```
typedef struct ivar_t *Ivar;

struct ivar_t {
#if __x86_64__
    // *offset was originally 64-bit on some x86_64 platforms.
    // We read and write only 32 bits of it.
    // Some metadata provides all 64 bits. This is harmless for unsigned 
    // little-endian values.
    // Some code uses all 64 bits. class_addIvar() over-allocates the 
    // offset for their benefit.
#endif
    int32_t *offset;
    const char *name;
    const char *type;
    // alignment is sometimes -1; use alignment() instead
    uint32_t alignment_raw;
    uint32_t size;

    uint32_t alignment() const {
        if (alignment_raw == ~(uint32_t)0) return 1U << WORD_SHIFT;
        return 1 << alignment_raw;
    }
};
```

####代码

YYClassIvarInfo类声明：
```
/**
 Instance variable information.
 */
@interface YYClassIvarInfo : NSObject
@property (nonatomic, assign, readonly) Ivar ivar;              ///< ivar opaque struct ivar本身指针
@property (nonatomic, strong, readonly) NSString *name;         ///< Ivar's name        ivar名
@property (nonatomic, assign, readonly) ptrdiff_t offset;       ///< Ivar's offset      ivar偏移量
@property (nonatomic, strong, readonly) NSString *typeEncoding; ///< Ivar's type encoding   ivar encode string
@property (nonatomic, assign, readonly) YYEncodingType type;    ///< Ivar's type        ivar encode解析值

/**
 Creates and returns an ivar info object.
 
 @param ivar ivar opaque struct
 @return A new object, or nil if an error occurs.
 */
- (instancetype)initWithIvar:(Ivar)ivar;
@end
```

``initWithIvar``方法实现：
```
- (instancetype)initWithIvar:(Ivar)ivar {
    if (!ivar) return nil;
    self = [super init];
    _ivar = ivar;
    const char *name = ivar_getName(ivar);      //获取ivar名
    if (name) {
        _name = [NSString stringWithUTF8String:name];
    }
    _offset = ivar_getOffset(ivar);             //获取便宜量
    const char *typeEncoding = ivar_getTypeEncoding(ivar);  //获取类型encode string
    if (typeEncoding) {
        _typeEncoding = [NSString stringWithUTF8String:typeEncoding];
        _type = YYEncodingGetType(typeEncoding);    //类型解析
    }
    return self;
}
```
**YYClassIvarInfo本身就是对系统Ivar的一层封装，并进行了一次类型的解析。**
####实例
用YYModel测试用例来进行观察：
YYTestNestRepo实现：
```
@interface YYTestNestRepo : NSObject
@property uint64_t repoID;
@property NSString *name;
@property YYTestNestUser *user;
@end
@implementation YYTestNestRepo
@end
```
YYTestNestRepo调用：
```
NSString *json = @"{\"repoID\":1234,\"name\":\"YYModel\",\"user\":{\"uid\":5678,\"name\":\"ibireme\"}}";
YYTestNestRepo *repo = [YYTestNestRepo yy_modelWithJSON:json];
```
设置解析断点在解析``@property YYTestNestUser *user;``的Ivar变量处：


![YYClassIvarInfo-user](http://upload-images.jianshu.io/upload_images/1829891-685f64a25141524c.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

### (3).@interface YYClassMethodInfo : NSObject
####相关知识

**Method:**An opaque type that represents a method in a class definition.
```
typedef struct method_t *Method;

struct method_t {
    SEL name;
    const char *types;
    IMP imp;

    struct SortBySELAddress :
        public std::binary_function<const method_t&,
                                    const method_t&, bool>
    {
        bool operator() (const method_t& lhs,
                         const method_t& rhs)
        { return lhs.name < rhs.name; }
    };
};
```
其中包含两个结构体SEL和IMP：

**SEL:**An opaque type that represents a method selector
> Method selectors are used to represent the name of a method at runtime. A method selector is a C string that has been registered (or “mapped“) with the Objective-C runtime. Selectors generated by the compiler are automatically mapped by the runtime when the class is loaded.

```
typedef struct objc_selector *SEL;
```

**IMP:**A pointer to the function of a method implementation
> This data type is a pointer to the start of the function that implements the method. This function uses standard C calling conventions as implemented for the current CPU architecture. The first argument is a pointer to self (that is, the memory for the particular instance of this class, or, for a class method, a pointer to the metaclass). The second argument is the method selector. The method arguments follow.

```
#if !OBJC_OLD_DISPATCH_PROTOTYPES
typedef void (*IMP)(void /* id, SEL, ... */ ); 
#else
typedef id (*IMP)(id, SEL, ...); 
#endif
```

####代码
YYClassMethodInfo类声明：
```
@interface YYClassMethodInfo : NSObject
@property (nonatomic, assign, readonly) Method method;                  ///< method opaque struct method指针
@property (nonatomic, strong, readonly) NSString *name;                 ///< method name            method名
@property (nonatomic, assign, readonly) SEL sel;                        ///< method's selector      method selector
@property (nonatomic, assign, readonly) IMP imp;                        ///< method's implementation    method implementation
@property (nonatomic, strong, readonly) NSString *typeEncoding;         ///< method's parameter and return types    method的参数和返回类型
@property (nonatomic, strong, readonly) NSString *returnTypeEncoding;   ///< return value's type    method返回值的encode types
@property (nullable, nonatomic, strong, readonly) NSArray<NSString *> *argumentTypeEncodings; ///< array of arguments' type method参数列表

- (instancetype)initWithMethod:(Method)method;
@end
```

``initWithMethod``方法实现：
```
- (instancetype)initWithMethod:(Method)method {
    if (!method) return nil;
    self = [super init];
    _method = method;
    _sel = method_getName(method);                      //获取方法名，在oc中，方法名就是selector的标志
    _imp = method_getImplementation(method);            //获取方法实现
    const char *name = sel_getName(_sel);
    if (name) {
        _name = [NSString stringWithUTF8String:name];
    }
    const char *typeEncoding = method_getTypeEncoding(method);  //获得方法参数和返回值
    if (typeEncoding) {
        _typeEncoding = [NSString stringWithUTF8String:typeEncoding];
    }
    char *returnType = method_copyReturnType(method);           //获得返回值encode string
    if (returnType) {
        _returnTypeEncoding = [NSString stringWithUTF8String:returnType];
        free(returnType);
    }
    unsigned int argumentCount = method_getNumberOfArguments(method);       //获得方法参数数量
    if (argumentCount > 0) {
        NSMutableArray *argumentTypes = [NSMutableArray new];
        for (unsigned int i = 0; i < argumentCount; i++) {                  //遍历参数
            char *argumentType = method_copyArgumentType(method, i);        //获得该参数的encode string
            NSString *type = argumentType ? [NSString stringWithUTF8String:argumentType] : nil;
            [argumentTypes addObject:type ? type : @""];
            if (argumentType) free(argumentType);
        }
        _argumentTypeEncodings = argumentTypes;
    }
    return self;
}
```


####实例
用YYModel测试用例来进行观察：
YYTestNestRepo实现：
```
@interface YYTestNestRepo : NSObject
@property uint64_t repoID;
@property NSString *name;
@property YYTestNestUser *user;
@end
@implementation YYTestNestRepo
@end
```
YYTestNestRepo调用：
```
NSString *json = @"{\"repoID\":1234,\"name\":\"YYModel\",\"user\":{\"uid\":5678,\"name\":\"ibireme\"}}";
YYTestNestRepo *repo = [YYTestNestRepo yy_modelWithJSON:json];
```
设置解析断点解析``user``方法：


![YYClassMethodInfo-user](http://upload-images.jianshu.io/upload_images/1829891-63ab0191bc86c50d.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)



对于property来说，本质是:Ivar+getter+setter，所以设置了property也会触发initWithMethod解析``-(YYTestNestUser *) user;``方法，该方法的解析如上图。

**这边比较有意思的是，明明user没有参数，怎么``method_getNumberOfArguments ``解析出来2个参数**
**原因就是方法调用最后都会转成``((void (*)(id, SEL))objc_msgSend)((id)m, @selector(user));``**，所以会有两个参数。

### (4).@interface YYClassPropertyInfo : NSObject

####相关知识
**Property:**An opaque type that represents an Objective-C declared property.
```
typedef struct property_t *objc_property_t;

struct property_t {
    const char *name;
    const char *attributes;
};
```
其中对于attributes就是property属性的encode string。具体解析可以参考JSONModel的文章。

####代码
YYClassPropertyInfo类声明：
```
@interface YYClassPropertyInfo : NSObject
@property (nonatomic, assign, readonly) objc_property_t property; ///< property's opaque struct     property指针
@property (nonatomic, strong, readonly) NSString *name;           ///< property's name              property名
@property (nonatomic, assign, readonly) YYEncodingType type;      ///< property's type              property encode解析值
@property (nonatomic, strong, readonly) NSString *typeEncoding;   ///< property's encoding value    property encode string
@property (nonatomic, strong, readonly) NSString *ivarName;       ///< property's ivar name         property对应的ivar名字
@property (nullable, nonatomic, assign, readonly) Class cls;      ///< may be nil                   property如果是oc类型，oc类型对应的class
@property (nullable, nonatomic, strong, readonly) NSArray<NSString *> *protocols; ///< may nil      property如果存在protocol，protocol列表
@property (nonatomic, assign, readonly) SEL getter;               ///< getter (nonnull)             property的getter方法
@property (nonatomic, assign, readonly) SEL setter;               ///< setter (nonnull)             property的setter方法

- (instancetype)initWithProperty:(objc_property_t)property;
@end
```
``initWithProperty``方法实现：

```
- (instancetype)initWithProperty:(objc_property_t)property {
    if (!property) return nil;
    self = [super init];
    _property = property;
    const char *name = property_getName(property);              //获得property名
    if (name) {
        _name = [NSString stringWithUTF8String:name];
    }
    
    YYEncodingType type = 0;
    unsigned int attrCount;
    objc_property_attribute_t *attrs = property_copyAttributeList(property, &attrCount);    //获得所有property的attribute array
    for (unsigned int i = 0; i < attrCount; i++) {
        switch (attrs[i].name[0]) {
            case 'T': { // Type encoding            表示是property类型
                if (attrs[i].value) {
                    _typeEncoding = [NSString stringWithUTF8String:attrs[i].value];     //获得attribute的encode string
                    type = YYEncodingGetType(attrs[i].value);                           //解析type
                    
                    if ((type & YYEncodingTypeMask) == YYEncodingTypeObject && _typeEncoding.length) {      //代表是OC类型
                        NSScanner *scanner = [NSScanner scannerWithString:_typeEncoding];               //扫描attribute的encode string
                        if (![scanner scanString:@"@\"" intoString:NULL]) continue;                //不包含@\"代表不是oc类型，跳过
                        
                        NSString *clsName = nil;
                        if ([scanner scanUpToCharactersFromSet: [NSCharacterSet characterSetWithCharactersInString:@"\"<"] intoString:&clsName]) {  //扫描oc类型string，在 \"之前
                            if (clsName.length) _cls = objc_getClass(clsName.UTF8String);               //获得oc对象类型，并附值
                        }
                        
                        NSMutableArray *protocols = nil;
                        while ([scanner scanString:@"<" intoString:NULL]) {                 //扫描<>中的protocol类型，并设置
                            NSString* protocol = nil;
                            if ([scanner scanUpToString:@">" intoString: &protocol]) {
                                if (protocol.length) {
                                    if (!protocols) protocols = [NSMutableArray new];
                                    [protocols addObject:protocol];
                                }
                            }
                            [scanner scanString:@">" intoString:NULL];
                        }
                        _protocols = protocols;
                    }
                }
            } break;
            case 'V': { // Instance variable                        //ivar变量
                if (attrs[i].value) {
                    _ivarName = [NSString stringWithUTF8String:attrs[i].value];
                }
            } break;
            case 'R': {                                             //以下为property的几种类型扫描,setter和getter方法要记录方法名
                type |= YYEncodingTypePropertyReadonly;
            } break;
            case 'C': {
                type |= YYEncodingTypePropertyCopy;
            } break;
            case '&': {
                type |= YYEncodingTypePropertyRetain;
            } break;
            case 'N': {
                type |= YYEncodingTypePropertyNonatomic;
            } break;
            case 'D': {
                type |= YYEncodingTypePropertyDynamic;
            } break;
            case 'W': {
                type |= YYEncodingTypePropertyWeak;
            } break;
            case 'G': {
                type |= YYEncodingTypePropertyCustomGetter;
                if (attrs[i].value) {
                    _getter = NSSelectorFromString([NSString stringWithUTF8String:attrs[i].value]);
                }
            } break;
            case 'S': {
                type |= YYEncodingTypePropertyCustomSetter;
                if (attrs[i].value) {
                    _setter = NSSelectorFromString([NSString stringWithUTF8String:attrs[i].value]);
                }
            } // break; commented for code coverage in next line
            default: break;
        }
    }
    if (attrs) {                //有attrs要free
        free(attrs);
        attrs = NULL;
    }
    
    _type = type;               //最后设置encode解析值
    if (_name.length) {             //设置默认的getter方法和setter方法
        if (!_getter) {
            _getter = NSSelectorFromString(_name);
        }
        if (!_setter) {
            _setter = NSSelectorFromString([NSString stringWithFormat:@"set%@%@:", [_name substringToIndex:1].uppercaseString, [_name substringFromIndex:1]]);
        }
    }
    return self;
}
```

这段的解析方式和之前JSONModel的解析property方式有些类似，也不多做介绍了。

####实例
用YYModel测试用例来进行观察：
YYTestNestRepo实现：
```
@interface YYTestNestRepo : NSObject
@property uint64_t repoID;
@property NSString *name;
@property YYTestNestUser *user;
@end
@implementation YYTestNestRepo
@end
```
YYTestNestRepo调用：
```
NSString *json = @"{\"repoID\":1234,\"name\":\"YYModel\",\"user\":{\"uid\":5678,\"name\":\"ibireme\"}}";
YYTestNestRepo *repo = [YYTestNestRepo yy_modelWithJSON:json];
```
设置解析断点解析property-user：


![property-user](http://upload-images.jianshu.io/upload_images/1829891-fb7683d2d4bd0367.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

### (5).@interface YYClassInfo : NSObject

####相关知识

**Class:**An opaque type that represents an Objective-C class.
```
typedef struct objc_class *Class;

struct objc_class : objc_object {
    Class superclass;
    const char *name;
    uint32_t version;
    uint32_t info;
    uint32_t instance_size;
    struct old_ivar_list *ivars;
    struct old_method_list **methodLists;
    Cache cache;
    struct old_protocol_list *protocols;
    // CLS_EXT only
    const uint8_t *ivar_layout;
    struct old_class_ext *ext;

    ...
}

struct objc_object {
private:
    isa_t isa;

public:
 
    ...
}
```

对Class的superclass和isa指针来说，网上有一个特别多转载的图：
![superclass and metaclass](http://upload-images.jianshu.io/upload_images/1829891-f88d2588ada3e99e.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
上图实线是 super_class 指针，虚线是isa指针。 有趣的是根元类的超类是NSObject，而isa指向了自己，而NSObject的超类为nil，也就是它没有超类。

####代码
YYClassInfo类声明：
```
@interface YYClassInfo : NSObject
@property (nonatomic, assign, readonly) Class cls; ///< class object                        class指针
@property (nullable, nonatomic, assign, readonly) Class superCls; ///< super class object   superClass指针
@property (nullable, nonatomic, assign, readonly) Class metaCls;  ///< class's meta class object    metaClass指针
@property (nonatomic, readonly) BOOL isMeta; ///< whether this class is meta class          是否该class是metaclass
@property (nonatomic, strong, readonly) NSString *name; ///< class name                     class名
@property (nullable, nonatomic, strong, readonly) YYClassInfo *superClassInfo; ///< super class's class info    superClass的classinfo（缓存）
@property (nullable, nonatomic, strong, readonly) NSDictionary<NSString *, YYClassIvarInfo *> *ivarInfos; ///< ivars        ivar的dictionary,key为ivar的name
@property (nullable, nonatomic, strong, readonly) NSDictionary<NSString *, YYClassMethodInfo *> *methodInfos; ///< methods  method的dictionary,key为method的name
@property (nullable, nonatomic, strong, readonly) NSDictionary<NSString *, YYClassPropertyInfo *> *propertyInfos; ///< properties   properties的dictionary,key为property的name
//设置class更新，比如动态增加了一个方法，需要更新class
- (void)setNeedUpdate;
//返回class是否需要更新，更新则应该调用下面两个方法之一
- (BOOL)needUpdate;
+ (nullable instancetype)classInfoWithClass:(Class)cls;
+ (nullable instancetype)classInfoWithClassName:(NSString *)className;

@end
```
YYClassInfo中有一个needUpdate是否更新的标识符，当手动更改class结构(比如``class_addMethod()``等)的时候，可以调用方法：

```
@implementation YYClassInfo {
    BOOL _needUpdate;           //是否需要更新private变量
}

- (void)setNeedUpdate {         //设置需要更新
    _needUpdate = YES;
}

- (BOOL)needUpdate {            //返回是否需要更新
    return _needUpdate;
}
```
实际的解析方法：

```

//多一层class从nsstring到class对象的转换
+ (instancetype)classInfoWithClassName:(NSString *)className {
    Class cls = NSClassFromString(className);
    return [self classInfoWithClass:cls];
}

//class解析主体方法
+ (instancetype)classInfoWithClass:(Class)cls {
    if (!cls) return nil;
    static CFMutableDictionaryRef classCache;           //class缓存
    static CFMutableDictionaryRef metaCache;            //meta class缓存
    static dispatch_once_t onceToken;
    static dispatch_semaphore_t lock;                   //锁
    dispatch_once(&onceToken, ^{                        //初始化两种缓存
        classCache = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        metaCache = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        lock = dispatch_semaphore_create(1);
    });
    dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);       //只允许同时1个线程
    YYClassInfo *info = CFDictionaryGetValue(class_isMetaClass(cls) ? metaCache : classCache, (__bridge const void *)(cls));        //获取曾经解析过的缓存
    if (info && info->_needUpdate) {        //如果存在且需要更新，则重新解析class并更新结构体
        [info _update];
    }
    dispatch_semaphore_signal(lock);                        //释放锁
    if (!info) {                                            //如果没有缓存，则第一次解析class
        info = [[YYClassInfo alloc] initWithClass:cls];
        if (info) {                                         //解析完毕设置缓存
            dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
            CFDictionarySetValue(info.isMeta ? metaCache : classCache, (__bridge const void *)(cls), (__bridge const void *)(info));
            dispatch_semaphore_signal(lock);
        }
    }
    return info;
}

```
``classInfoWithClass``方法中主要调用了两个方法``- (instancetype)initWithClass:(Class)cls``（初始化class）和``- (void)_update``（更新class），接下来看该两个方法的实现。

```
//初始化class对象方法
- (instancetype)initWithClass:(Class)cls {
    if (!cls) return nil;
    self = [super init];
    _cls = cls;
    _superCls = class_getSuperclass(cls);           //设置superclass
    _isMeta = class_isMetaClass(cls);               //判断是否是metaclass
    if (!_isMeta) {                                 //不是的话获得meta class
        _metaCls = objc_getMetaClass(class_getName(cls));
    }
    _name = NSStringFromClass(cls);                 //获得类名
    [self _update];                                 //进行更新

    _superClassInfo = [self.class classInfoWithClass:_superCls];    //递归superclass
    return self;
}
```
这边也用到了````- (void)_update``（更新class），这应该就是class的核心更新方法：

```
//更新函数
- (void)_update {
    _ivarInfos = nil;                   //重置ivar，mthod，property3个缓存dictionary
    _methodInfos = nil;
    _propertyInfos = nil;
    
    Class cls = self.cls;
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    if (methods) {                      //解析method，并以name为key，进行缓存设置
        NSMutableDictionary *methodInfos = [NSMutableDictionary new];
        _methodInfos = methodInfos;
        for (unsigned int i = 0; i < methodCount; i++) {
            YYClassMethodInfo *info = [[YYClassMethodInfo alloc] initWithMethod:methods[i]];
            if (info.name) methodInfos[info.name] = info;
        }
        free(methods);
    }
    unsigned int propertyCount = 0;
    objc_property_t *properties = class_copyPropertyList(cls, &propertyCount);
    if (properties) {                   //解析property，并以name为key，进行缓存设置
        NSMutableDictionary *propertyInfos = [NSMutableDictionary new];
        _propertyInfos = propertyInfos;
        for (unsigned int i = 0; i < propertyCount; i++) {
            YYClassPropertyInfo *info = [[YYClassPropertyInfo alloc] initWithProperty:properties[i]];
            if (info.name) propertyInfos[info.name] = info;
        }
        free(properties);
    }
    
    unsigned int ivarCount = 0;
    Ivar *ivars = class_copyIvarList(cls, &ivarCount);
    if (ivars) {                        //解析ivar，并以name为key，进行缓存设置
        NSMutableDictionary *ivarInfos = [NSMutableDictionary new];
        _ivarInfos = ivarInfos;
        for (unsigned int i = 0; i < ivarCount; i++) {
            YYClassIvarInfo *info = [[YYClassIvarInfo alloc] initWithIvar:ivars[i]];
            if (info.name) ivarInfos[info.name] = info;
        }
        free(ivars);
    }
    
    if (!_ivarInfos) _ivarInfos = @{};          //如果不存在相应的方法，则初始化空的dictionary给相应的方法
    if (!_methodInfos) _methodInfos = @{};
    if (!_propertyInfos) _propertyInfos = @{};
    
    _needUpdate = NO;                           //已经更新完成，设no
}
```
该函数虽然比较长，但也比较好理解，就是将method,property,ivar全部取出并附值给缓存。

####实例
用YYModel测试用例来进行观察：
YYTestNestRepo实现：
```
@interface YYTestNestRepo : NSObject
@property uint64_t repoID;
@property NSString *name;
@property YYTestNestUser *user;
@end
@implementation YYTestNestRepo
@end
```
YYTestNestRepo调用：
```
NSString *json = @"{\"repoID\":1234,\"name\":\"YYModel\",\"user\":{\"uid\":5678,\"name\":\"ibireme\"}}";
YYTestNestRepo *repo = [YYTestNestRepo yy_modelWithJSON:json];
```
设置解析断点解析class YYTestNestRepo：

![class YYTestNestRepo](http://upload-images.jianshu.io/upload_images/1829891-4b174bac457408e9.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

**至此，整个model的class信息全部被解析完成，然后设置到了YYClassInfo类型的上。**

##小结
相对于JSONModel只对Property进行解析然后缓存。
YYModel将Class的Method,Property,Ivar全部进行了解析与缓存。

其中比较亮点的地方：
* 1.Ivar和property解析出来的YYEncodingType
* 2.CFMutableDictionaryRef的缓存
* 3.可以动态更新的needUpdate

##参考资料
[本文csdn地址](http://blog.csdn.net/game3108/article/details/52398880)
1.[郑钦洪_：YYModel 源码历险记](http://www.jianshu.com/users/aa41dad549af/latest_articles)
2.[Objective-C Runtime Programming Guide - Declared Properties](https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtPropertyIntrospection.html)
3.[Objective-C Runtime Programming Guide - Type Encodings](https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html)
4.[runtime源代码](http://opensource.apple.com/tarballs/objc4/)
5.[Objective-C Runtime的数据类型](http://www.cnblogs.com/whyandinside/archive/2013/02/26/2933552.html)
6.[轻松学习之三——IMP指针的作用](http://www.jianshu.com/p/425a39d43d16)
7.[runtime Method](http://www.huangyibiao.com/archives/400)
8.[apple-objective_c runtime](https://developer.apple.com/reference/objectivec/1657527-objective_c_runtime?language=objc)
9.[Objective-C Runtime](http://yulingtianxia.com/blog/2014/11/05/objective-c-runtime/)
