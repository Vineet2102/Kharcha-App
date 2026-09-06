#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface permission_handler_apple_permission_handler_apple_SWIFTPM_MODULE_BUNDLER_FINDER : NSObject
@end

@implementation permission_handler_apple_permission_handler_apple_SWIFTPM_MODULE_BUNDLER_FINDER
@end

NSBundle* permission_handler_apple_permission_handler_apple_SWIFTPM_MODULE_BUNDLE() {
    NSString *bundleName = @"permission_handler_apple_permission_handler_apple";

    NSArray<NSURL*> *candidates = @[
        NSBundle.mainBundle.resourceURL,
        [NSBundle bundleForClass:[permission_handler_apple_permission_handler_apple_SWIFTPM_MODULE_BUNDLER_FINDER class]].resourceURL,
        NSBundle.mainBundle.bundleURL
    ];

    for (NSURL* candidate in candidates) {
        NSURL *bundlePath = [candidate URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.bundle", bundleName]];

        NSBundle *bundle = [NSBundle bundleWithURL:bundlePath];
        if (bundle != nil) {
            return bundle;
        }
    }

    @throw [[NSException alloc] initWithName:@"SwiftPMResourcesAccessor" reason:[NSString stringWithFormat:@"unable to find bundle named %@", bundleName] userInfo:nil];
}

NS_ASSUME_NONNULL_END