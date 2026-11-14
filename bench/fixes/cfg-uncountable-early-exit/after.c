int f(const int *a, int n, int k) {  /* fix: drop the early exit; the first match is the minimum matching index */
  int r = n;
  for (int i = 0; i < n; i++) { int c = a[i] == k ? i : n; r = c < r ? c : r; }
  return r == n ? -1 : r; }
