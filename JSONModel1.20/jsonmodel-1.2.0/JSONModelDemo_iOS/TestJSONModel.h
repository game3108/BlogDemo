//
//  TestJSONModel.h
//  JSONModelDemo_iOS
//
//  Created by game3108 on 16/7/26.
//  Copyright © 2016年 Underplot ltd. All rights reserved.
//

#import <JSONModel/JSONModel.h>

@interface TestJSONModel : JSONModel
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *number;
@property (nonatomic, assign) NSInteger age;
@end
