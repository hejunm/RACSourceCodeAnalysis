//
//  UIControl+RACSignalSupportPrivate.m
//  ReactiveObjC
//
//  Created by Uri Baghin on 06/08/2013.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "UIControl+RACSignalSupportPrivate.h"
#import "NSObject+RACDeallocating.h"
#import "NSObject+RACLifting.h"
#import "RACChannel.h"
#import "RACCompoundDisposable.h"
#import "RACDisposable.h"
#import "RACSignal+Operations.h"
#import "UIControl+RACSignalSupport.h"

@implementation UIControl (RACSignalSupportPrivate)

- (RACChannelTerminal *)rac_channelForControlEvents:(UIControlEvents)controlEvents key:(NSString *)key nilValue:(id)nilValue {
	NSCParameterAssert(key.length > 0);
	key = [key copy];
	RACChannel *channel = [[RACChannel alloc] init];

	[self.rac_deallocDisposable addDisposable:[RACDisposable disposableWithBlock:^{
		[channel.followingTerminal sendCompleted];
	}]];

    /**监听controlEvents，触发事件后将改事件值转变成key。*/
	RACSignal *eventSignal = [[[self
		rac_signalForControlEvents:controlEvents]
		mapReplace:key]
		takeUntil:[[channel.followingTerminal ignoreValues]catchTo:RACSignal.empty]];
	
    /**
     方向一：触发事件，从leadingTerminal中接受。
     eventSignal发送事件时（也就是controlEvents事件触发时），会调用valueForKey获取相应的值。key就是传进来的参数。
     channel.followingTerminal订阅这个信号。那么leadingTerminal就会收到valueForKey 返回的值。
     */
    [[self
		rac_liftSelector:@selector(valueForKey:) withSignals:eventSignal, nil]
		subscribe:channel.followingTerminal];

    /**
     方向二：
     leadingTerminal发送一个值， 然后触发(setValue:forKey:) 。
     leadingTerminal发送一个值，valuesSignal信号就会发送一个valeu。然后进行一个map。会后调用setValue:forKey:
     */
	RACSignal *valuesSignal = [channel.followingTerminal
		map:^(id value) {
			return value ?: nilValue;
		}];
	[self rac_liftSelector:@selector(setValue:forKey:) withSignals:valuesSignal, [RACSignal return:key], nil];

	return channel.leadingTerminal;
}

@end
