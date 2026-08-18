// Bare-libobjc2 debugging demo for the GNUstep LLDB plugin.
//
// Builds against libobjc2 alone - no gnustep-base - so it works with just
// <prefix>/lib/objc.dll (Windows) or libobjc.so (Linux). The class shapes are
// modeled on the LLDB Shell tests this plugin ships with
// (llvm-project/lldb/test/Shell/Expr/objc-gnustep-{dynamic-types,print,
// tagged-pointers,stepping}.m), so everything those tests validate can be
// explored interactively here:
//
//   * dynamic types:   `frame variable -d run-target shape` shows the derived
//                      class, not the static Shape type
//   * po:              works via the _NSPrintForDebugger below
//   * expressions:     `expr (double)[shapes[0] area]`
//   * stepping:        `step` at a message send lands in the method
//   * tagged pointers: `frame variable -d run-target tiny`
//
// Build: demos/build.ps1 (Windows) or make -C demos (Linux).

#import "objc/runtime.h"
#include <stdio.h>

@protocol NSCoding
@end

#ifdef __has_attribute
#if __has_attribute(objc_root_class)
__attribute__((objc_root_class))
#endif
#endif
@interface NSObject <NSCoding> {
  id isa;
  int refcount;
}
+ (id)new;
@end
@implementation NSObject
+ (id)new {
  return class_createInstance(self, 0);
}
@end

@interface Shape : NSObject {
  int sides;
  double scale;
}
+ (id)newWithScale:(double)s;
- (double)area;
- (const char *)kindName;
@end

@implementation Shape
+ (id)newWithScale:(double)s {
  Shape *shape = [self new];
  shape->scale = s;
  return shape;
}
- (double)area {
  return 0.0;
}
- (const char *)kindName {
  return "shape";
}
@end

@interface Square : Shape
@end
@implementation Square
+ (id)newWithScale:(double)s {
  Square *sq = [super newWithScale:s];
  sq->sides = 4;
  return sq;
}
- (double)area {
  return scale * scale;
}
- (const char *)kindName {
  return "square";
}
@end

@interface Circle : Shape
@end
@implementation Circle
+ (id)newWithScale:(double)s {
  Circle *c = [super newWithScale:s];
  c->sides = 0;
  return c;
}
- (double)area {
  return 3.14159265358979 * scale * scale;
}
- (const char *)kindName {
  return "circle";
}
@end

// A libobjc2 "small object" class: pointers with low tag bits set carry their
// value inline; the class comes from the runtime's small-object table.
@interface TinyInt : NSObject
@end
@implementation TinyInt
@end

// gnustep-base normally provides this (Source/NSDebug.m); against the bare
// runtime we supply it ourselves so LLDB's `po` has something to call.
const char *_NSPrintForDebugger(id object) {
  static char buf[128];
  if (!object)
    return "<nil>";
  snprintf(buf, sizeof(buf), "<%s: %p>", object_getClassName(object),
           (void *)object);
  return buf;
}

int main(void) {
  objc_registerSmallObjectClass_np(objc_getClass("TinyInt"), 1);

  // Static type Shape everywhere; dynamic types differ per element.
  Shape *shapes[3];
  shapes[0] = [Square newWithScale:2.0];
  shapes[1] = [Circle newWithScale:1.0];
  shapes[2] = [Shape newWithScale:5.0];

  // 42 in the tag-1 slot registered above.
  id tiny = (id)(unsigned long long)((42 << 3) | 1);

  double total = 0.0;
  for (int i = 0; i < 3; i++) {
    Shape *shape = shapes[i];
    double a = [shape area]; // break here: step into the dispatch
    printf("%s area = %f\n", [shape kindName], a);
    total += a;
  }

  printf("total = %f, tiny = %p\n", total, (void *)tiny); // break here: inspect
  return total < 0.0;
}
