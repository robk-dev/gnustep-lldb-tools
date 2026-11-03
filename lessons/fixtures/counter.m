// Teaching fixture: deliberately small; no Foundation dependency.
#import <objc/runtime.h>
#include <stdio.h>
@protocol NSCoding @end
__attribute__((objc_root_class))
@interface LessonObject <NSCoding> { id isa; }
+ (id)new;
@end
@implementation LessonObject
+ (id)new { return class_createInstance(self, 0); }
@end
@interface LessonText : LessonObject
- (const char *)UTF8String;
@end
@implementation LessonText
- (const char *)UTF8String { return "Counter ready"; }
@end
@interface Counter : LessonObject {
@public
  int before;
  __int128 aligned;
  int after;
}
- (int)twice:(int)value;
- (id)description;
@end
@implementation Counter
- (int)twice:(int)value {
  return value * 2; // METHOD_BODY
}
- (id)description { return [LessonText new]; }
@end
int main(void) {
  Counter *counter = [Counter new];
  counter->before = 1;
  counter->aligned = 42;
  counter->after = 3;
  id object = counter;
  int answer = [counter twice:21]; // LESSON_STOP
  printf("answer = %d\n", answer); // LESSON_RESULT
  return answer == 42 && object != 0 ? 0 : 1;
}
