//
//  ViewController.m
//  RACDemo
//
//  Created by jmhe on 2017/11/23.
//  Copyright © 2017年 贺俊孟. All rights reserved.
//

#import "ViewController.h"
#import "ReactiveObjC.h"
#import "RACArraySequence.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    
    UITextField *tf = [[UITextField alloc]initWithFrame:CGRectMake(30, 60, 60, 20)];
    tf.backgroundColor = [UIColor redColor];
    [self.view addSubview:tf];
                     
    NSMutableArray *start = [[NSMutableArray alloc] init];
//    RACSignal *signal = [tf.rac_textSignal scanWithStart:start reduce:^id (NSMutableArray *collectedValues, id x) {
//        [collectedValues addObject:(x ?: NSNull.null)];
//        return collectedValues;
//    }];
//    [signal subscribeNext:^(id x) {
//        NSLog(@"%@",x);
//    }];
    
}



@end
