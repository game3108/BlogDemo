//
//  RSAEncryptor.h
//  RSA-Test
//
//  Created by game3108 on 2016/12/5.
//  Copyright © 2016年 game3108. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RSAEncryptor : NSObject
#pragma mark - Instance Methods
- (void) loadPublicKeyFromFile: (NSString*) derFilePath;
- (void) loadPublicKeyFromData: (NSData*) derData;

- (void) loadPrivateKeyFromFile: (NSString*) p12FilePath password:(NSString*)p12Password;
- (void) loadPrivateKeyFromData: (NSData*) p12Data password:(NSString*)p12Password;

- (NSString*) rsaEncryptString:(NSString*)string;
- (NSData*) rsaEncryptData:(NSData*)data ;

- (NSString*) rsaDecryptString:(NSString*)string;
- (NSData*) rsaDecryptData:(NSData*)data;

#pragma mark - Class Methods
+ (void) setSharedInstance: (RSAEncryptor*)instance;
+ (RSAEncryptor*) sharedInstance;
@end
