void f(float *a, const float *b, const long *p, int n) {
#pragma clang loop vectorize(assume_safety)
  for (int i = 0; i < n; i++) a[p[i]] = b[i]; }
