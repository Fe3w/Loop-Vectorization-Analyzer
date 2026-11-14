#include <math.h>
void f(float *a, int n) { for (int i = 0; i < n; i++) if (a[i] < 0) a[i] = sqrtf(-a[i]); }
