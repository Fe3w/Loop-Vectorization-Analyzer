int f(const int *a, int n) {  /* fix: bound the loop by a known length, count the matches */
  int c = 0; for (int i = 0; i < n; i++) c += a[i] != 0; return c; }
