void f(float *restrict a, const float *restrict b, const int *restrict idx, int n) { for (int i = 0; i < n; i++) a[i] = b[idx[i]]; }
