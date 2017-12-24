//
//  RACCommand.m
//  ReactiveObjC
//
//  Created by Josh Abernathy on 3/3/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACCommand.h"
#import "RACEXTScope.h"
#import "NSArray+RACSequenceAdditions.h"
#import "NSObject+RACDeallocating.h"
#import "NSObject+RACDescription.h"
#import "NSObject+RACPropertySubscribing.h"
#import "RACMulticastConnection.h"
#import "RACReplaySubject.h"
#import "RACScheduler.h"
#import "RACSequence.h"
#import "RACSignal+Operations.h"
#import <libkern/OSAtomic.h>

NSString * const RACCommandErrorDomain = @"RACCommandErrorDomain";
NSString * const RACUnderlyingCommandErrorKey = @"RACUnderlyingCommandErrorKey";

const NSInteger RACCommandErrorNotEnabled = 1;

@interface RACCommand () {
	// Atomic backing variable for `allowsConcurrentExecution`.
	volatile uint32_t _allowsConcurrentExecution;
}

/// A subject that sends added execution signals.
@property (nonatomic, strong, readonly) RACSubject *addedExecutionSignalsSubject;

/// A subject that sends the new value of `allowsConcurrentExecution` whenever it changes.
/**
 是否允许同时执行。
 当
 */
@property (nonatomic, strong, readonly) RACSubject *allowsConcurrentExecutionSubject;

// `enabled`, but without a hop to the main thread.
//
// Values from this signal may arrive on any thread.
@property (nonatomic, strong, readonly) RACSignal *immediateEnabled;

// The signal block that the receiver was initialized with.
@property (nonatomic, copy, readonly) RACSignal * (^signalBlock)(id input);

@end

@implementation RACCommand

#pragma mark Properties
//get方法
- (BOOL)allowsConcurrentExecution {
	return _allowsConcurrentExecution != 0;
}

//set方法。设置完后，allowsConcurrentExecutionSubject通知给订阅者。
- (void)setAllowsConcurrentExecution:(BOOL)allowed {
	if (allowed) {
		OSAtomicOr32Barrier(1, &_allowsConcurrentExecution);
	} else {
		OSAtomicAnd32Barrier(0, &_allowsConcurrentExecution);
	}

	[self.allowsConcurrentExecutionSubject sendNext:@(_allowsConcurrentExecution)];
}

#pragma mark Lifecycle

- (instancetype)init {
	NSCAssert(NO, @"Use -initWithSignalBlock: instead");
	return nil;
}

- (instancetype)initWithSignalBlock:(RACSignal<id> * (^)(id input))signalBlock {
	return [self initWithEnabled:nil signalBlock:signalBlock];
}

- (void)dealloc {
	[_addedExecutionSignalsSubject sendCompleted];
	[_allowsConcurrentExecutionSubject sendCompleted];
}

