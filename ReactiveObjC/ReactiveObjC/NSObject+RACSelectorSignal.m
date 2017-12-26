//
//  NSObject+RACSelectorSignal.m
//  ReactiveObjC
//
//  Created by Josh Abernathy on 3/18/13.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "NSObject+RACSelectorSignal.h"
#import "RACEXTRuntimeExtensions.h"
#import "NSInvocation+RACTypeParsing.h"
#import "NSObject+RACDeallocating.h"
#import "RACCompoundDisposable.h"
#import "RACDisposable.h"
#import "RACSubject.h"
#import "RACTuple.h"
#import "NSObject+RACDescription.h"
#import <objc/message.h>
#import <objc/runtime.h>

NSString * const RACSelectorSignalErrorDomain = @"RACSelectorSignalErrorDomain";
const NSInteger RACSelectorSignalErrorMethodSwizzlingRace = 1;

static NSString * const RACSignalForSelectorAliasPrefix = @"rac_alias_";
static NSString * const RACSubclassSuffix = @"_RACSelectorSignal";
static void *RACSubclassAssociationKey = &RACSubclassAssociationKey;

static NSMutableSet *swizzledClasses() {
	static NSMutableSet *set;
	static dispatch_once_t pred;
	
	dispatch_once(&pred, ^{
		set = [[NSMutableSet alloc] init];
	});

	return set;
}

/**
 为一个selector生成对应signal的步骤如下:
 
1 为self添加一个RACSubject类型的变量。这个就是rac_signalForSelector返回的signal。
  objc_setAssociatedObject(self, aliasSelector, subject, OBJC_ASSOCIATION_RETAIN);

2 为当前对象的类动态生成一个子类RACSubclass。（就叫这个名字吧）
 通过object_setClass(self, RACSubclass);修改self的isa指针，指向RACSubclass。
 在生成子类时需要考虑一些细节，比如对象已经使用object_setClass进行过类的替换等。具体请看RACSwizzleClass。
 
3 替换子类RACSubclass selector的实现为_objc_msgForward。
 调用rac_signalForSelector可以分为两种情况:
 (1).RACSubclass实现了Selector（也就RACSubclass的父类实现了Selector）， 然后调用rac_signalForSelector。这种情况下aliasSelector的实现为原来的实现，Selector的实现为_objc_msgForward。
 (2).RACSubclass没有实现Selector，然后调用rac_signalForSelector。这时aliasSelector的实现为null,Selector的实现为_objc_msgForward。
 
4 现在调用RACSubclass的selector就会进行转发。 调用methodSignatureForSelector和forwardInvocation方法。
  在创建子类RACSubclass时会Swizzle这两个方法。
 
5 RACSwizzleMethodSignatureForSelector（代码中有注释）
 
6 RACSwizzleForwardInvocation（代码中有注释）
 在这里信号sendNext
 
另外还有辅助方法：
RACSwizzleGetClass
当调用 [self class]要返回原来的类，不能是子类RACSubclass。欺骗调用方。
 */

@implementation NSObject (RACSelectorSignal)
- (RACSignal *)rac_signalForSelector:(SEL)selector {
    NSCParameterAssert(selector != NULL);
    
    return NSObjectRACSignalForSelector(self, selector, NULL);
}

- (RACSignal *)rac_signalForSelector:(SEL)selector fromProtocol:(Protocol *)protocol {
    NSCParameterAssert(selector != NULL);
    NSCParameterAssert(protocol != NULL);
    
    return NSObjectRACSignalForSelector(self, selector, protocol);
}

