##前言
本文的中文注释代码demo更新在我的[github](https://github.com/game3108/BlogDemo/tree/master/YYModelDemo)上。

 上篇 [YYModel源代码分析（二）YYClassInfo
](http://www.jianshu.com/p/012dbce17a50) 主要分析了YYClassInfo文件。本篇会主要集中在NSObject+YYModel文件上。文章内容会包含一些与JSONModel的比较，想了解JSONModel，可以参考[JSONModel源代码解析](http://www.jianshu.com/p/64ce3927eb62)。

##主体分层
NSObject+YYModel主要分为以下几个部分：

*  内部使用的C函数部分
* ``@interface _YYModelPropertyMeta : NSObject``
* ``@interface _YYModelMeta : NSObject``
* ``@interface NSObject (YYModel) : NSObject``
* ``@interface NSArray (YYModel) : NSObject``
* ``@interface NSDictionary (YYModel) : NSObject``
* ``@protocol YYModel <NSObject>``:接口YYModel

由于代码较多，所以会挑重点的部分进行介绍。

##NSObject+YYModel源代码

###@interface _YYModelPropertyMeta : NSObject
####声明
```
/// A property info in object model.
// model property的进一步分装
@interface _YYModelPropertyMeta : NSObject {
    @package
    NSString *_name;             ///< property's name                   //property名
    YYEncodingType _type;        ///< property's type                   //property的encode解析值
    YYEncodingNSType _nsType;    ///< property's Foundation type        //property的foundation类型
    BOOL _isCNumber;             ///< is c number type                  //是不是c语言的数字
    Class _cls;                  ///< property's class, or nil          //property的class
    Class _genericCls;           ///< container's generic class, or nil if threr's no generic class     //property内包含的类class
    SEL _getter;                 ///< getter, or nil if the instances cannot respond        //property getter方法
    SEL _setter;                 ///< setter, or nil if the instances cannot respond        //property setter方法
    BOOL _isKVCCompatible;       ///< YES if it can access with key-value coding            //是否可以使用KVC
    BOOL _isStructAvailableForKeyedArchiver; ///< YES if the struct can encoded with keyed archiver/unarchiver      //是否是struct并且可以archiver/unarchiver
    BOOL _hasCustomClassFromDictionary; ///< class/generic class implements +modelCustomClassForDictionary:     //是否包含本本地的class转换
    
    /*
     property->key:       _mappedToKey:key     _mappedToKeyPath:nil            _mappedToKeyArray:nil
     property->keyPath:   _mappedToKey:keyPath _mappedToKeyPath:keyPath(array) _mappedToKeyArray:nil
     property->keys:      _mappedToKey:keys[0] _mappedToKeyPath:nil/keyPath    _mappedToKeyArray:keys(array)
     */
    NSString *_mappedToKey;      ///< the key mapped to                                     //property本地的key mapper的key
    NSArray *_mappedToKeyPath;   ///< the key path mapped to (nil if the name is not key path)  //property本地的key mapper的key path列表
    NSArray *_mappedToKeyArray;  ///< the key(NSString) or keyPath(NSArray) array (nil if not mapped to multiple keys) /property本地的key mapper的key列表
    YYClassPropertyInfo *_info;  ///< property's info                                   //property的YYClassPropertyInfo info
    _YYModelPropertyMeta *_next; ///< next meta if there are multiple properties mapped to the same key.      //同个key的多个property的映射next指针
}
@end
```
其中需要理解一下的包括：
1.``_hasCustomClassFromDictionary``就是判断是否有本地的不同class的映射
如下例子，当dictionary包含不同的值的时候，映射的model类型不同
```
@implementation YYBaseUser
+ (Class)modelCustomClassForDictionary:(NSDictionary*)dictionary {
    if (dictionary[@"localName"]) {
        return [YYLocalUser class];
    } else if (dictionary[@"remoteName"]) {
        return [YYRemoteUser class];
    }
    return [YYBaseUser class];
}
```
2.keyMapper相关内容
如下例子，dictionary中不同的key，对应的model的property有一个映射关系
其中对于包含"."的映射，则是一种多层的映射关系
```
+ (NSDictionary *)modelCustomPropertyMapper {
    return @{ @"name" : @"n",
              @"count" : @"ext.c",
              @"desc1" : @"ext.d", // mapped to same key path
              @"desc2" : @"ext.d", // mapped to same key path
              @"desc3" : @"ext.d.e",
              @"desc4" : @".ext",
              @"modelID" : @[@"ID", @"Id", @"id", @"ext.id"]};
}
```
3.``_YYModelPropertyMeta *_next``同一个key的下一个meta解析类型
因为有了key mapper，所以会出现同一个mapper的key值，可能会一对多个model的property值，这边设计了一个_next指针进行链接


4.``Class _genericCls``包含的类型
如下例子，property会有NSArray\NSDictionary\NSSet类型，内部的类型就通过该参数表示
```
@interface YYTestCustomClassModel : NSObject
@property (nonatomic, strong) NSArray *users;
@property (nonatomic, strong) NSDictionary *userDict;
@property (nonatomic, strong) NSSet *userSet;
@end

+ (NSDictionary *)modelContainerPropertyGenericClass {
    return @{@"users" : YYBaseUser.class,
             @"userDict" : YYBaseUser.class,
             @"userSet" : YYBaseUser.class};
}
```
####实现
```
//通过YYClassInfo，YYClassPropertyInfo，Class对象解析成_YYModelPropertyMeta
+ (instancetype)metaWithClassInfo:(YYClassInfo *)classInfo propertyInfo:(YYClassPropertyInfo *)propertyInfo generic:(Class)generic {
    
    // support pseudo generic class with protocol name
    // 这边也考虑了，某些类型写在protocol中，包含在<>中，和JSONModel一样进行一下protocol的类型判断
    // 比如NSArray<TestObject> xxx
    if (!generic && propertyInfo.protocols) {
        for (NSString *protocol in propertyInfo.protocols) {
            Class cls = objc_getClass(protocol.UTF8String);
            if (cls) {
                generic = cls;
                break;
            }
        }
    }
    
    //构造_YYModelPropertyMeta对象
    _YYModelPropertyMeta *meta = [self new];
    meta->_name = propertyInfo.name;                //设置名
    meta->_type = propertyInfo.type;                //设置encode type
    meta->_info = propertyInfo;                     //设置YYClassPropertyInfo
    meta->_genericCls = generic;                    //设置可能有的包含类
    
    if ((meta->_type & YYEncodingTypeMask) == YYEncodingTypeObject) {   //如果是OC对象，则判断是不是标准oc foundation类型
        meta->_nsType = YYClassGetNSType(propertyInfo.cls);
    } else {
        meta->_isCNumber = YYEncodingTypeIsCNumber(meta->_type);        //判断是否是c 数字
    }
    if ((meta->_type & YYEncodingTypeMask) == YYEncodingTypeStruct) {       //判断和是否是struct
        /*
         It seems that NSKeyedUnarchiver cannot decode NSValue except these structs:
         */
        //NSKeyedUnarchiver只可以解析以下的struct
        static NSSet *types = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSMutableSet *set = [NSMutableSet new];
            // 32 bit
            [set addObject:@"{CGSize=ff}"];
            [set addObject:@"{CGPoint=ff}"];
            [set addObject:@"{CGRect={CGPoint=ff}{CGSize=ff}}"];
            [set addObject:@"{CGAffineTransform=ffffff}"];
            [set addObject:@"{UIEdgeInsets=ffff}"];
            [set addObject:@"{UIOffset=ff}"];
            // 64 bit
            [set addObject:@"{CGSize=dd}"];
            [set addObject:@"{CGPoint=dd}"];
            [set addObject:@"{CGRect={CGPoint=dd}{CGSize=dd}}"];
            [set addObject:@"{CGAffineTransform=dddddd}"];
            [set addObject:@"{UIEdgeInsets=dddd}"];
            [set addObject:@"{UIOffset=dd}"];
            types = set;
        });
        if ([types containsObject:propertyInfo.typeEncoding]) {
            meta->_isStructAvailableForKeyedArchiver = YES;
        }
    }
    meta->_cls = propertyInfo.cls;      //设置类
    
    if (generic) {      //如果是包含类的话，用包含类去判断是否需要类型转换
        meta->_hasCustomClassFromDictionary = [generic respondsToSelector:@selector(modelCustomClassForDictionary:)];
    } else if (meta->_cls && meta->_nsType == YYEncodingTypeNSUnknown) {        //如果是其它oc类型，用类型去判断是否需要类型转换
        meta->_hasCustomClassFromDictionary = [meta->_cls respondsToSelector:@selector(modelCustomClassForDictionary:)];
    }
    
    //设置getter方法
    if (propertyInfo.getter) {
        if ([classInfo.cls instancesRespondToSelector:propertyInfo.getter]) {
            meta->_getter = propertyInfo.getter;
        }
    }
    
    //设置setter方法
    if (propertyInfo.setter) {
        if ([classInfo.cls instancesRespondToSelector:propertyInfo.setter]) {
            meta->_setter = propertyInfo.setter;
        }
    }
    
    //如果包含getter和setter方法
    if (meta->_getter && meta->_setter) {
        /*
         KVC invalid type:
         long double
         pointer (such as SEL/CoreFoundation object)
         */
        //以下代表可以使用kvc进行附值
        switch (meta->_type & YYEncodingTypeMask) {
            case YYEncodingTypeBool:
            case YYEncodingTypeInt8:
            case YYEncodingTypeUInt8:
            case YYEncodingTypeInt16:
            case YYEncodingTypeUInt16:
            case YYEncodingTypeInt32:
            case YYEncodingTypeUInt32:
            case YYEncodingTypeInt64:
            case YYEncodingTypeUInt64:
            case YYEncodingTypeFloat:
            case YYEncodingTypeDouble:
            case YYEncodingTypeObject:
            case YYEncodingTypeClass:
            case YYEncodingTypeBlock:
            case YYEncodingTypeStruct:
            case YYEncodingTypeUnion: {
                meta->_isKVCCompatible = YES;
            } break;
            default: break;
        }
    }
    
    return meta;
}
```
实现部分还是容易理解，主要还是通过YYClassInfo，YYClassPropertyInfo，Class对象解析成_YYModelPropertyMeta。

###@interface _YYModelMeta : NSObject
####声明
```
/// A class info in object model.
// model class的进一层封装
@interface _YYModelMeta : NSObject {
    @package
    YYClassInfo *_classInfo;            //YYClassInfo类型
    /// Key:mapped key and key path, Value:_YYModelPropertyMeta.
    NSDictionary *_mapper;              //key mapper的值，key是mapped key and key path，Value是_YYModelPropertyMeta类型
    /// Array<_YYModelPropertyMeta>, all property meta of this model.
    NSArray *_allPropertyMetas;         //所有的_YYModelPropertyMeta列表
    /// Array<_YYModelPropertyMeta>, property meta which is mapped to a key path.
    NSArray *_keyPathPropertyMetas;     //所有的路径映射property缓存
    /// Array<_YYModelPropertyMeta>, property meta which is mapped to multi keys.
    NSArray *_multiKeysPropertyMetas;   //所有的多层映射property缓存
    /// The number of mapped key (and key path), same to _mapper.count.
    NSUInteger _keyMappedCount;         //key mapper数量
    /// Model class type.
    YYEncodingNSType _nsType;           //model class的oc类型
    
    BOOL _hasCustomWillTransformFromDictionary;     //是否包含本地的某些值进行替换
    BOOL _hasCustomTransformFromDictionary;         //是否有本地的值的类型判断
    BOOL _hasCustomTransformToDictionary;           //与上个相反，当转成dictionary的时候，转换的方式
    BOOL _hasCustomClassFromDictionary;             //是否有本地的类型的转换
}
@end
```
其中，需要理解的包括：
1.
```
NSDictionary *_mapper;
NSArray *_allPropertyMetas; 
NSArray *_keyPathPropertyMetas; 
NSArray *_multiKeysPropertyMetas;
```
_mapper是包括了所有class和superclass的property的key value缓存，其中的key是所有已经映射过key name和不需要映射的property name组成。
_allPropertyMetas是所有class和superclass的property解析_YYModelPropertyMeta列表。
_keyPathPropertyMetas是表示映射如果是一个路径比如`` @"count" : @"ext.c"``下的_YYModelPropertyMeta列表。
_multiKeysPropertyMetas是表示映射如果是一个NSArray比如``@"modelID" : @[@"ID", @"Id", @"id", @"ext.id"]``下的_YYModelPropertyMeta列表。

2.
```
    BOOL _hasCustomWillTransformFromDictionary;     //是否包含本地的某些值进行替换
    BOOL _hasCustomTransformFromDictionary;         //是否有本地的值的类型判断
    BOOL _hasCustomTransformToDictionary;           //与上个相反，当转成dictionary的时候，转换的方式
    BOOL _hasCustomClassFromDictionary;             //是否有本地的类型的转换
```
判断方式：
```
    _hasCustomWillTransformFromDictionary = ([cls instancesRespondToSelector:@selector(modelCustomWillTransformFromDictionary:)]);
    _hasCustomTransformFromDictionary = ([cls instancesRespondToSelector:@selector(modelCustomTransformFromDictionary:)]);
    _hasCustomTransformToDictionary = ([cls instancesRespondToSelector:@selector(modelCustomTransformToDictionary:)]);
    _hasCustomClassFromDictionary = ([cls respondsToSelector:@selector(modelCustomClassForDictionary:)]);
```
对应的实际例子：
```
@interface YYTestCustomTransformModel : NSObject
@property uint64_t id;
@property NSString *content;
@property NSDate *time;
@end

-(NSDictionary *)modelCustomWillTransformFromDictionary:(NSDictionary *)dic{
    if (dic) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:dic];
        if (dict[@"date"]) {
            dict[@"time"] = dict[@"date"];
        }
        return dict;
    }
    return dic;
}

- (BOOL)modelCustomTransformFromDictionary:(NSDictionary *)dic {
    NSNumber *time = dic[@"time"];
    if ([time isKindOfClass:[NSNumber class]] && time.unsignedLongLongValue != 0) {
        _time = [NSDate dateWithTimeIntervalSince1970:time.unsignedLongLongValue / 1000.0];
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)modelCustomTransformToDictionary:(NSMutableDictionary *)dic {
    if (_time) {
        dic[@"time"] = @((uint64_t)(_time.timeIntervalSince1970 * 1000));
        return YES;
    } else {
        return NO;
    }
}
```
最后一个在``_YYModelPropertyMeta``已经提过，这里不再提。

####实现

```
- (instancetype)initWithClass:(Class)cls {
    YYClassInfo *classInfo = [YYClassInfo classInfoWithClass:cls];      //构造 YYClassInfo结构体
    if (!classInfo) return nil;
    self = [super init];
    
    // Get black list
    NSSet *blacklist = nil;
    if ([cls respondsToSelector:@selector(modelPropertyBlacklist)]) {       //黑名单，不解析的property
        NSArray *properties = [(id<YYModel>)cls modelPropertyBlacklist];
        if (properties) {
            blacklist = [NSSet setWithArray:properties];
        }
    }
    
    // Get white list
    NSSet *whitelist = nil;
    if ([cls respondsToSelector:@selector(modelPropertyWhitelist)]) {       //白名单，只解析的property
        NSArray *properties = [(id<YYModel>)cls modelPropertyWhitelist];
        if (properties) {
            whitelist = [NSSet setWithArray:properties];
        }
    }
    
    // Get container property's generic class
    //获得包含的类的类型
    NSDictionary *genericMapper = nil;
    if ([cls respondsToSelector:@selector(modelContainerPropertyGenericClass)]) {
        genericMapper = [(id<YYModel>)cls modelContainerPropertyGenericClass];      //获得包含类映射的dictionary
        if (genericMapper) {
            NSMutableDictionary *tmp = [NSMutableDictionary new];
            [genericMapper enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {        //遍历dictionary
                if (![key isKindOfClass:[NSString class]]) return;
                Class meta = object_getClass(obj);          //获得映射的类型
                if (!meta) return;                          //不是类型返回
                if (class_isMetaClass(meta)) {              //如果是meta class的话,直接设置（因为是对象的类类型)
                    tmp[key] = obj;
                } else if ([obj isKindOfClass:[NSString class]]) {  //如果是string的话，转成class，设置
                    Class cls = NSClassFromString(obj);
                    if (cls) {
                        tmp[key] = cls;
                    }
                }
            }];
            genericMapper = tmp;                    //获得包含类的映射dictionary
        }
    }
    
    // Create all property metas.
    NSMutableDictionary *allPropertyMetas = [NSMutableDictionary new];
    YYClassInfo *curClassInfo = classInfo;
    
    //递归class和superclass，但忽略nsobject/nsproxy
    while (curClassInfo && curClassInfo.superCls != nil) { // recursive parse super class, but ignore root class (NSObject/NSProxy)
        //获得class的所有YYClassPropertyInfo缓存
        for (YYClassPropertyInfo *propertyInfo in curClassInfo.propertyInfos.allValues) {
            if (!propertyInfo.name) continue;
            if (blacklist && [blacklist containsObject:propertyInfo.name]) continue;    //跳过黑名单
            if (whitelist && ![whitelist containsObject:propertyInfo.name]) continue;   //只判断拍名单
            //构造_YYModelPropertyMeta结构体
            _YYModelPropertyMeta *meta = [_YYModelPropertyMeta metaWithClassInfo:classInfo
                                                                    propertyInfo:propertyInfo
                                                                         generic:genericMapper[propertyInfo.name]];
            if (!meta || !meta->_name) continue;                        //没有名字跳过
            if (!meta->_getter || !meta->_setter) continue;             //没有getter或者setter方法跳过
            if (allPropertyMetas[meta->_name]) continue;                //已经解析过的跳过
            allPropertyMetas[meta->_name] = meta;                       //将解析通过dictionary缓存
        }
        curClassInfo = curClassInfo.superClassInfo;                 //递归super class
    }
    if (allPropertyMetas.count) _allPropertyMetas = allPropertyMetas.allValues.copy;    //复制一份解析出来的所有allPropertyMetas
    
    // create mapper
    //开始key mapper映射
    NSMutableDictionary *mapper = [NSMutableDictionary new];
    NSMutableArray *keyPathPropertyMetas = [NSMutableArray new];
    NSMutableArray *multiKeysPropertyMetas = [NSMutableArray new];
    
    //如果有key mapper 映射
    if ([cls respondsToSelector:@selector(modelCustomPropertyMapper)]) {
        NSDictionary *customMapper = [(id <YYModel>)cls modelCustomPropertyMapper];
        [customMapper enumerateKeysAndObjectsUsingBlock:^(NSString *propertyName, NSString *mappedToKey, BOOL *stop) {
            _YYModelPropertyMeta *propertyMeta = allPropertyMetas[propertyName];        //找到映射值的_YYModelPropertyMeta
            if (!propertyMeta) return;                              //没有直接返回
            [allPropertyMetas removeObjectForKey:propertyName];     //有映射所以从原来的列表删除
            
            if ([mappedToKey isKindOfClass:[NSString class]]) {             //如果是NSString映射
                if (mappedToKey.length == 0) return;
                
                propertyMeta->_mappedToKey = mappedToKey;               //设置mapper key
                NSArray *keyPath = [mappedToKey componentsSeparatedByString:@"."];  //如果是包含"."代表key的路径映射
                for (NSString *onePath in keyPath) {
                    if (onePath.length == 0) {
                        NSMutableArray *tmp = keyPath.mutableCopy;
                        [tmp removeObject:@""];
                        keyPath = tmp;
                        break;
                    }
                }
                if (keyPath.count > 1) {                            //>1说明有路径映射
                    propertyMeta->_mappedToKeyPath = keyPath;       //设置_mappedToKeyPath
                    [keyPathPropertyMetas addObject:propertyMeta];  //添加路径映射对象
                }
                propertyMeta->_next = mapper[mappedToKey] ?: nil;   //如果包含上一个同样key值的_YYModelPropertyMeta对象，则设置next指针
                mapper[mappedToKey] = propertyMeta;
                
            } else if ([mappedToKey isKindOfClass:[NSArray class]]) {       //如果是nsarray映射
                
                NSMutableArray *mappedToKeyArray = [NSMutableArray new];
                for (NSString *oneKey in ((NSArray *)mappedToKey)) {        //多一级nsarray的遍历，内容与nsstring相同
                    if (![oneKey isKindOfClass:[NSString class]]) continue;
                    if (oneKey.length == 0) continue;
                    
                    NSArray *keyPath = [oneKey componentsSeparatedByString:@"."];
                    if (keyPath.count > 1) {
                        [mappedToKeyArray addObject:keyPath];
                    } else {
                        [mappedToKeyArray addObject:oneKey];
                    }
                    
                    if (!propertyMeta->_mappedToKey) {
                        propertyMeta->_mappedToKey = oneKey;
                        propertyMeta->_mappedToKeyPath = keyPath.count > 1 ? keyPath : nil;
                    }
                }
                if (!propertyMeta->_mappedToKey) return;
                
                propertyMeta->_mappedToKeyArray = mappedToKeyArray;     //多级的映射值会存到_mappedToKeyArray
                [multiKeysPropertyMetas addObject:propertyMeta];
                
                propertyMeta->_next = mapper[mappedToKey] ?: nil;   //同样，如果包含上一个同样key值的_YYModelPropertyMeta对象，则设置next指针
                mapper[mappedToKey] = propertyMeta;
            }
        }];
    }
    
    //映射完后，遍历所有的allPropertyMetas，设置mapper和next指针
    [allPropertyMetas enumerateKeysAndObjectsUsingBlock:^(NSString *name, _YYModelPropertyMeta *propertyMeta, BOOL *stop) {
        propertyMeta->_mappedToKey = name;
        propertyMeta->_next = mapper[name] ?: nil;
        mapper[name] = propertyMeta;
    }];
    
    //如果有映射值，则缓存
    if (mapper.count) _mapper = mapper;
    //如果路径映射值，则缓存
    if (keyPathPropertyMetas) _keyPathPropertyMetas = keyPathPropertyMetas;
    //如果有多映射值，则缓存
    if (multiKeysPropertyMetas) _multiKeysPropertyMetas = multiKeysPropertyMetas;
    
    _classInfo = classInfo;         //设置classinfo
    _keyMappedCount = _allPropertyMetas.count;          //设置property数量
    _nsType = YYClassGetNSType(cls);            //获得本类的oc foundation类型
    _hasCustomWillTransformFromDictionary = ([cls instancesRespondToSelector:@selector(modelCustomWillTransformFromDictionary:)]);
    _hasCustomTransformFromDictionary = ([cls instancesRespondToSelector:@selector(modelCustomTransformFromDictionary:)]);
    _hasCustomTransformToDictionary = ([cls instancesRespondToSelector:@selector(modelCustomTransformToDictionary:)]);
    _hasCustomClassFromDictionary = ([cls respondsToSelector:@selector(modelCustomClassForDictionary:)]);
    
    return self;
}

/// Returns the cached model class meta
//返回缓存的model class meta
+ (instancetype)metaWithClass:(Class)cls {
    if (!cls) return nil;
    static CFMutableDictionaryRef cache;        //class的_YYModelMeta缓存
    static dispatch_once_t onceToken;
    static dispatch_semaphore_t lock;
    dispatch_once(&onceToken, ^{
        cache = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        lock = dispatch_semaphore_create(1);
    });
    dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
    _YYModelMeta *meta = CFDictionaryGetValue(cache, (__bridge const void *)(cls));
    dispatch_semaphore_signal(lock);
    if (!meta || meta->_classInfo.needUpdate) {             //利用
        meta = [[_YYModelMeta alloc] initWithClass:cls];    //重新构造 _YYModelMeta缓存
        if (meta) {                                         //设置缓存
            dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
            CFDictionarySetValue(cache, (__bridge const void *)(cls), (__bridge const void *)(meta));
            dispatch_semaphore_signal(lock);
        }
    }
    return meta;
}
```
实现处理了很多key mapper的映射问题，但本身逻辑并不复杂。

##解析逻辑

```
//id json对象转化为 dictioanry的方法
+ (NSDictionary *)_yy_dictionaryWithJSON:(id)json {
    if (!json || json == (id)kCFNull) return nil;
    NSDictionary *dic = nil;
    NSData *jsonData = nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        dic = json;
    } else if ([json isKindOfClass:[NSString class]]) {
        jsonData = [(NSString *)json dataUsingEncoding : NSUTF8StringEncoding];
    } else if ([json isKindOfClass:[NSData class]]) {
        jsonData = json;
    }
    if (jsonData) {
        dic = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:NULL];
        if (![dic isKindOfClass:[NSDictionary class]]) dic = nil;
    }
    return dic;
}

//先转化json对象到dictionary，再调用yy_modelWithDictionary
+ (instancetype)yy_modelWithJSON:(id)json {
    NSDictionary *dic = [self _yy_dictionaryWithJSON:json];
    return [self yy_modelWithDictionary:dic];
}

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


//附值函数
- (BOOL)yy_modelSetWithDictionary:(NSDictionary *)dic {
    if (!dic || dic == (id)kCFNull) return NO;
    if (![dic isKindOfClass:[NSDictionary class]]) return NO;
    

    _YYModelMeta *modelMeta = [_YYModelMeta metaWithClass:object_getClass(self)];
    if (modelMeta->_keyMappedCount == 0) return NO;
    
    //本地dictionary值替换
    if (modelMeta->_hasCustomWillTransformFromDictionary) {
        dic = [((id<YYModel>)self) modelCustomWillTransformFromDictionary:dic];
        if (![dic isKindOfClass:[NSDictionary class]]) return NO;
    }
    
    ModelSetContext context = {0};
    context.modelMeta = (__bridge void *)(modelMeta);
    context.model = (__bridge void *)(self);
    context.dictionary = (__bridge void *)(dic);
    
    
    //遍历dictioanry并附值
    if (modelMeta->_keyMappedCount >= CFDictionaryGetCount((CFDictionaryRef)dic)) {
        CFDictionaryApplyFunction((CFDictionaryRef)dic, ModelSetWithDictionaryFunction, &context);
        if (modelMeta->_keyPathPropertyMetas) {
            CFArrayApplyFunction((CFArrayRef)modelMeta->_keyPathPropertyMetas,
                                 CFRangeMake(0, CFArrayGetCount((CFArrayRef)modelMeta->_keyPathPropertyMetas)),
                                 ModelSetWithPropertyMetaArrayFunction,
                                 &context);
        }
        if (modelMeta->_multiKeysPropertyMetas) {
            CFArrayApplyFunction((CFArrayRef)modelMeta->_multiKeysPropertyMetas,
                                 CFRangeMake(0, CFArrayGetCount((CFArrayRef)modelMeta->_multiKeysPropertyMetas)),
                                 ModelSetWithPropertyMetaArrayFunction,
                                 &context);
        }
    } else {
        CFArrayApplyFunction((CFArrayRef)modelMeta->_allPropertyMetas,
                             CFRangeMake(0, modelMeta->_keyMappedCount),
                             ModelSetWithPropertyMetaArrayFunction,
                             &context);
    }
    
    //本地property验证
    if (modelMeta->_hasCustomTransformFromDictionary) {
        return [((id<YYModel>)self) modelCustomTransformFromDictionary:dic];
    }
    return YES;
}
```
附值这块，就只取``ModelSetWithDictionaryFunction``设置
```
static void ModelSetWithDictionaryFunction(const void *_key, const void *_value, void *_context) {
    ModelSetContext *context = _context;
    __unsafe_unretained _YYModelMeta *meta = (__bridge _YYModelMeta *)(context->modelMeta); //取_YYModelMeta
    __unsafe_unretained _YYModelPropertyMeta *propertyMeta = [meta->_mapper objectForKey:(__bridge id)(_key)];  //取_YYModelPropertyMeta
    __unsafe_unretained id model = (__bridge id)(context->model);
    while (propertyMeta) {          //循环遍历propertyMeta
        if (propertyMeta->_setter) {
            ModelSetValueForProperty(model, (__bridge __unsafe_unretained id)_value, propertyMeta); //设置值
        }
        propertyMeta = propertyMeta->_next;
    };
}
```
而``ModelSetValueForProperty``的设置函数，就是根据不同类型，去调用msgSend调用相应的meta->_setter方法，进行附值，代码较长，这里也不贴了。

**至此，整个YYModel的解析就完成了。**

##总结
YYModel在整体的解析过程中，分三步：
1. 先将Class的Method，Property，Ivar分别解析缓存，构成Class的缓存
2. 构建``_YYModelPropertyMeta``缓存Property结构体，再``_YYModelMeta``缓存``_YYModelPropertyMeta``结构。
3.根据解析出来的``_YYModelPropertyMeta``与相应的YYEncodingType等属性，进行相应值的设置

**JSONModel与YYModel对比**

对比| JSONModel | YYModel
----|------|----
解析方式 | 只解析property attribute encode string | 解析Class Method,Property,Ivar缓存，再构造``_YYModelPropertyMeta``与``_YYModelMeta``
附值方式 | KVC | 先解析出property的类型，使用msgSend调用meta->setter方法分类型附值
缓存方式 | AssociatedObject | CFMutableDictionaryRef
包含类型方式 | 定义同名protocol，声明protocol | 不仅可以声明protocol定义，还可以实现``modelContainerPropertyGenericClass``接口
映射值为路径解析 | 无 | 有
model类型转换| 无 |  有
懒加载  |有 | 无
是否可以缺省  | 通过protocol optional | 黑名单\白名单



##参考资料
[CSDN地址](http://blog.csdn.net/game3108/article/details/52416868)
1.[JSONModel源代码解析](http://www.jianshu.com/p/64ce3927eb62)
2.[郑钦洪_：YYModel 源码历险记](http://www.jianshu.com/users/aa41dad549af/latest_articles)