- (instancetype)initWithEnabled:(RACSignal *)enabledSignal signalBlock:(RACSignal<id> * (^)(id input))signalBlock {
	NSCParameterAssert(signalBlock != nil);

	self = [super init];

	_addedExecutionSignalsSubject = [RACSubject new];
	_allowsConcurrentExecutionSubject = [RACSubject new];
	_signalBlock = [signalBlock copy];

	_executionSignals = [[[self.addedExecutionSignalsSubject
		map:^(RACSignal *signal) {
            //signal发error事件时，订阅号订阅[RACSignal empty]。
			return [signal catchTo:[RACSignal empty]];
		}]
		deliverOn:RACScheduler.mainThreadScheduler]
		setNameWithFormat:@"%@ -executionSignals", self];
	
	// `errors` needs to be multicasted so that it picks up all
	// `activeExecutionSignals` that are added.
	//
	// In other words, if someone subscribes to `errors` _after_ an execution
	// has started, it should still receive any error from that execution.
    /**
     addedExecutionSignalsSubject是一个可以send信号（子信号）的信号。
     _errors用于收集所有子信号发出的error。
     */
	RACMulticastConnection *errorsConnection = [[[self.addedExecutionSignalsSubject
		flattenMap:^(RACSignal *signal) {
			return [[signal
				ignoreValues]
				catch:^(NSError *error) {
					return [RACSignal return:error];
				}];
		}]
		deliverOn:RACScheduler.mainThreadScheduler]
		publish];
	
	_errors = [errorsConnection.signal setNameWithFormat:@"%@ -errors", self];
	[errorsConnection connect];

    /**
     当前的command是否正在执行
     */
	RACSignal *immediateExecuting = [[[[self.addedExecutionSignalsSubject
		flattenMap:^(RACSignal *signal) {
            /**
             根据(running.integerValue + next.integerValue)是否是0判断信号是否正在执行。
             */
			return [[[signal
              /**
               cacheTo 和 then 确保了signal在发error和complate 计数减1. 也就是[RACSignal return:@-1]。 开始是1.
               */
				catchTo:[RACSignal empty]]
				then:^{
					return [RACSignal return:@-1];
				}]
				startWith:@1];
		}]
        /**
         累加，当结果是0，代表没有正在执行的了。否则，存在正在执行的。
         */
		scanWithStart:@0 reduce:^(NSNumber *running, NSNumber *next) {
			return @(running.integerValue + next.integerValue);
		}]
		map:^(NSNumber *count) {
			return @(count.integerValue > 0);
		}]
		startWith:@NO];

    /**
     A signal of whether this command is currently executing.
     确保订阅者的回调在主线程中执行。
     */
	_executing = [[[[[immediateExecuting
		deliverOn:RACScheduler.mainThreadScheduler]
		// This is useful before the first value arrives on the main thread.
		startWith:@NO]
		distinctUntilChanged]
		replayLast]
		setNameWithFormat:@"%@ -executing", self];
	
    /**
     是否允许更多的操作。
     _allowsConcurrentExecution 初始化是0，所以startWith:@NO。
     if then else 实现的效果就是if [self.allowsConcurrentExecutionSubject startWith:@NO]发yes,
     那么订阅者就订阅[RACSignal return:@YES]。 否则订阅者订阅[immediateExecuting not]。
     
     */
	RACSignal *moreExecutionsAllowed = [RACSignal
		if:[self.allowsConcurrentExecutionSubject startWith:@NO]
		then:[RACSignal return:@YES]
		else:[immediateExecuting not]];
	
    //enabledSignal发的第一个值是yes
	if (enabledSignal == nil) {
		enabledSignal = [RACSignal return:@YES];
	} else {
		enabledSignal = [enabledSignal startWith:@YES];
	}
	
    /**
     1,合并信号enabledSignal，moreExecutionsAllowed。两个信号中的任意一个发送事件，合并后的信号都会发送事件。
     如果正常的sendNext，那么合并后的信号发送元组类型的值。
     2，元组中的两个元素 进行and操作。
     3，rac_willDeallocSignal 信号发送值后，订阅者不再订阅此信号。
     4，保存最新的数据。当其他订阅者订阅时，直接得到最新的历史数据。
     
     */
	_immediateEnabled = [[[[RACSignal
		combineLatest:@[ enabledSignal, moreExecutionsAllowed ]]
		and]
		takeUntil:self.rac_willDeallocSignal]
		replayLast];
	
    /**
     1, take:1, 只获取一个。 bind会返回一个RACReturnSignal。
        这种信号被订阅时，调用订阅者的sendNext(value), 然后sendComplate.
     2，concat：在才immediateEnabled信号接收到到一个value后，订阅者订阅[[self.immediateEnabled skip:1] deliverOn:RACScheduler.mainThreadScheduler]]。订阅者的next,error,complate事件都是在主线程中执行。
     3，只有发送的value与上一次的不同，才将这个值发给订阅者。
     4，replayLast，保存最新的数据。当其他订阅者订阅时，直接得到最新的历史数据。
        
     */
	_enabled = [[[[[self.immediateEnabled
		take:1]
		concat:[[self.immediateEnabled skip:1] deliverOn:RACScheduler.mainThreadScheduler]]
		distinctUntilChanged]
		replayLast]
		setNameWithFormat:@"%@ -enabled", self];

	return self;
}



#pragma mark Execution
/**
 大致流程：
 execute:(id)input ---> signalBlock(input)--->  RACReplaySubject订阅signalBlock返回的signal---> 返回RACReplaySubject，使用方可以点阅这个Subject。
 
 辅助：
 enableSignal：用于控制commond是否可以被执行。可以看下面的逻辑。
 allowsConcurrentExecution：
 YES: 允许同时执行，就是当signalBlock返回的信号没有error,没有complate的情况下，执行execute，调用signalBlock，返回一个RACReplaySubject。
 NO: 一个command会返回一个RACReplaySubject。只有这个RACReplaySubject结束了，执行execute 才会生成一个新的RACReplaySubject。
 
 
 */
- (RACSignal *)execute:(id)input {
	// `immediateEnabled` is guaranteed to send a value upon subscription, so
	// -first is acceptable here.
	BOOL enabled = [[self.immediateEnabled first] boolValue];
	if (!enabled) {
		NSError *error = [NSError errorWithDomain:RACCommandErrorDomain code:RACCommandErrorNotEnabled userInfo:@{
			NSLocalizedDescriptionKey: NSLocalizedString(@"The command is disabled and cannot be executed", nil),
			RACUnderlyingCommandErrorKey: self
		}];

		return [RACSignal error:error];
	}

	RACSignal *signal = self.signalBlock(input);
	NSCAssert(signal != nil, @"nil signal returned from signal block for value: %@", input);

	// We subscribe to the signal on the main thread so that it occurs _after_
	// -addActiveExecutionSignal: completes below.
	//
	// This means that `executing` and `enabled` will send updated values before
	// the signal actually starts performing work.
	RACMulticastConnection *connection = [[signal
		subscribeOn:RACScheduler.mainThreadScheduler]
		multicast:[RACReplaySubject subject]];
	
	[self.addedExecutionSignalsSubject sendNext:connection.signal];

	[connection connect];
	return [connection.signal setNameWithFormat:@"%@ -execute: %@", self, RACDescription(input)];
}

@end
