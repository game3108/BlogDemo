## 前言
本文的RSA例子代码更新在我的[github](https://github.com/game3108/BlogDemo/tree/master/RSA-algorithm)上。

RSA算法是最重要算法之一，它是计算机通信安全的基石，保证了加密数据不会被破解。**本文主要参考了参考资料中的文章，介绍一下RSA算法的内容，自己写一遍，算是学习了。**

## 历史
#### 1.对称加密算法
在1976年以前，所有的加密方法都是同一种模式["对称加密算法"](http://zh.wikipedia.org/zh-cn/%E5%AF%B9%E7%AD%89%E5%8A%A0%E5%AF%86)（Symmetric-key algorithm）:

* （1）甲方选择某一种加密规则，对信息进行加密；
* （2）乙方使用同一种规则，对信息进行解密。

这种加密模式有一个最大弱点：甲方必须把加密规则告诉乙方，否则无法解密。
#### 2.非对称加密算法
1976年，两位美国计算机学家Whitfield Diffie 和 Martin Hellman，提出了一种崭新构思，可以在不直接传递密钥的情况下，完成解密。这被称为["Diffie-Hellman密钥交换算法"](http://en.wikipedia.org/wiki/Diffie%E2%80%93Hellman_key_exchange)。

* （1）甲要传密信给乙，乙先根据某种算法得出本次与甲通信的公钥与私钥
* （2）乙将公钥传给甲（公钥可以让任何人知道，即使泄露也没有任何关系）
* （3）甲使用乙传给的公钥加密要发送的信息原文m，发送给乙密文c
* （4）乙使用自己的私钥解密密文c，得到信息原文m 

如果公钥加密的信息只有私钥解得开，那么只要私钥不泄漏，通信就是安全的。
####3.RSA算法的出现
1977年，三位数学家Rivest、Shamir 和 Adleman 设计了一种算法，可以实现非对称加密。这种算法用他们三个人的名字命名，叫做[RSA算法](http://zh.wikipedia.org/zh-cn/RSA%E5%8A%A0%E5%AF%86%E7%AE%97%E6%B3%95)。
这种算法非常[可靠](http://en.wikipedia.org/wiki/RSA_Factoring_Challenge)，密钥越长，它就越难破解。根据已经披露的文献，目前被破解的最长RSA密钥是768个二进制位。也就是说，长度超过768位的密钥，还无法破解（至少没人公开宣布）。因此可以认为，1024位的RSA密钥基本安全，2048位的密钥极其安全。


## 数论知识
#### 1.质数
一个大于1的自然数，除了1和它本身外，不能被其他自然数整除（除0以外）的数称之为质数（素数）；否则称为合数。
#### 2.互质数
**互质**，又称**互素**。若N个整数的[最大公因子](http://zh.wikipedia.org/wiki/%E6%9C%80%E5%A4%A7%E5%85%AC%E5%9B%A0%E6%95%B8)是1，则称这N个整数互质。
#### 3.指数运算
>指数运算又称乘方计算，计算结果称为幂。*nm
*指将*n*自乘*m*次。把*nm
*看作乘方的结果，叫做”n的m次幂”或”n的m次方”。其中，n称为“**底数**”，m称为“**[指数](https://zh.wikipedia.org/wiki/%E6%8C%87%E6%95%B0)**”。

#### 4.模运算
>让m去被n整除，只取所得的余数作为结果，就叫做模运算。

例如，10 mod 3 = 1 、26 mod 6 = 2 、28 mod 2 = 0
#### 5.同余
>给定一个正整数m，如果两个整数a和b满足a-b能被m整除，即(a-b)modm=0，那么就称整数a与b对模m同余，记作a≡b(modm)，同时可成立amodm=b。

#### 6.欧拉函数
>任意给定正整数n，计算在小于等于n的正整数之中，有多少个与n构成互质关系？计算这个值的方法就叫做欧拉函数，以φ(n)表示.

例如，在1到8之中，与8形成互质关系的是1、3、5、7，所以φ(n)=4
在RSA算法中，我们需要明白欧拉函数对以下定理成立

>如果n可以分解成两个互质的整数之积，即n=p×q，则有：φ(n)=φ(pq)=φ(p)φ(q);
根据“大数是质数的两个数一定是互质数”可以知道：一个数如果是质数，则小于它的所有正整数与它都是互质数；所以如果一个数p是质数，则有：φ(p)=p-1

由上易得，若我们知道一个数n可以分解为两个**质数**p和q的乘积，则有
φ(n)=(p-1)(q-1)

#### 7.欧拉定理
>如果两个正整数a和n互质，则n的欧拉函数φ(n)可以让下面的等式成立：
![](http://upload-images.jianshu.io/upload_images/1829891-47c5e3497bd4b0df.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)



比如，3和7互质，而7的欧拉函数φ(7)等于6，所以3的6次方（729）减去1，可以被7整除（728/7=104）。

#### 8.模反元素

>
![](http://upload-images.jianshu.io/upload_images/1829891-5daf89a581f7f82e.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)


意即，如果两个正整数a和n互质，那么一定可以找到整数b
使得ab-1被n整除，或者说ab被n除的余数是1

比如，3和11互质，那么3的模反元素就是4，因为 (3 × 4)-1 可以被11整除。显然，模反元素不止一个， 4加减11的整数倍都是3的模反元素 {...,-18,-7,4,15,26,...}，即如果b是a的模反元素，则 b+kn 都是a的模反元素。

## 算法基础
#### 1.实例
先通过一个实例来理解RSA算法的过程：

甲要发给乙一个加密内容：m=65
乙发送甲公钥：(n,e)=(3233,17)
甲根据公式
![](http://upload-images.jianshu.io/upload_images/1829891-7395fe6ed61b7344.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

加密出c
![](http://upload-images.jianshu.io/upload_images/1829891-51c6de1506849b1d.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

甲将使用公钥加密的密文c=2790发送给乙
乙收到c=2790的密文后使用私钥(n,d)=(3233,2753)
根据公式


![](http://upload-images.jianshu.io/upload_images/1829891-da42f8de042e5041.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)


解密出m


![](http://upload-images.jianshu.io/upload_images/1829891-7858da368410f4ca.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)


从始至终，用来解密的私钥(n,d)=(3233,2753)一直都在乙处，从未泄露。乙给甲的仅仅是用来加密的公钥(3233,17)，这个公钥并不能用来解密，即使被他人截获，也没有任何泄密的风险。

#### 2.计算公私钥
* 1.随机选择两个不相等的质数p和q（乙选择了61和53）
* 2.计算p和q的乘积n=p×q=61×53=3233
* 3.根据本文“欧拉函数”介绍过的公式
φ(n)=(p-1)(q-1)
代入计算n的欧拉函数值
φ(3233)=(61-1)×(53-1)=60×52=3120
* 4.随机选择一个整数e，条件是1<e<φ(n)，且e与φ(n)互质
乙就在1到3120之间，随机选择了17
* 5.因为e与φ(n)互质，根据求模反元素的公式计算e，对于e的模反元素d有：
ed≡1(modφ(n))
这个式子等价于
(ed-1)/φ(n)=k（k为任意正整数）
即
ed-kφ(n)=1，
代入数据得：17d-3120k=1
实质上就是对以上这个二元一次方程求解得到一组解为：(d,k)=(2753,-15)
* 6.将n和e封装成公钥，n和d封装成私钥
n=3233，e=17，d=2753
所以公钥就是(3233,17)，私钥就是(3233,2753)

**至此，整个rsa公私钥的算法就清楚了**

#### 3.推导
整个过程中，让人困扰的可能是
![式子1](http://upload-images.jianshu.io/upload_images/1829891-3c9a991741dc07d9.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
与
![式子2](http://upload-images.jianshu.io/upload_images/1829891-9e1389799df604e7.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

事实上式子2就是从式子1推导出来，具体过程可以参考[RSA算法原理（二）](http://www.ruanyifeng.com/blog/2013/07/rsa_algorithm_part_two.html)，这边也做一个简单描述：


![](http://upload-images.jianshu.io/upload_images/1829891-f08afeea56d9ee1e.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)


![](http://upload-images.jianshu.io/upload_images/1829891-e702c3d478ce7cd8.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)


![](http://upload-images.jianshu.io/upload_images/1829891-4076ef8351b67072.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)


#### 4.安全性
在上面给出的例子中，一共出现了6个数字：

* 随机质数p	 	61
* 随机质数q			53
* n=p×q			3233
* φ(n)=(p-1)(q-1) 		3120
* 随机e与φ(n)互质	17
* e的模反元素d		 2753

其中公钥用到了(n,e)，剩下4个不知。关键私钥(n,d)，关键值是d，不能泄露d。

**那么，有无可能在已知n和e的情况下，推导出d？**
* （1）ed≡1 (mod φ(n))。只有知道e和φ(n)，才能算出d。
* （2）φ(n)=(p-1)(q-1)。只有知道p和q，才能算出φ(n)。
* （3）n=pq。只有将n因数分解，才能算出p和q。

**结论：如果n可以被因数分解，d就可以算出，也就意味着私钥被破解。**
**事实上，RSA的安全性就是源自你没办法轻易的对大整数“因式分解”。人类已经分解的最大整数（232个十进制位，768个二进制位）。比它更大的因数分解，还没有被报道过，因此目前被破解的最长RSA密钥就是768位。实际应用中，RSA密钥一般是1024位，重要场合则为2048位。**


## 算法实现
#### iOS中的实现与使用
iOS的 <sercurity.framework>框架中包含可以使用RSA加密与解密的方法：
```
//加密方法
OSStatus SecKeyEncrypt(
   SecKeyRef           key,
   SecPadding          padding,
   const uint8_t  *plainText,
   size_t              plainTextLen,
   uint8_t             *cipherText,
   size_t              *cipherTextLen)
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_2_0);

//解密方法
OSStatus SecKeyDecrypt(
    SecKeyRef           key,                                /* Private key */
    SecPadding          padding,			  /* kSecPaddingNone,
                                                                         kSecPaddingPKCS1,
                                                                       kSecPaddingOAEP */
    const uint8_t       *cipherText,
    size_t              cipherTextLen,		/* length of cipherText */
    uint8_t             *plainText,	
    size_t              *plainTextLen)		/* IN/OUT */
    __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_2_0);
```
但这个framework的api只支持从标准证书文件(cer,crt)中读取公私钥。

**所以先要使用openssl生成公钥证书public_key.der和私钥证书private_key.p12。然后读取公私钥，再用framework进行加密。**

```
    RSAEncryptor* rsaEncryptor = [[RSAEncryptor alloc] init];
    NSString* publicKeyPath = [[NSBundle mainBundle] pathForResource:@"public_key" ofType:@"der"];
    NSString* privateKeyPath = [[NSBundle mainBundle] pathForResource:@"private_key" ofType:@"p12"];
    [rsaEncryptor loadPublicKeyFromFile: publicKeyPath];
    [rsaEncryptor loadPrivateKeyFromFile: privateKeyPath password:@""];    // 这里，请换成你生成p12时的密码
    
    NSString* restrinBASE64STRING = [rsaEncryptor rsaEncryptString:@"I.O.S"];
    NSLog(@"Encrypted: %@", restrinBASE64STRING);       // 请把这段字符串Copy到JAVA这边main()里做测试
    NSString* decryptString = [rsaEncryptor rsaDecryptString: restrinBASE64STRING];
    NSLog(@"Decrypted: %@", decryptString);
```
具体的RSAEncryptor代码，这里就不贴了，可以从我的[github](https://github.com/game3108/RSA-algorithm)上找相应的iOS加解密的代码。上面还有一个c++的RSA算法的例子，可以看一下。

## 总结
本文主要还是整理了网上各个文章，其中数学原理解释的最清楚的应该是阮一峰的[RSA算法原理（一）](http://www.ruanyifeng.com/blog/2013/06/rsa_algorithm_part_one.html)与[RSA算法原理（二）](http://www.ruanyifeng.com/blog/2013/07/rsa_algorithm_part_two.html)。数学原理上有不懂的可以再看一下这两篇文章。最后总结一下RSA算法加密方式。

密钥组成与加解密 | 公式
-----|-----
公钥KU | n：质数p和质数q的乘积（p和q必须保密）e：与(p-1)×(q-1)互质
私钥KR | n：同公钥nd：![](http://upload-images.jianshu.io/upload_images/1829891-9f673763188db106.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
加密 | ![](http://upload-images.jianshu.io/upload_images/1829891-fc0048217477f83d.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
解密 | ![](http://upload-images.jianshu.io/upload_images/1829891-73de887504a8843c.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

## 参考资料
[本文CSDN地址](http://blog.csdn.net/game3108/article/details/53485347)
1.[RSA算法原理（一）](http://www.ruanyifeng.com/blog/2013/06/rsa_algorithm_part_one.html)
2.[RSA算法原理（二）](http://www.ruanyifeng.com/blog/2013/07/rsa_algorithm_part_two.html)
2.[wiki-RSA加密算法](https://zh.wikipedia.org/zh-cn/RSA%E5%8A%A0%E5%AF%86%E6%BC%94%E7%AE%97%E6%B3%95)
3.[RSA算法基础详解](http://www.cnblogs.com/hykun/p/RSA.html)
4.[RSA加密](https://blog.cnbluebox.com/blog/2014/03/19/rsajia-mi/)
5.[[iOS 上的 RSA 加密方法](http://johnny.logdown.com/posts/69881-rsa-encryption-method-on-ios)](http://johnny.logdown.com/posts/69881-rsa-encryption-method-on-ios)
6.[通过ios实现RSA加密和解密](http://blog.csdn.net/u011467458/article/details/50676494)
