#include <math.h>
void f(float *a, int n) {  /* fix: call unconditionally (safe: argument is never negative), select */
  for (int i = 0; i < n; i++) { float t = sqrtf(fabsf(a[i])); a[i] = a[i] < 0 ? t : a[i]; } }
