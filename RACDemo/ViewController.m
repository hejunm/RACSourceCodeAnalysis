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
    
    RACSequence *sequence1 = [RACSequence sequenceWithHeadBlock:^id _Nullable{
        return @1;
    } tailBlock:^RACSequence * _Nonnull{
        return [RACSequence return:@2];
    }];
    
    RACSequence *sequence2 = [RACSequence sequenceWithHeadBlock:^id _Nullable{
        return @3;
    } tailBlock:^RACSequence * _Nonnull{
        return [RACSequence return:@4];
    }];
    
     RACSequence *seq = [[RACArraySequence sequenceWithArray:@[sequence1, sequence2] offset:0] bind:^{
        return ^(id value, BOOL *stop) {
            return value;
        };
    }];
    
    
    id current;
    NSEnumerator *en = seq.objectEnumerator;
    while (current =  [en nextObject]) {
        NSLog(@"%@",current);
    }
    
}

@end