static RACSignal *NSObjectRACSignalForSelector(NSObject *self, SEL selector, Protocol *protocol) {
    SEL aliasSelector = RACAliasForSelector(selector);
    
    @synchronized (self) {
        //如果存在subject，直接返回
        RACSubject *subject = objc_getAssociatedObject(self, aliasSelector);
        if (subject != nil) return subject;
        
        
        //动态的生成一个子类
        Class class = RACSwizzleClass(self);
        NSCAssert(class != nil, @"Could not swizzle class of %@", self);
        
        
        subject = [[RACSubject subject] setNameWithFormat:@"%@ -rac_signalForSelector: %s", RACDescription(self), sel_getName(selector)];
        objc_setAssociatedObject(self, aliasSelector, subject, OBJC_ASSOCIATION_RETAIN);
        
        [self.rac_deallocDisposable addDisposable:[RACDisposable disposableWithBlock:^{
            [subject sendCompleted];
        }]];
        
        
        /**
         targetMethod == NULL
         selector ----> _objc_msgForward 当调用selector时直接调用forwardInvocation。
         targetMethod != NULL
         selector ----> _objc_msgForward
         aliasSelector ----> method_getImplementation(targetMethod)
         */
        Method targetMethod = class_getInstanceMethod(class, selector);
        if (targetMethod == NULL) {
            const char *typeEncoding;
            if (protocol == NULL) {
                typeEncoding = RACSignatureForUndefinedSelector(selector);
            } else {
                // Look for the selector as an optional instance method.
                struct objc_method_description methodDescription = protocol_getMethodDescription(protocol, selector, NO, YES);
                
                if (methodDescription.name == NULL) {
                    // Then fall back to looking for a required instance
                    // method.
                    methodDescription = protocol_getMethodDescription(protocol, selector, YES, YES);
                    NSCAssert(methodDescription.name != NULL, @"Selector %@ does not exist in <%s>", NSStringFromSelector(selector), protocol_getName(protocol));
                }
                typeEncoding = methodDescription.types;
            }
            
            RACCheckTypeEncoding(typeEncoding);
            
            // Define the selector to call -forwardInvocation:.
            if (!class_addMethod(class, selector, _objc_msgForward, typeEncoding)) {
                NSDictionary *userInfo = @{
                                           NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedString(@"A race condition occurred implementing %@ on class %@", nil), NSStringFromSelector(selector), class],
                                           NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Invoke -rac_signalForSelector: again to override the implementation.", nil)
                                           };
                return [RACSignal error:[NSError errorWithDomain:RACSelectorSignalErrorDomain code:RACSelectorSignalErrorMethodSwizzlingRace userInfo:userInfo]];
            }
        } else if (method_getImplementation(targetMethod) != _objc_msgForward) {
            // Make a method alias for the existing method implementation.
            const char *typeEncoding = method_getTypeEncoding(targetMethod);
            
            RACCheckTypeEncoding(typeEncoding);
            
            BOOL addedAlias __attribute__((unused)) = class_addMethod(class, aliasSelector, method_getImplementation(targetMethod), typeEncoding);
            NSCAssert(addedAlias, @"Original implementation for %@ is already copied to %@ on %@", NSStringFromSelector(selector), NSStringFromSelector(aliasSelector), class);
            
            // Redefine the selector to call -forwardInvocation:.
            class_replaceMethod(class, selector, _objc_msgForward, method_getTypeEncoding(targetMethod));
        }
        
        return subject;
    }
}

static Class RACSwizzleClass(NSObject *self) {
    Class statedClass = self.class;
    Class baseClass = object_getClass(self);
    
    // The "known dynamic subclass" is the subclass generated by RAC.
    // It's stored as an associated object on every instance that's already
    // been swizzled, so that even if something else swizzles the class of
    // this instance, we can still access the RAC generated subclass.
    Class knownDynamicSubclass = objc_getAssociatedObject(self, RACSubclassAssociationKey);
    if (knownDynamicSubclass != Nil) return knownDynamicSubclass;
    
    /**
     If the class is already lying about what it is, it's probably a KVO
     dynamic subclass or something else that we shouldn't subclass
     ourselves.
     
     Just swizzle -forwardInvocation: in-place. Since the object's class
     was almost certainly dynamically changed, we shouldn't see another of
     these classes in the hierarchy.
     
     Additionally, swizzle -respondsToSelector: because the default
     implementation may be ignorant of methods added to this class.
     
     如果statedClass != baseClass，证明已经动态生成了类（比如kvo）,这时我们没有必要再动态生成一个子类。
     只要swizzle -forwardInvocation: 和 respondsToSelector
     */
    NSString *className = NSStringFromClass(baseClass);
    if (statedClass != baseClass) {
        @synchronized (swizzledClasses()) {
            if (![swizzledClasses() containsObject:className]) {
                RACSwizzleForwardInvocation(baseClass);
                RACSwizzleRespondsToSelector(baseClass);
                RACSwizzleGetClass(baseClass, statedClass);
                RACSwizzleGetClass(object_getClass(baseClass), statedClass);
                RACSwizzleMethodSignatureForSelector(baseClass);
                [swizzledClasses() addObject:className];
            }
        }
        return baseClass;
    }
    
    const char *subclassName = [className stringByAppendingString:RACSubclassSuffix].UTF8String;
    
    //The Class object for the named class, or  nil if the class is not registered with the Objective-C runtime.
    Class subclass = objc_getClass(subclassName);
    
    if (subclass == nil) {
        //创建子类，类名为subclassName
        subclass = objc_allocateClassPair(baseClass, subclassName, 0);
        if (subclass == nil) return nil;
        
        RACSwizzleForwardInvocation(subclass);
        RACSwizzleRespondsToSelector(subclass);
        RACSwizzleGetClass(subclass, statedClass);
        RACSwizzleGetClass(object_getClass(subclass), statedClass);
        RACSwizzleMethodSignatureForSelector(subclass);
        objc_registerClassPair(subclass);
    }
    
    object_setClass(self, subclass);
    objc_setAssociatedObject(self, RACSubclassAssociationKey, subclass, OBJC_ASSOCIATION_ASSIGN);
    return subclass;
}

