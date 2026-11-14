#define N 256
double aa[N][N], bb[N][N], cc[N][N];
void legal_swap(double A[restrict N][N], const double B[restrict N][N]) {
  for (int j = 0; j < N; j++)
    for (int i = 0; i < N; i++)
      A[i][j] = A[i][j] + B[i][j];
}
void skew(double A[N][N]) {
  for (int i = 1; i < N; i++)
    for (int j = 0; j < N - 1; j++)
      A[j][i] = A[j + 1][i - 1] + 1.0;
}
void rep(int reps) {
  for (int nl = 0; nl < reps; nl++)
    for (int j = 0; j < N; j++)
      for (int i = 0; i < N; i++)
        aa[i][j] = bb[i][j] + cc[i][j];
}
