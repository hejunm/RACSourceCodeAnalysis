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
    
    RACSubject *sub = [RACSubject subject];
    [[sub subscribeOn:[RACScheduler scheduler]]subscribeNext:^(id x) {
        NSLog(@"%@",[NSThread currentThread]);
        NSLog(@"hf");
    }];
    
    [NSThread sleepForTimeInterval:20];
    [sub sendNext:@"helo"];
    
    NSLog(@"fhkdj");
    
    
    
    
}



@end
