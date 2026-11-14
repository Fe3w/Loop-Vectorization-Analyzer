float f(const float *a, int n) { float s = 1; for (int i = 0; i < n; i++) s = s * s + a[i]; return s; }
