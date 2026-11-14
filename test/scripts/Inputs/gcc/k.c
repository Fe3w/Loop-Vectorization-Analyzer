float sum(const float *a, int n) {
  float s = 0;
  for (int i = 0; i < n; i++)
    s += a[i];
  return s;
}
void copy(float *restrict a, const float *restrict b, int n) {
  for (int i = 0; i < n; i++)
    a[i] = b[i] + 1.0f;
}
float ext(float);
void calls(float *restrict a, const float *restrict b, int n) {
  for (int i = 0; i < n; i++)
    a[i] = ext(b[i]);
}
