#import <Foundation/Foundation.h>
int main(void) {
  @autoreleasepool {
    NSArray *items = @[@"apple", @"banana", @"cherry"];
    NSNumber *number = @42;
    NSString *text = [items objectAtIndex:1]; // FOUNDATION_STOP
    NSLog(@"%@ %@", text, number);
    @try {
      [NSException raise:@"LessonException" format:@"An intentional teaching exception"];
    } @catch (NSException *exception) {
      NSLog(@"Caught %@", [exception name]);
    }
  }
  return 0;
}
