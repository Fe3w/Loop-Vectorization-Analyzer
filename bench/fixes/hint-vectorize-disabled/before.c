void f(float *restrict a, const float *restrict b, int n) {
#pragma clang loop vectorize(disable)
  for (int i = 0; i < n; i++) a[i] = b[i] + 1.0f; }
