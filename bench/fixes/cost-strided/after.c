float A[256][256], B[256][256];
void f(int i) { for (int j = 0; j < 256; j++) A[i][j] = A[i][j] * B[i][j]; }  /* fix: interchange: walk rows */