static void RACSwizzleMethodSignatureForSelector(Class class) {
    
    IMP newIMP = imp_implementationWithBlock(^(id self, SEL selector) {
        // Don't send the -class message to the receiver because we've changed that to return the original class.
        Class actualClass = object_getClass(self);
        Method method = class_getInstanceMethod(actualClass, selector);
        /**
          Messages that the original class dynamically implements fall here.
          Call the original class' -methodSignatureForSelector:.
          使用rac_signalForSelector操作过的方法一定是有实现的。method == NULL不是RAC导致的消息转发，交给父类处理。
         */
        if (method == NULL) {
            struct objc_super target = {
                .super_class = class_getSuperclass(class),
                .receiver = self,
            };
            NSMethodSignature * (*messageSend)(struct objc_super *, SEL, SEL) = (__typeof__(messageSend))objc_msgSendSuper;
            return messageSend(&target, @selector(methodSignatureForSelector:), selector);
        }
        
        /**
         这种情况selector对应的实现就是_objc_msgForward。
         */
        char const *encoding = method_getTypeEncoding(method);
        return [NSMethodSignature signatureWithObjCTypes:encoding];
    });
    
    //替换之
    SEL selector = @selector(methodSignatureForSelector:);
    Method methodSignatureForSelectorMethod = class_getInstanceMethod(class, selector);
    class_replaceMethod(class, selector, newIMP, method_getTypeEncoding(methodSignatureForSelectorMethod));
}

static BOOL RACForwardInvocation(id self, NSInvocation *invocation) {
    //如果原类有实现该方法，调用方法原来的实现
	SEL aliasSelector = RACAliasForSelector(invocation.selector);
	Class class = object_getClass(invocation.target);
    //这个respondsToAlias 保存方法原来的实现（如果有声明的话，在NSObjectRACSignalForSelector中指定的）
	BOOL respondsToAlias = [class instancesRespondToSelector:aliasSelector];
	if (respondsToAlias) {
		invocation.selector = aliasSelector;
		[invocation invoke];
	}

    //获取subject，并将参数发出去。
    RACSubject *subject = objc_getAssociatedObject(self, aliasSelector);
    if (subject == nil) {
       return respondsToAlias;
    }
	[subject sendNext:invocation.rac_argumentsTuple];
	return YES;
}

//替换某个类的forwardInvocation方法。
static void RACSwizzleForwardInvocation(Class class) {
	SEL forwardInvocationSEL = @selector(forwardInvocation:);
	Method forwardInvocationMethod = class_getInstanceMethod(class, forwardInvocationSEL);

	// Preserve any existing implementation of -forwardInvocation:.
	void (*originalForwardInvocation)(id, SEL, NSInvocation *) = NULL;
	if (forwardInvocationMethod != NULL) {
		originalForwardInvocation = (__typeof__(originalForwardInvocation))method_getImplementation(forwardInvocationMethod);
	}

	// Set up a new version of -forwardInvocation:.
	//
	// If the selector has been passed to -rac_signalForSelector:, invoke
	// the aliased method, and forward the arguments to any attached signals.
	//
	// If the selector has not been passed to -rac_signalForSelector:,
	// invoke any existing implementation of -forwardInvocation:. If there
	// was no existing implementation, throw an unrecognized selector
	// exception.
	id newForwardInvocation = ^(id self, NSInvocation *invocation) {
        /**
         处理完了，直接返回.
         调用原方法（如果有）
         信号发sendNext （如果有） ---> 返回yes.
         否则返回NO。
         */
		BOOL matched = RACForwardInvocation(self, invocation);
		if (matched) return;
        
		if (originalForwardInvocation == NULL) { //直接报错
			[self doesNotRecognizeSelector:invocation.selector];
		} else {
            //使用原forwardInvocation进行处理
			originalForwardInvocation(self, forwardInvocationSEL, invocation);
		}
	};

	class_replaceMethod(class, forwardInvocationSEL, imp_implementationWithBlock(newForwardInvocation), "v@:@");
}

