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
    [[RACScheduler scheduler]schedule:^{
        id value = [sub first];
        NSLog(@"%@",value);
    }];
    
    [[RACScheduler scheduler] afterDelay:30 schedule:^{
        [sub sendNext:@"1"];
    }];
    
}



@end
