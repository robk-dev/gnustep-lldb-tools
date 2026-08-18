// gnustep-base defines _NSPrintForDebugger (Source/NSDebug.m) but does not
// dllexport it on Windows MSVC, so the debugger cannot resolve it in the DLL
// and `po` has nothing to call. Defining it in the app makes it visible in
// the executable's symbol table; the body mirrors NSDebug.m.
#import <Foundation/Foundation.h>

const char *_NSPrintForDebugger(id object) {
  if (object && [object respondsToSelector:@selector(description)])
    return [[object description] UTF8String];

  return NULL;
}
