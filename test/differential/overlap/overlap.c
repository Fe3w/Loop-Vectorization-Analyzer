// Overlap driver for looplens-repair (S24). Each kernel accumulates into one
// element of an array while reading ranges of the SAME array, so the repair
// versions it. main() places the accumulator before, at the start of, inside, at
// the end of, just past and far from the ranges read: calls where it lies inside
// a range must take the original (slow) copy, the others the promoted (fast) copy.
// Results are printed exactly (%a). See overlap.test.
#include <stdio.h>

#define LEN 512

// cholesky / lu shape: acc -= x[k] * y[k], two unit-stride ranges.
__attribute__((noinline)) void k_dot(double *A, long r, long c1, long c2, long n) {
  for (long k = 0; k < n; k++)
    A[r] -= A[c1 + k] * A[c2 + k];
}

// flat accumulator, one range (test/repair/differential.ll shape).
__attribute__((noinline)) void k_sum(double *A, long r, long c, long n) {
  for (long k = 0; k < n; k++)
    A[r] += A[c + k];
}

// trmm shape: both reads strided (column walks).
__attribute__((noinline)) void k_col(double *A, long r, long c1, long c2, long n) {
  for (long k = 0; k < n; k++)
    A[r] += A[c1 + 7 * k] * A[c2 + 7 * k];
}

// nussinov shape: integer max of the accumulator and a sum of two reads.
__attribute__((noinline)) void k_max(int *T, long r, long c1, long c2, long n) {
  for (long k = 0; k < n; k++) {
    int v = T[c1 + k] + T[c2 + 3 * k];
    T[r] = T[r] >= v ? T[r] : v;
  }
}

static double A[LEN];
static int T[LEN];

static void reset(void) {
  for (int i = 0; i < LEN; i++) {
    A[i] = (double)((i * 37) % 101) / 16.0 - 2.5;
    T[i] = (i * 53) % 97 - 40;
  }
}

static void dump(const char *name, long r) {
  double s = 0.0;
  long t = 0;
  for (int i = 0; i < LEN; i++) {
    s += A[i] * (double)(i % 13 + 1);
    t += (long)T[i] * (i % 11 + 1);
  }
  printf("%s r=%ld A[r]=%a T[r]=%d sumA=%a sumT=%ld\n", name, r, A[r], T[r], s, t);
}

int main(void) {
  const long n = 40, c1 = 100, c2 = 300;
  // Accumulator positions relative to the first range [c1, c1+n):
  // one before, first element, inside, last element, one past, far away;
  // then the same for the second range [c2, c2+n) (a partial overlap of "the
  // set of ranges": inside one, outside the other).
  const long rs[] = {c1 - 1, c1, c1 + n / 2, c1 + n - 1, c1 + n, 50,
                     c2 - 1, c2, c2 + n / 2, c2 + n - 1, c2 + n, 480};
  for (unsigned i = 0; i < sizeof rs / sizeof rs[0]; i++) {
    long r = rs[i];
    reset(); k_dot(A, r, c1, c2, n); dump("dot", r);
    reset(); k_sum(A, r, c1, n);     dump("sum", r);
    reset(); k_col(A, r, c1, c2, n); dump("col", r);   // reads c + 7k, k < 40
    reset(); k_max(T, r, c1, c2, n); dump("max", r);
  }
  // Two ranges that overlap each other, accumulator inside their overlap and outside.
  reset(); k_dot(A, 110, 100, 105, n); dump("dot-ranges-overlap-in", 110);
  reset(); k_dot(A, 20, 100, 105, n);  dump("dot-ranges-overlap-out", 20);
  return 0;
}
