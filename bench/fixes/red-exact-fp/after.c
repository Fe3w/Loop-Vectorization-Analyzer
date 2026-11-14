float f(const float *a, int n) { float s = 0;
#pragma clang loop vectorize(enable)
  for (int i = 0; i < n; i++) s += a[i]; return s; }
