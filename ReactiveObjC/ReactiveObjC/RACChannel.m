//
//  RACChannel.m
//  ReactiveObjC
//
//  Created by Uri Baghin on 01/01/2013.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "RACChannel.h"
#import "RACDisposable.h"
#import "RACReplaySubject.h"
#import "RACSignal+Operations.h"

@interface RACChannelTerminal<ValueType> ()

/// The values for this terminal.
@property (nonatomic, strong, readonly) RACSignal<ValueType> *values;

/// A subscriber will will send values to the other terminal.
@property (nonatomic, strong, readonly) id<RACSubscriber> otherTerminal;

- (instancetype)initWithValues:(RACSignal<ValueType> *)values otherTerminal:(id<RACSubscriber>)otherTerminal;

@end

@implementation RACChannel
/**
 _leadingTerminal，_followingTerminal既可以作为信号，也能作为订阅者。
 leadingSubject和followingSubject类型为RACReplaySubject
 内部结构如下：
 
                 |_leadingTerminal                          _followingTerminal           |
                 |                                                                       |
    subscribe<-- |value:leadingSubject            <-    ->  value:followingSubject       |-->subscribe
                 |                                  \  /                                 |
                 |                                   \/                                  |
                 |                                   /\                                  |
                 |                                  /  \                                 |
    sourceSignal1|                                 /    \                                |sourceSignal2
    sendEvent--> |otherTerminal:followingSubject->/      \<-otherTerminal:leadingSubject |<--sendEvent
                 |                                                                       |
     
 followingSubject的Capacity为1，所以订阅者在订阅时，会立刻收到一个保存的历史值。
 leadingSubject  的Capacity为0，所以不会有上述特性。
 
 （1）当_leadingTerminal作为信号:
 [_leadingTerminal subscribeNext:^(ValueType  _Nullable x) {
 
 }];
 用于接受leadingSubject发送的事件
 
 （2）_leadingTerminal作为订阅者:
 [sourceSignal subscribe:_leadingTerminal]
将sourceSignal发出的事件发给followingSubject
 */

- (instancetype)init {
	self = [super init];

	// We don't want any starting value from the leadingSubject, but we do want
	// error and completion to be replayed.
	RACReplaySubject *leadingSubject = [[RACReplaySubject replaySubjectWithCapacity:0] setNameWithFormat:@"leadingSubject"];
	RACReplaySubject *followingSubject = [[RACReplaySubject replaySubjectWithCapacity:1] setNameWithFormat:@"followingSubject"];

	// Propagate errors and completion to everything.
	[[leadingSubject ignoreValues] subscribe:followingSubject];
	[[followingSubject ignoreValues] subscribe:leadingSubject];

	_leadingTerminal = [[[RACChannelTerminal alloc] initWithValues:leadingSubject otherTerminal:followingSubject] setNameWithFormat:@"leadingTerminal"];
	_followingTerminal = [[[RACChannelTerminal alloc] initWithValues:followingSubject otherTerminal:leadingSubject] setNameWithFormat:@"followingTerminal"];
	return self;
}

@end

@implementation RACChannelTerminal

#pragma mark Lifecycle

- (instancetype)initWithValues:(RACSignal *)values otherTerminal:(id<RACSubscriber>)otherTerminal {
	NSCParameterAssert(values != nil);
	NSCParameterAssert(otherTerminal != nil);

	self = [super init];

	_values = values;
	_otherTerminal = otherTerminal;

	return self;
}

#pragma mark RACSignal

- (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
	return [self.values subscribe:subscriber];
}

#pragma mark <RACSubscriber>

- (void)sendNext:(id)value {
	[self.otherTerminal sendNext:value];
}

- (void)sendError:(NSError *)error {
	[self.otherTerminal sendError:error];
}

- (void)sendCompleted {
	[self.otherTerminal sendCompleted];
}

- (void)didSubscribeWithDisposable:(RACCompoundDisposable *)disposable {
	[self.otherTerminal didSubscribeWithDisposable:disposable];
}

@end
