// Don't include Foundation directly - use the fix header
#import <Foundation/Foundation.h>

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSString *greeting = @"Hello";
    NSArray *fruits = @[ @"apple", @"banana" ];
    
    // Create dictionary using literal syntax (this should work)
    NSDictionary *personInfo = @{
      @"name" : @"John Doe",
      @"age" : @30,  // NSNumber literal should work
      @"skills" : @[ @"Objective-C", @"Swift" ]
    };
    
    // Breakpoint here
    NSLog(@"Testing: %@ and %@", greeting, fruits);
    return 0;
  }
}