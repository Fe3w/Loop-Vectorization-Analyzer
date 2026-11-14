static inline float scale(float x) { return 2.0f * x + 1.0f; }  /* fix: inline the callee */
void f(float *restrict a, const float *restrict b, int n) { for (int i = 0; i < n; i++) a[i] = scale(b[i]); }
