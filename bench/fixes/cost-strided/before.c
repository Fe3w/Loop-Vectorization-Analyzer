float A[256][256], B[256][256];
void f(int j) { for (int i = 0; i < 256; i++) A[i][j] = A[i][j] * B[i][j]; }
