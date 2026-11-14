#include "polybench.h"
#include "alpha.h"
void alpha(float *restrict a, float *restrict b) {
  for (int i = 0; i < FAKE_N; i++)
    a[i] = b[i] + ALPHA;
}
#ifdef POLYBENCH_TIME
/* Like PolyBench with -DPOLYBENCH_TIME: run the kernel, print seconds on stdout. */
#include <stdio.h>
#include <time.h>
int main(void) {
  static float a[FAKE_N], b[FAKE_N];
  struct timespec t0, t1;
  clock_gettime(CLOCK_MONOTONIC, &t0);
  for (int r = 0; r < 1000; r++) alpha(a, b);
  clock_gettime(CLOCK_MONOTONIC, &t1);
  printf("%0.6f\n", (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9);
  return a[1] > 1e30f;
}
#endif