static void RACSwizzleRespondsToSelector(Class class) {
	SEL respondsToSelectorSEL = @selector(respondsToSelector:);

	// Preserve existing implementation of -respondsToSelector:.
	Method respondsToSelectorMethod = class_getInstanceMethod(class, respondsToSelectorSEL);
	BOOL (*originalRespondsToSelector)(id, SEL, SEL) = (__typeof__(originalRespondsToSelector))method_getImplementation(respondsToSelectorMethod);

	// Set up a new version of -respondsToSelector: that returns YES for methods
	// added by -rac_signalForSelector:.
	//
	// If the selector has a method defined on the receiver's actual class, and
	// if that method's implementation is _objc_msgForward, then returns whether
	// the instance has a signal for the selector.
	// Otherwise, call the original -respondsToSelector:.
	id newRespondsToSelector = ^ BOOL (id self, SEL selector) {
        /**
         从当前类中获取,不去查询父类。
         */
		Method method = rac_getImmediateInstanceMethod(class, selector);

		if (method != NULL && method_getImplementation(method) == _objc_msgForward) {
			SEL aliasSelector = RACAliasForSelector(selector);
			if (objc_getAssociatedObject(self, aliasSelector) != nil) return YES;
		}

		return originalRespondsToSelector(self, respondsToSelectorSEL, selector);
	};

	class_replaceMethod(class, respondsToSelectorSEL, imp_implementationWithBlock(newRespondsToSelector), method_getTypeEncoding(respondsToSelectorMethod));
}

static void RACSwizzleGetClass(Class class, Class statedClass) {
	SEL selector = @selector(class);
	Method method = class_getInstanceMethod(class, selector);
	IMP newIMP = imp_implementationWithBlock(^(id self) {
		return statedClass;
	});
	class_replaceMethod(class, selector, newIMP, method_getTypeEncoding(method));
}


// It's hard to tell which struct return types use _objc_msgForward, and
// which use _objc_msgForward_stret instead, so just exclude all struct, array,
// union, complex and vector return types.
static void RACCheckTypeEncoding(const char *typeEncoding) {
#if !NS_BLOCK_ASSERTIONS
	// Some types, including vector types, are not encoded. In these cases the
	// signature starts with the size of the argument frame.
	NSCAssert(*typeEncoding < '1' || *typeEncoding > '9', @"unknown method return type not supported in type encoding: %s", typeEncoding);
	NSCAssert(strstr(typeEncoding, "(") != typeEncoding, @"union method return type not supported");
	NSCAssert(strstr(typeEncoding, "{") != typeEncoding, @"struct method return type not supported");
	NSCAssert(strstr(typeEncoding, "[") != typeEncoding, @"array method return type not supported");
	NSCAssert(strstr(typeEncoding, @encode(_Complex float)) != typeEncoding, @"complex float method return type not supported");
	NSCAssert(strstr(typeEncoding, @encode(_Complex double)) != typeEncoding, @"complex double method return type not supported");
	NSCAssert(strstr(typeEncoding, @encode(_Complex long double)) != typeEncoding, @"complex long double method return type not supported");

#endif // !NS_BLOCK_ASSERTIONS
}



//获取方法的别名。也就是在原方法名前面添加一个前缀rac_alias_。
static SEL RACAliasForSelector(SEL originalSelector) {
	NSString *selectorName = NSStringFromSelector(originalSelector);
	return NSSelectorFromString([RACSignalForSelectorAliasPrefix stringByAppendingString:selectorName]);
}


static const char *RACSignatureForUndefinedSelector(SEL selector) {
	const char *name = sel_getName(selector);
	NSMutableString *signature = [NSMutableString stringWithString:@"v@:"];

	while ((name = strchr(name, ':')) != NULL) {
		[signature appendString:@"@"];
		name++;
	}

	return signature.UTF8String;
}





@end
