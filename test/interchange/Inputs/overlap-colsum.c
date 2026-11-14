#include <stdio.h>
#define N 64
__attribute__((noinline))
void colsum(double A[N][N], double B[N][N]) {
  for (int j = 0; j < N; j++)
    for (int i = 0; i < N; i++)
      A[i][j] = A[i][j] + B[i][j];
}
static double buf[(N + 1) * N];
int main(void) {
  for (int k = 0; k < (N + 1) * N; k++)
    buf[k] = (double)(k % 7);
  /* B[i][j] == A[i+1][j-1]: B overlaps A, shifted by one row minus one element. */
  colsum((double (*)[N])buf, (double (*)[N])(buf + N - 1));
  double s = 0;
  for (int k = 0; k < N * N; k++)
    s += buf[k] * (double)(k % 13 + 1);
  printf("checksum=%.1f\n", s);
  return 0;
}
