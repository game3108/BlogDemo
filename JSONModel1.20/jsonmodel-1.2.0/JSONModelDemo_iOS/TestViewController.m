//
//  TestViewController.m
//  JSONModelDemo_iOS
//
//  Created by game3108 on 16/7/26.
//  Copyright © 2016年 Underplot ltd. All rights reserved.
//

#import "TestViewController.h"
#import "TestObject.h"
#import "TestJSONModel.h"

@interface TestViewController ()

@end

@implementation TestViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    NSData* ghData = [NSData dataWithContentsOfURL: [NSURL URLWithString:@"http://xxxx"]];
    NSDictionary* json = nil;
    if (ghData) {
        json = [NSJSONSerialization
                JSONObjectWithData:ghData
                options:kNilOptions
                error:nil];
    }
    
    TestObject *testObject = [[TestObject alloc]init];
    testObject.name     = json[@"name"];
    testObject.number   = json[@"number"];
    testObject.age      = [json[@"age"] integerValue];
    
    JSONModelError *error = nil;
    TestJSONModel *testJSONModel = [[TestJSONModel alloc]initWithDictionary:json error:&error];
    

}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
