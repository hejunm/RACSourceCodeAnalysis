//
//  RACMulticastConnection.m
//  ReactiveObjC
//
//  Created by Josh Abernathy on 4/11/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACMulticastConnection.h"
#import "RACMulticastConnection+Private.h"
#import "RACDisposable.h"
#import "RACSerialDisposable.h"
#import "RACSubject.h"
#import <libkern/OSAtomic.h>

@interface RACMulticastConnection () {
	RACSubject *_signal;

	// When connecting, a caller should attempt to atomically swap the value of this
	// from `0` to `1`.
	//
	// If the swap is successful the caller is resposible for subscribing `_signal`
	// to `sourceSignal` and storing the returned disposable in `serialDisposable`.
	//
	// If the swap is unsuccessful it means that `_sourceSignal` has already been
	// connected and the caller has no action to take.
	//volatile 可以保证线程安全
    
    int32_t volatile _hasConnected;
}

@property (nonatomic, readonly, strong) RACSignal *sourceSignal;
@property (strong) RACSerialDisposable *serialDisposable;
@end

@implementation RACMulticastConnection

#pragma mark Lifecycle

//初始化方法。
- (instancetype)initWithSourceSignal:(RACSignal *)source subject:(RACSubject *)subject {
	NSCParameterAssert(source != nil);
	NSCParameterAssert(subject != nil);

	self = [super init];

	_sourceSignal = source;
	_serialDisposable = [[RACSerialDisposable alloc] init];
	_signal = subject;
	
	return self;
}

#pragma mark Connecting


- (RACDisposable *)connect {
    /**
     比较0 和 _hasConnected。 如果相等返回true,并将1 赋值给_hasConnected。
     整个操作都是原子性的。
     执行一次后shouldConnect = NO.
     这样就保证了原信号只能被订阅一次。
     */
    
	BOOL shouldConnect = OSAtomicCompareAndSwap32Barrier(0, 1, &_hasConnected);
	if (shouldConnect) {
		self.serialDisposable.disposable = [self.sourceSignal subscribe:_signal];
	}

	return self.serialDisposable;
}

/**
返回一个自己创建的信号(命名为‘连接信号’吧)。
当订阅者订阅‘连接信号’时，将订阅者添加到RACSubject的订阅者数组中。 并执行connect操作。
 */
- (RACSignal *)autoconnect {
	__block volatile int32_t subscriberCount = 0;

	return [[RACSignal
		createSignal:^(id<RACSubscriber> subscriber) {
            
            //记录RACSubject被订阅的次数。原子操作
			OSAtomicIncrement32Barrier(&subscriberCount);

			RACDisposable *subscriptionDisposable = [self.signal subscribe:subscriber];
			RACDisposable *connectionDisposable = [self connect];

			return [RACDisposable disposableWithBlock:^{
				[subscriptionDisposable dispose];

                //当RACSubject的订阅者数组count是0时，取消对原信号的订阅
				if (OSAtomicDecrement32Barrier(&subscriberCount) == 0) {
					[connectionDisposable dispose];
				}
			}];
		}]
		setNameWithFormat:@"[%@] -autoconnect", self.signal.name];
}

@end
