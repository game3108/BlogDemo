##前言
本文的demo更新在[github](https://github.com/game3108/BlogDemo/tree/master/JSONModel1.20)上。

客户端请求服务器，经常使用的时JSON方式传递数据。一些第三方开源库帮助我们将JSON转化为Model对象，其中比较有名的有：YYModel,JSONModel,Mantle,MJExtension等。今天主要讲一下[JSONModel](https://github.com/jsonmodel/jsonmodel)和相应的源代码。 (以下代码都是建立在release 1.20版本的基础上。） 

##常规解析
解析JSON数据的最基础的方法是使用``NSJSONSerialization``，比如下面的一个最简单的网络请求
```
    NSData* ghData = [NSData dataWithContentsOfURL: [NSURL URLWithString:@"http://xxxx"]];
    NSDictionary* json = nil;
    if (ghData) {
        json = [NSJSONSerialization
                JSONObjectWithData:ghData
                options:kNilOptions
                error:nil];
    }
```
最后通过``NSJSONSerialization``去将数据解析成了一个dictionary


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
然后进行设置
```
    TestObject *testObject = [[TestObject alloc]init];
    testObject.name     = json[@"name"];
    testObject.number   = json[@"number"];
    testObject.age      = [json[@"age"] integerValue];
```
**这么做虽然正确，但如果所有数据都这么处理，会有一些麻烦：**
* 1.你需要很小心的处理model property类型与dictionary中的数据对应类型
比如有一个``NSURL *url``的值，你需要在``json[@"url"]``这个``NSString *``类型进行一次转化成``NSURL *``，但编译器并不会提示你这样的错误，很多时候你如果忘记了就会犯错
* 2.如果你的赋值地点过于的多，你每一次修改model的property，就需要把所有赋值地方进行一次整体的更改，会比较麻烦
* 3.很多时候json数据如果有遗漏或者变化，比较难发现
比如对应上面的age这个值，json数据中如果不包含age，通过``[json[@"age"] integerValue]``的写法，就会把值设置为0，这在很多时候容易被忽略，以为json数据中包含这样的值。

##JSONModel解析
我们只需要建立这样一个JSONModel对象
```
#import <JSONModel/JSONModel.h>

@interface TestJSONModel : JSONModel
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *number;
@property (nonatomic, assign) NSInteger age;
@end
```
并调用
```
    JSONModelError *error = nil;
    TestJSONModel *testJSONModel = [[TestJSONModel alloc]initWithDictionary:json error:&error];
```
就可以将model的值进行自行设置，相对于常规方法，大大简化了代码量和难度。

##JSONModel源代码分析

####目录结构
我们先来看一下JSONModel的目录结构

![JSONModel目录](http://upload-images.jianshu.io/upload_images/1829891-b6e421ecb099c481.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
可以看到，项目中其实还包括networking,transformer等有关的类，但我们这次解析主要聚焦在JSONModel.m上，也不是逐行解析，主要讲正题的思路和方法。
####核心代码
初始化代码可以说是核心代码，代码如下：
```
-(id)initWithDictionary:(NSDictionary*)dict error:(NSError**)err
{
    //check for nil input
    //1.为空判断
    if (!dict) {
        if (err) *err = [JSONModelError errorInputIsNil];
        return nil;
    }

    //invalid input, just create empty instance
    //2.类型判断
    if (![dict isKindOfClass:[NSDictionary class]]) {
        if (err) *err = [JSONModelError errorInvalidDataWithMessage:@"Attempt to initialize JSONModel object using initWithDictionary:error: but the dictionary parameter was not an 'NSDictionary'."];
        return nil;
    }

    //create a class instance
    //3.核心，初始化映射property
    self = [self init];
    if (!self) {
        
        //super init didn't succeed
        if (err) *err = [JSONModelError errorModelIsInvalid];
        return nil;
    }
    
    //check incoming data structure
    //4.检查映射结构是否能够从dictionary中找到相应的数据
    if (![self __doesDictionary:dict matchModelWithKeyMapper:self.__keyMapper error:err]) {
        return nil;
    }
    
    //import the data from a dictionary
    //5.进行数据赋值
    if (![self __importDictionary:dict withKeyMapper:self.__keyMapper validation:YES error:err]) {
        return nil;
    }
    
    //run any custom model validation
    //6.本地数据检查
    if (![self validate:err]) {
        return nil;
    }
    
    //model is valid! yay!
    return self;
}
```
**主要分为以下6块：**
* 1.空值判断
* 2.输入类型dictionary判断
* **3.初始化：解析model对象，并且映射property**
* **4.查值：检查model property名与数据来源json字典中数据名，判断是否所有property都有值**
* **5.赋值：进行赋值**
* 6.本地数据正确性检查
**以下我将主要解析3，4，5这三部分的主代码**

####初始化
以下是初始化的调用函数
```
-(void)__setup__
{
    //if first instance of this model, generate the property list
    //使用AssociateObject进行映射property的缓存，判断是否映射过
    if (!objc_getAssociatedObject(self.class, &kClassPropertiesKey)) {
        [self __inspectProperties];
    }

    //if there's a custom key mapper, store it in the associated object
    //获取对象的keyMapper影射，同样使用AssociateObject进行映射property的缓存
    id mapper = [[self class] keyMapper];
    if ( mapper && !objc_getAssociatedObject(self.class, &kMapperObjectKey) ) {
        objc_setAssociatedObject(
                                 self.class,
                                 &kMapperObjectKey,
                                 mapper,
                                 OBJC_ASSOCIATION_RETAIN // This is atomic
                                 );
    }
}

-(id)init
{
    self = [super init];
    if (self) {
        //do initial class setup
        [self __setup__];
    }
    return self;
}
```
这段代码使用AssociateObject的缓存判断kClassPropertiesKey就知道该model对象是否有进行过解析property，没有的话进行解析，同时取出model的key mapper，也同样进行缓存。
key mapper主要是用来针对某些json字段名和model数据名不一致的情况。
比如``"com.app.test.name":"xxx"``,``"test_name":"xxx"``这样的情况，可能对应的model数据字段名为name，那如何讲着两个值进行映射，就通过key mapper来完成。
主体的解析代码如下：
```
//inspects the class, get's a list of the class properties
//解析property结构主体
-(void)__inspectProperties
{
    //JMLog(@"Inspect class: %@", [self class]);
    
    NSMutableDictionary* propertyIndex = [NSMutableDictionary dictionary];
    
    //temp variables for the loops
    Class class = [self class];
    NSScanner* scanner = nil;
    NSString* propertyType = nil;
    
    // inspect inherited properties up to the JSONModel class
    while (class != [JSONModel class]) {
        //JMLog(@"inspecting: %@", NSStringFromClass(class));
        
        unsigned int propertyCount;
        //赋值所有property列表，进行循环判断
        objc_property_t *properties = class_copyPropertyList(class, &propertyCount);
        
        //loop over the class properties
        for (unsigned int i = 0; i < propertyCount; i++) {
            
            //JSONModelClassProperty包涵解析与赋值时候的所有判断
            JSONModelClassProperty* p = [[JSONModelClassProperty alloc] init];

            //get property name
            objc_property_t property = properties[i];
            const char *propertyName = property_getName(property);
            p.name = @(propertyName);
            
            //JMLog(@"property: %@", p.name);
            
            //get property attributes
            //核心，通过property_getAttributes获取property的encode string，解析encode string可以解析出具体property的类型
            const char *attrs = property_getAttributes(property);
            NSString* propertyAttributes = @(attrs);
            NSArray* attributeItems = [propertyAttributes componentsSeparatedByString:@","];
            
            //ignore read-only properties
            if ([attributeItems containsObject:@"R"]) {
                continue; //to next property
            }
            
            //check for 64b BOOLs
            if ([propertyAttributes hasPrefix:@"Tc,"]) {
                //mask BOOLs as structs so they can have custom converters
                p.structName = @"BOOL";
            }
            
            scanner = [NSScanner scannerWithString: propertyAttributes];
            
            //JMLog(@"attr: %@", [NSString stringWithCString:attrs encoding:NSUTF8StringEncoding]);
            [scanner scanUpToString:@"T" intoString: nil];
            [scanner scanString:@"T" intoString:nil];
            
            //check if the property is an instance of a class
            //解析一个类，包括自己创建的类和oc自带类NSString等
            if ([scanner scanString:@"@\"" intoString: &propertyType]) {
                
                [scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\"<"]
                                        intoString:&propertyType];
                
                //JMLog(@"type: %@", propertyClassName);
                p.type = NSClassFromString(propertyType);
                p.isMutable = ([propertyType rangeOfString:@"Mutable"].location != NSNotFound);
                p.isStandardJSONType = [allowedJSONTypes containsObject:p.type];
                
                //read through the property protocols
                //解析protocol的string
                while ([scanner scanString:@"<" intoString:NULL]) {
                    
                    NSString* protocolName = nil;
                    
                    [scanner scanUpToString:@">" intoString: &protocolName];
                    
                    if ([protocolName isEqualToString:@"Optional"]) {
                        p.isOptional = YES;
                    } else if([protocolName isEqualToString:@"Index"]) {
                        p.isIndex = YES;
                        objc_setAssociatedObject(
                                                 self.class,
                                                 &kIndexPropertyNameKey,
                                                 p.name,
                                                 OBJC_ASSOCIATION_RETAIN // This is atomic
                                                 );
                    } else if([protocolName isEqualToString:@"ConvertOnDemand"]) {
                        p.convertsOnDemand = YES;
                    } else if([protocolName isEqualToString:@"Ignore"]) {
                        p = nil;
                    } else {
                        p.protocol = protocolName;
                    }
                    
                    [scanner scanString:@">" intoString:NULL];
                }

            }
            //check if the property is a structure
            //解析structure
            else if ([scanner scanString:@"{" intoString: &propertyType]) {
                [scanner scanCharactersFromSet:[NSCharacterSet alphanumericCharacterSet]
                                    intoString:&propertyType];
                
                p.isStandardJSONType = NO;
                p.structName = propertyType;

            }
            //the property must be a primitive
            //其他类型都是基本类型，比如int float等
            else {

                //the property contains a primitive data type
                [scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@","]
                                        intoString:&propertyType];
                
                //get the full name of the primitive type
                propertyType = valueTransformer.primitivesNames[propertyType];
                
                if (![allowedPrimitiveTypes containsObject:propertyType]) {
                    
                    //type not allowed - programmer mistaken -> exception
                    @throw [NSException exceptionWithName:@"JSONModelProperty type not allowed"
                                                   reason:[NSString stringWithFormat:@"Property type of %@.%@ is not supported by JSONModel.", self.class, p.name]
                                                 userInfo:nil];
                }

            }

            NSString *nsPropertyName = @(propertyName);
            //本地覆盖方法去判断是不是Optional
            if([[self class] propertyIsOptional:nsPropertyName]){
                p.isOptional = YES;
            }
            
            if([[self class] propertyIsIgnored:nsPropertyName]){
                p = nil;
            }
            //本地覆盖方法去判断是不是有protocol
            NSString* customProtocol = [[self class] protocolForArrayProperty:nsPropertyName];
            if (customProtocol) {
                p.protocol = customProtocol;
            }
            
            //few cases where JSONModel will ignore properties automatically
            if ([propertyType isEqualToString:@"Block"]) {
                p = nil;
            }
            
            //add the property object to the temp index
            //通过kvc去设置相应的值
            if (p && ![propertyIndex objectForKey:p.name]) {
                [propertyIndex setValue:p forKey:p.name];
            }
        }
        
        free(properties);
        
        //ascend to the super of the class
        //(will do that until it reaches the root class - JSONModel)
        class = [class superclass];
    }
    
    //finally store the property index in the static property index
    //使用AssociateObject进行缓存
    objc_setAssociatedObject(
                             self.class,
                             &kClassPropertiesKey,
                             [propertyIndex copy],
                             OBJC_ASSOCIATION_RETAIN // This is atomic
                             );
}
```
看上去比较长，其实我们只需要明白以下几个概念就可以比较容易理解：
* 1.runtime
> The Objective-C language defers as many decisions as it can from compile time and link time to runtime. Whenever possible, it does things dynamically. This means that the language requires not just a compiler, but also a runtime system to execute the compiled code. The runtime system acts as a kind of operating system for the Objective-C language; it’s what makes the language work.

* 2.``objc_property_t *properties = class_copyPropertyList(Class cls, unsigned int *count);``
> You can use the functions class_copyPropertyList and protocol_copyPropertyList to retrieve an array of the properties associated with a class (including loaded categories) and a protocol respectively

* 3.``const char *property_getAttributes(objc_property_t property)``
> You can use the property_getAttributes function to discover the name and the @encode type string of a property. 

以上几个概念都可以从[Objective-C Runtime Programming Guide](https://developer.apple.com/library/prerelease/content/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtPropertyIntrospection.html#//apple_ref/doc/uid/TP40008048-CH101-SW1)上找到更加具体的解释，尤其是对应encode string每一个字符的含义。

**简单来说就是：
使用runtime的``class_copyPropertyList``方法去获得所有model对象的property列表，再使用
``property_getAttributes``获得property的encode string，通过解析encode string去获得property对象的正确含义。
在解析的过程中，使用NSScanner去扫描encode string,并使用JSONModelClassProperty的结构体去保存相关信息。
其中对于protocol的使用较为特殊，在这里的protocol并非我们平常当作接口抽象的作用，而是单纯的为了让encode string中增加相应的字段，可以在解析与赋值的时候给予特定的含义。
**

举个解析的例子：
这个是JSONModel自带demo中的一个结构体，可以看到他的相关property
```
@protocol LoanModel @end

@interface LoanModel : JSONModel

@property (strong, nonatomic) NSString* name;
@property (strong, nonatomic) NSString* status;
@property (strong, nonatomic) NSString* use;

@property (strong, nonatomic) LocationModel* location;

@end
```
当解析到最后一行的property``@property (strong, nonatomic) LocationModel* location;
``我设置了一个断点，查看结果

![propertyAttributes](http://upload-images.jianshu.io/upload_images/1829891-bd480c217a764c85.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

![JSONModelClassProperty](http://upload-images.jianshu.io/upload_images/1829891-45c6d54439eeaf6e.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
可以看到，对于location来说，它的类为\"与\"中的LocationModel，并且它还是&(retain),N(nonatomic)的。
而protocol则会在encode string的<>中，JSONModel通过这样的方式，可以让我们快速设置一个property的一些属性，比如

```
@interface KivaFeed : JSONModel

@property (strong, nonatomic) NSArray<LoanModel, ConvertOnDemand>* loans;

@end
```
中的loans，它不仅代表着loans这个array中包含的元素为LoanModel,而且它还有JSONModel特别设置的几个特性ConvertOnDemand（懒加载），这些特性包括
* 可选择：isOptional
* 懒加载：convertsOnDemand
* 索引key：isIndex

通过protocol就可以达到标明array与dictionary中对应元素的类型，和一些对于property解析的时候有用的表示。

####查值
```
-(BOOL)__doesDictionary:(NSDictionary*)dict matchModelWithKeyMapper:(JSONKeyMapper*)keyMapper error:(NSError**)err
{
    //check if all required properties are present
    //将输入dictionary的keys装入set，将映射的property的keys装入set
    NSArray* incomingKeysArray = [dict allKeys];
    NSMutableSet* requiredProperties = [self __requiredPropertyNames].mutableCopy;
    NSSet* incomingKeys = [NSSet setWithArray: incomingKeysArray];
    
    //transform the key names, if necessary
    //如果存在keyMapper映射，在对应set中找到相应key进行替换
    if (keyMapper || globalKeyMapper) {
        
        NSMutableSet* transformedIncomingKeys = [NSMutableSet setWithCapacity: requiredProperties.count];
        NSString* transformedName = nil;
        
        //loop over the required properties list
        for (JSONModelClassProperty* property in [self __properties__]) {
            
            transformedName = (keyMapper||globalKeyMapper) ? [self __mapString:property.name withKeyMapper:keyMapper importing:YES] : property.name;
            
            //check if exists and if so, add to incoming keys
            id value;
            @try {
                value = [dict valueForKeyPath:transformedName];
            }
            @catch (NSException *exception) {
                value = dict[transformedName];
            }
            
            if (value) {
                [transformedIncomingKeys addObject: property.name];
            }
        }
        
        //overwrite the raw incoming list with the mapped key names
        incomingKeys = transformedIncomingKeys;
    }
    
    //check for missing input keys
    //判断property解析的set是不是dictionary所有key的子set来判断是否全部包含
    if (![requiredProperties isSubsetOfSet:incomingKeys]) {
        
        //get a list of the missing properties
        [requiredProperties minusSet:incomingKeys];
        
        //not all required properties are in - invalid input
        JMLog(@"Incoming data was invalid [%@ initWithDictionary:]. Keys missing: %@", self.class, requiredProperties);
        
        if (err) *err = [JSONModelError errorInvalidDataWithMissingKeys:requiredProperties];
        return NO;
    }
    
    //not needed anymore
    incomingKeys= nil;
    requiredProperties= nil;
    
    return YES;
}
```
**查值的作用主要就是为了能够检查是否model的所有property是否都能够被赋值，如果不能则说明缺少值则抛出错误。这边主要的亮点就是使用了NSSet，将dictionary的所有key存入一个set：incomingKeys，并且将key mapper映射名进行替换。将刚解析出来的model所有property的name也存入一个set：requiredProperties，判断两者是不是包含关系。**

####赋值

```
-(BOOL)__importDictionary:(NSDictionary*)dict withKeyMapper:(JSONKeyMapper*)keyMapper validation:(BOOL)validation error:(NSError**)err
{
    //loop over the incoming keys and set self's properties
    //循环遍历映射出来的JSONModelClassProperty结构体
    for (JSONModelClassProperty* property in [self __properties__]) {
        
        //convert key name ot model keys, if a mapper is provided
        //keyMapper映射，获取镇真正的值
        NSString* jsonKeyPath = (keyMapper||globalKeyMapper) ? [self __mapString:property.name withKeyMapper:keyMapper importing:YES] : property.name;
        //JMLog(@"keyPath: %@", jsonKeyPath);
        
        //general check for data type compliance
        id jsonValue;
        @try {
            jsonValue = [dict valueForKeyPath: jsonKeyPath];
        }
        @catch (NSException *exception) {
            jsonValue = dict[jsonKeyPath];
        }
        
        //check for Optional properties
        if (isNull(jsonValue)) {
            //skip this property, continue with next property
            if (property.isOptional || !validation) continue;
            
            if (err) {
                //null value for required property
                NSString* msg = [NSString stringWithFormat:@"Value of required model key %@ is null", property.name];
                JSONModelError* dataErr = [JSONModelError errorInvalidDataWithMessage:msg];
                *err = [dataErr errorByPrependingKeyPathComponent:property.name];
            }
            return NO;
        }
        
        Class jsonValueClass = [jsonValue class];
        BOOL isValueOfAllowedType = NO;
        
        //判断数据输入类型是不是允许的json类型
        for (Class allowedType in allowedJSONTypes) {
            if ( [jsonValueClass isSubclassOfClass: allowedType] ) {
                isValueOfAllowedType = YES;
                break;
            }
        }
        
        if (isValueOfAllowedType==NO) {
            //type not allowed
            JMLog(@"Type %@ is not allowed in JSON.", NSStringFromClass(jsonValueClass));
            
            if (err) {
				NSString* msg = [NSString stringWithFormat:@"Type %@ is not allowed in JSON.", NSStringFromClass(jsonValueClass)];
				JSONModelError* dataErr = [JSONModelError errorInvalidDataWithMessage:msg];
				*err = [dataErr errorByPrependingKeyPathComponent:property.name];
			}
            return NO;
        }
        
        //check if there's matching property in the model
        if (property) {
            
            // check for custom setter, than the model doesn't need to do any guessing
            // how to read the property's value from JSON
            // 使用对象相应的setter方法进行set
            if ([self __customSetValue:jsonValue forProperty:property]) {
                //skip to next JSON key
                continue;
            };
            
            // 0) handle primitives
            // 代表基础类型，比如int float等，直接使用kvc赋值
            if (property.type == nil && property.structName==nil) {
                
                //generic setter
                if (jsonValue != [self valueForKey:property.name]) {
                    [self setValue:jsonValue forKey: property.name];
                }
                
                //skip directly to the next key
                continue;
            }
            
            // 0.5) handle nils
            if (isNull(jsonValue)) {
                if ([self valueForKey:property.name] != nil) {
                    [self setValue:nil forKey: property.name];
                }
                continue;
            }
            
            
            // 1) check if property is itself a JSONModel
            // 判断子结构是否是一个JSONModel结构，进行递归遍历，先将子结构遍历完并赋值完成
            if ([self __isJSONModelSubClass:property.type]) {
                
                //initialize the property's model, store it
                JSONModelError* initErr = nil;
                id value = [[property.type alloc] initWithDictionary: jsonValue error:&initErr];
                
                if (!value) {
                    //skip this property, continue with next property
                    if (property.isOptional || !validation) continue;
                    
					// Propagate the error, including the property name as the key-path component
					if((err != nil) && (initErr != nil))
					{
						*err = [initErr errorByPrependingKeyPathComponent:property.name];
					}
                    return NO;
                }
                if (![value isEqual:[self valueForKey:property.name]]) {
                    [self setValue:value forKey: property.name];
                }
                
                //for clarity, does the same without continue
                continue;
                
            } else {
                
                // 2) check if there's a protocol to the property
                //  ) might or not be the case there's a built in transform for it
                // 是否包含protocol的字段，该字段主要用来表明array或者dictionary中的对象类型
                if (property.protocol) {
                    
                    //JMLog(@"proto: %@", p.protocol);
                    //循环遍历子内容，将对应的类型赋给相应的array或者dictionary
                    jsonValue = [self __transform:jsonValue forProperty:property error:err];
                    if (!jsonValue) {
                        if ((err != nil) && (*err == nil)) {
							NSString* msg = [NSString stringWithFormat:@"Failed to transform value, but no error was set during transformation. (%@)", property];
							JSONModelError* dataErr = [JSONModelError errorInvalidDataWithMessage:msg];
							*err = [dataErr errorByPrependingKeyPathComponent:property.name];
						}
                        return NO;
                    }
                }
                
                // 3.1) handle matching standard JSON types
                // 判断标准的json类型，比如nsstring等
                if (property.isStandardJSONType && [jsonValue isKindOfClass: property.type]) {
                    
                    //mutable properties
                    if (property.isMutable) {
                        jsonValue = [jsonValue mutableCopy];
                    }
                    
                    //set the property value
                    if (![jsonValue isEqual:[self valueForKey:property.name]]) {
                        [self setValue:jsonValue forKey: property.name];
                    }
                    continue;
                }
                
                // 3.3) handle values to transform
                // 其他处理情况，主要是一些类型转换的情况，比如nsstring转换为nsurl等
                if (
                    (![jsonValue isKindOfClass:property.type] && !isNull(jsonValue))
                    ||
                    //the property is mutable
                    property.isMutable
                    ||
                    //custom struct property
                    property.structName
                    ) {
                    
                    // searched around the web how to do this better
                    // but did not find any solution, maybe that's the best idea? (hardly)
                    // 获取真实的json数据类型
                    Class sourceClass = [JSONValueTransformer classByResolvingClusterClasses:[jsonValue class]];
                    
                    //JMLog(@"to type: [%@] from type: [%@] transformer: [%@]", p.type, sourceClass, selectorName);
                    
                    //build a method selector for the property and json object classes
                    // 通过property类型和json数据类型进行转换的判断
                    NSString* selectorName = [NSString stringWithFormat:@"%@From%@:",
                                              (property.structName? property.structName : property.type), //target name
                                              sourceClass]; //source name
                    SEL selector = NSSelectorFromString(selectorName);
                    
                    //check for custom transformer
                    //是否有本地转换的方法
                    BOOL foundCustomTransformer = NO;
                    if ([valueTransformer respondsToSelector:selector]) {
                        foundCustomTransformer = YES;
                    } else {
                        //try for hidden custom transformer
                        selectorName = [NSString stringWithFormat:@"__%@",selectorName];
                        selector = NSSelectorFromString(selectorName);
                        if ([valueTransformer respondsToSelector:selector]) {
                            foundCustomTransformer = YES;
                        }
                    }
                    
                    //check if there's a transformer with that name
                    if (foundCustomTransformer) {
                        
                        //it's OK, believe me...
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        //transform the value
                        // 通过 JSONValueTransformer 进行类型转换
                        jsonValue = [valueTransformer performSelector:selector withObject:jsonValue];
#pragma clang diagnostic pop
                        
                        if (![jsonValue isEqual:[self valueForKey:property.name]]) {
                            [self setValue:jsonValue forKey: property.name];
                        }
                        
                    } else {
                        
                        // it's not a JSON data type, and there's no transformer for it
                        // if property type is not supported - that's a programmer mistake -> exception
                        @throw [NSException exceptionWithName:@"Type not allowed"
                                                       reason:[NSString stringWithFormat:@"%@ type not supported for %@.%@", property.type, [self class], property.name]
                                                     userInfo:nil];
                        return NO;
                    }
                    
                } else {
                    // 3.4) handle "all other" cases (if any)
                    if (![jsonValue isEqual:[self valueForKey:property.name]]) {
                        [self setValue:jsonValue forKey: property.name];
                    }
                }
            }
        }
    }
    
    return YES;
}
```

**代码看上去很长，其实也比较好理解：
循环遍历model的每一个解析出来的property结构，首先从dictioanry拿出真正对应property的value，进行value一系列的值判断。value可用的情况下，就开始进行赋值，有setter方法的通过setter方法赋值，基础类型int，float等直接赋值，如果property又是一个JSONModel，就递归先将子Model进行整体解析。如果包含protocol字段，则表明内部是一个array或者dictionary，并包含这个protocol字段的对象解析。对于其他情况，应该是一种类型的转换，通过获取值类型和property类型，调用相应的转换方法进行赋值。
其中值得一提的就是JSONValueTransformer的类型转化，它解决了我们之前所说的麻烦1，将数据类型得以正确转换。**

##总结
至此，JSONModel主代码的作为，基本解释的差不多了。
总的来说JSONModel的源代码有以下优点：
* Runtime动态解析model数据类型
* AssociatedObject缓存
* keyMapper映射
* NSScanner扫描String
* JSONValueTransformer类型转换
* KVC附值
* 。。。

如果以上有任何我说错的地方，或者可以解释的更好的地方，也欢迎给我留言，我也会修改我的错误。Thanks。
(PS:和同事聊起这方面的话题，他表示YYModel的效率会比JSONModel高好几倍，下一份就看一下YYModel的源代码。)

##参考资料
[本文csdn地址](http://blog.csdn.net/game3108/article/details/52043661)
1.[Objective-C Runtime Programming Guide](https://developer.apple.com/library/prerelease/content/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtPropertyIntrospection.html#//apple_ref/doc/uid/TP40008048-CH101-SW1)
2.[JSONModel源码解析](http://satanwoo.github.io/2015/09/17/code-of-JSONModel/?utm_source=tuicool&utm_medium=referral)
