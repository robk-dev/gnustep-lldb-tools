// No platform headers: keep the compiler walkthrough independent of SDK paths.
__attribute__((objc_root_class))
@interface Counter
- (int)twice:(int)value;
@end
@implementation Counter
- (int)twice:(int)value { return value * 2; }
@end
int call(Counter *counter) { return [counter twice:21]; }
