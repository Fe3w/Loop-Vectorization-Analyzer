void f(float *a, const float *b, const long *p, int n) { for (int i = 0; i < n; i++) a[p[i]] = b[i]; }
