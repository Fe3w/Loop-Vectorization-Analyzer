void f(float *a, int n) { for (int i = 8; i < n; i++) a[i] = a[i - 8] * 2.0f; }  /* fix: distance >= vector length */
