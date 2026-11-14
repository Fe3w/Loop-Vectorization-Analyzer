#include <math.h>
void f(float *restrict a, const float *restrict b, int n) { for (int i = 0; i < n; i++) a[i] = sinf(b[i]); }
