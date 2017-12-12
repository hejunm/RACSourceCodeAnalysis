//
//  RACDynamicSignal.m
//  ReactiveObjC
//
//  Created by Justin Spahr-Summers on 2013-10-10.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "RACDynamicSignal.h"
#import "RACEXTScope.h"
#import "RACCompoundDisposable.h"
#import "RACPassthroughSubscriber.h"
#import "RACScheduler+Private.h"
#import "RACSubscriber.h"
#import <libkern/OSAtomic.h>

@interface RACDynamicSignal ()

// The block to invoke for each subscriber.
@property (nonatomic, copy, readonly) RACDisposable * (^didSubscribe)(id<RACSubscriber> subscriber);

@end

@implementation RACDynamicSignal

#pragma mark Lifecycle

+ (RACSignal *)createSignal:(RACDisposable * (^)(id<RACSubscriber> subscriber))didSubscribe {
	RACDynamicSignal *signal = [[self alloc] init];
	signal->_didSubscribe = [didSubscribe copy];
	return [signal setNameWithFormat:@"+createSignal:"];
}

#pragma mark Managing Subscribers

- (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
	NSCParameterAssert(subscriber != nil);
    
	RACCompoundDisposable *disposable = [RACCompoundDisposable compoundDisposable];
    /**
     装饰者， passthroughSubscriber会作为didSubscribe block的参数进行调用。
     在sendNext等进行事件分发时，会先判断passthroughSubscriber.disposable否已经dispose, 如果已经dispose，直接返回。
     形参subscriber（subscriber1）中存在一个disposable对象（disposable1），passthroughSubscriber.disposable会添加到disposable1中
     didSubscribe block返回一个自己创建的disposable，用于释放资源，并添加到passthroughSubscriber.disposable中。
     当subscriber1 调用sendError 或 sendComplate时，disposable1会执行dispose方法，这时会遍历其保存的所有的disposable并执行dispose，完成资源释放。
     当subscriber1 delloc时,也会调用disposable1的dispose方法。
     之后再执行sendNest,sendError,sendComplate就不会执行了。
     
     一个订阅者可以订阅多个信号。该方法返回disposable用于释放本次订阅产生的资源。
     
     如果订阅者执行 dispose， 那么释放与该订阅者相关的所有资源。
     
     */
   
	subscriber = [[RACPassthroughSubscriber alloc] initWithSubscriber:subscriber signal:self disposable:disposable];
	if (self.didSubscribe != NULL) {
		RACDisposable *schedulingDisposable = [RACScheduler.subscriptionScheduler schedule:^{
			RACDisposable *innerDisposable = self.didSubscribe(subscriber);
			[disposable addDisposable:innerDisposable];
		}];

		[disposable addDisposable:schedulingDisposable];
	}
	
	return disposable;
}

@end
