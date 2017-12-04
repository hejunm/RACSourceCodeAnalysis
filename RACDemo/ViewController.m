//
//  ViewController.m
//  RACDemo
//
//  Created by jmhe on 2017/11/23.
//  Copyright © 2017年 贺俊孟. All rights reserved.
//

#import "ViewController.h"
#import "ReactiveObjC.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self zipWith];
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)zipWith {
    //zipWith:把两个信号压缩成一个信号，只有当两个信号同时发出信号内容时，并且把两个信号的内容合并成一个元祖，才会触发压缩流的next事件。
    // 创建信号A
    RACSubject *signalA = [RACSubject subject];
    [[signalA map:^id (id value) {
        return @([value integerValue] *2);
    }]subscribeNext:^(id  x) {
        NSLog(@"%@",x);
    } error:^(NSError * error) {
        NSLog(@"%@",error);
    } completed:^{
        NSLog(@"结束");
    }];
    
    
    // 发送信号 交互顺序，元组内元素的顺序不会变，跟发送的顺序无关，而是跟压缩的顺序有关[signalA zipWith:signalB]---先是A后是B
    [signalA sendNext:@1];
    [signalA sendNext:@2];
    [signalA sendNext:@3];
    [signalA sendNext:@4];
    [signalA sendNext:@5];
    
}

@end
