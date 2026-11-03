#include <stdio.h>
int total(const int *values, int count) {
  int result = 0;
  // Intentional logic bug: skips the final item. Predict before stepping.
  for (int i = 0; i < count - 1; ++i)
    result += values[i];
  return result;
}
int main(void) {
  int marks[] = {10, 20, 30};
  int actual = total(marks, 3);
  printf("Expected 60, got %d\n", actual);
  return 0;
}
