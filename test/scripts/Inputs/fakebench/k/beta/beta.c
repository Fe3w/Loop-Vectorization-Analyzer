#include "polybench.h"
float beta(float *a) {
  float s = 0;
  for (int i = 0; i < FAKE_N; i++)
    s += a[i];
  return s;
}
#ifdef POLYBENCH_TIME
#include <stdio.h>
#include <time.h>
int main(void) {
  static float a[FAKE_N];
  struct timespec t0, t1;
  float s = 0;
  clock_gettime(CLOCK_MONOTONIC, &t0);
  for (int r = 0; r < 1000; r++) s += beta(a);
  clock_gettime(CLOCK_MONOTONIC, &t1);
  printf("%0.6f\n", (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9);
  return s > 1e30f;
}
#endif
