//
//  NSObject+RACLifting.m
//  ReactiveObjC
//
//  Created by Josh Abernathy on 10/13/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "NSObject+RACLifting.h"
#import "RACEXTScope.h"
#import "NSInvocation+RACTypeParsing.h"
#import "NSObject+RACDeallocating.h"
#import "NSObject+RACDescription.h"
#import "RACSignal+Operations.h"
#import "RACTuple.h"

@implementation NSObject (RACLifting)

/**
 arguments信号发送一个值，就会调用一次selector。参数就是信号发送的value（元组）.
 并保存最新的值。
 */
- (RACSignal *)rac_liftSelector:(SEL)selector withSignalOfArguments:(RACSignal *)arguments {
	NSCParameterAssert(selector != NULL);
	NSCParameterAssert(arguments != nil);
	
	@unsafeify(self);
	
	NSMethodSignature *methodSignature = [self methodSignatureForSelector:selector];
	NSCAssert(methodSignature != nil, @"%@ does not respond to %@", self, NSStringFromSelector(selector));
	
	return [[[[arguments
		takeUntil:self.rac_willDeallocSignal]
		map:^(RACTuple *arguments) {
			@strongify(self);
			
			NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
			invocation.selector = selector;
			invocation.rac_argumentsTuple = arguments;
			[invocation invokeWithTarget:self];
			
			return invocation.rac_returnValue;
		}]
		replayLast]
		setNameWithFormat:@"%@ -rac_liftSelector: %s withSignalsOfArguments: %@", RACDescription(self), sel_getName(selector), arguments];
}

/**
 将signals combineLatest。然后调用
 - (RACSignal *)rac_liftSelector:(SEL)selector withSignalOfArguments:(RACSignal *)arguments
 
 根据combineLatest的实现， 只有所有的信后都sendNext,合成后的信号才会发事件。
 也就是注释中的but only after each signal has sent an initial value
 */
- (RACSignal *)rac_liftSelector:(SEL)selector withSignalsFromArray:(NSArray *)signals {
	NSCParameterAssert(signals != nil);
	NSCParameterAssert(signals.count > 0);

	NSMethodSignature *methodSignature = [self methodSignatureForSelector:selector];
	NSCAssert(methodSignature != nil, @"%@ does not respond to %@", self, NSStringFromSelector(selector));

	NSUInteger numberOfArguments __attribute__((unused)) = methodSignature.numberOfArguments - 2;
	NSCAssert(numberOfArguments == signals.count, @"Wrong number of signals for %@ (expected %lu, got %lu)", NSStringFromSelector(selector), (unsigned long)numberOfArguments, (unsigned long)signals.count);

    /**
     combineLatest：聚合。 只要数组中的信号有一个发送了事件，订阅者就会收到数据（元组）
     */
	return [[self
		rac_liftSelector:selector withSignalOfArguments:[RACSignal combineLatest:signals]]
		setNameWithFormat:@"%@ -rac_liftSelector: %s withSignalsFromArray: %@", RACDescription(self), sel_getName(selector), signals];
}

/**确保可变参数都是信号，将这些参数封装到数组中。然后调用
 - (RACSignal *)rac_liftSelector:(SEL)selector withSignalsFromArray:(NSArray *)signals {
 */
- (RACSignal *)rac_liftSelector:(SEL)selector withSignals:(RACSignal *)firstSignal, ... {
	NSCParameterAssert(firstSignal != nil);

	NSMutableArray *signals = [NSMutableArray array];

	va_list args;
	va_start(args, firstSignal);
	for (id currentSignal = firstSignal; currentSignal != nil; currentSignal = va_arg(args, id)) {
		NSCAssert([currentSignal isKindOfClass:RACSignal.class], @"Argument %@ is not a RACSignal", currentSignal);

		[signals addObject:currentSignal];
	}
	va_end(args);

	return [[self
		rac_liftSelector:selector withSignalsFromArray:signals]
		setNameWithFormat:@"%@ -rac_liftSelector: %s withSignals: %@", RACDescription(self), sel_getName(selector), signals];
}

@end
