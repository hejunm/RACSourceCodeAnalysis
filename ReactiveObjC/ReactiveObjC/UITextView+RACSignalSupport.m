//
//  UITextView+RACSignalSupport.m
//  ReactiveObjC
//
//  Created by Cody Krieger on 5/18/12.
//  Copyright (c) 2012 Cody Krieger. All rights reserved.
//

#import "UITextView+RACSignalSupport.h"
#import "RACEXTScope.h"
#import "NSObject+RACDeallocating.h"
#import "NSObject+RACDescription.h"
#import "RACDelegateProxy.h"
#import "RACSignal+Operations.h"
#import "RACTuple.h"
#import <objc/runtime.h>

@implementation UITextView (RACSignalSupport)

/**
 在这里对self.delegate 进行移花接木。替换之。
 self.rac_delegateProxy.rac_proxiedDelegate = self.delegate;
 self.delegate = (id)self.rac_delegateProxy;
 
 当UITextView有啥事件需要通知给代理时，就会调用rac_delegateProxy的相应代理方法。但是rac_delegateProxy没有实现呀，
 这是就会转发给它rac_proxiedDelegate。 转发过程在RACDelegateProxy 实现。
 
 这时，UITextView有事件需要通知给delegate时，都会通过RACDelegateProxy进行转发。
 相当于加入了一个hook。
 
 分析到这里，两个问题不由的从脑海中浮现：
 如何将代理方法转变成signal？ 怎么用这个hook？
 
 在下面的方法寻找答案吧！
 [self.rac_delegateProxy signalForSelector:@selector(textViewDidChange:)]
 */
static void RACUseDelegateProxy(UITextView *self) {
    if (self.delegate == self.rac_delegateProxy) return;

    self.rac_delegateProxy.rac_proxiedDelegate = self.delegate;
    self.delegate = (id)self.rac_delegateProxy;
}

- (RACDelegateProxy *)rac_delegateProxy {
	RACDelegateProxy *proxy = objc_getAssociatedObject(self, _cmd);
	if (proxy == nil) {
		proxy = [[RACDelegateProxy alloc] initWithProtocol:@protocol(UITextViewDelegate)];
		objc_setAssociatedObject(self, _cmd, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	return proxy;
}

- (RACSignal *)rac_textSignal {
	@weakify(self);
	RACSignal *signal = [[[[[RACSignal
		defer:^{
			@strongify(self);
			return [RACSignal return:RACTuplePack(self)];
		}]
		concat:[self.rac_delegateProxy signalForSelector:@selector(textViewDidChange:)]]
		reduceEach:^(UITextView *x) {
			return x.text;
		}]
		takeUntil:self.rac_willDeallocSignal]
		setNameWithFormat:@"%@ -rac_textSignal", RACDescription(self)];

    /**移花接木*/
	RACUseDelegateProxy(self);

	return signal;
}

@end
