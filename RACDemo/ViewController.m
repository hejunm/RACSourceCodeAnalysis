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
    
//    UITextField *tf = [[UITextField alloc]initWithFrame:CGRectMake(30, 60, 60, 20)];
//    tf.backgroundColor = [UIColor redColor];
//    [self.view addSubview:tf];
//
//    [[tf.rac_textSignal throttle:10] subscribeNext:^(NSString *x) {
//        NSLog(@"%@",x);
//    }];
    [self catch];
    
}

- (void)catch{
    RACSubject *sub = [RACSubject subject];
    
    RACSignal *signal1 = [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        NSLog(@"订阅了");
        return nil;
    }];
    
    [[sub catchTo:signal1]subscribeNext:^(id   x) {
        NSLog(@"%@",x);
    } error:^(NSError * error) {
        NSLog(@"%@",error);
    } completed:^{
        NSLog(@"结束");
    }];
    
    [sub sendNext:@"hello"];
    [sub sendError:[NSError errorWithDomain:@"fh" code:1 userInfo:nil]];
    [sub sendNext:@"hello4"];
    [sub sendCompleted];
}

@end
