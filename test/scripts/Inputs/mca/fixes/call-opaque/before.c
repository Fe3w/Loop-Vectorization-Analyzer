float scale(float);
void f(float *restrict a, const float *restrict b, int n) { for (int i = 0; i < n; i++) a[i] = scale(b[i]); }
