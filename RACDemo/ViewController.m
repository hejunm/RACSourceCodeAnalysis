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
    
    RACSequence *sequence = [RACSequence sequenceWithHeadBlock:^id _Nullable{
        return @1;
    } tailBlock:^RACSequence * _Nonnull{
        return [RACSequence sequenceWithHeadBlock:^id _Nullable{
            return @2;
        } tailBlock:^RACSequence * _Nonnull{
            return [RACSequence return:@3];
        }];
    }];
    
    RACSequence *bindSequence = [sequence bind:^RACSequenceBindBlock _Nonnull{
        return ^(NSNumber *value, BOOL *stop) {
            NSLog(@"RACSequenceBindBlock: %@", value);
            value = @(value.integerValue * 2);
            return [RACSequence return:value];
        };
    }];
    
    id tail =  bindSequence.tail.tail.tail;
    
    NSLog(@"hha");
}

@end
