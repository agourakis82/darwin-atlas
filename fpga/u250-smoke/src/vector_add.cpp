extern "C" void vector_add(
    const int* a,
    const int* b,
    int* out,
    unsigned int count) {
#pragma HLS INTERFACE m_axi port=a offset=slave bundle=gmem0
#pragma HLS INTERFACE m_axi port=b offset=slave bundle=gmem1
#pragma HLS INTERFACE m_axi port=out offset=slave bundle=gmem2
#pragma HLS INTERFACE s_axilite port=a bundle=control
#pragma HLS INTERFACE s_axilite port=b bundle=control
#pragma HLS INTERFACE s_axilite port=out bundle=control
#pragma HLS INTERFACE s_axilite port=count bundle=control
#pragma HLS INTERFACE s_axilite port=return bundle=control

vector_add_loop:
  for (unsigned int i = 0; i < count; ++i) {
#pragma HLS PIPELINE II=1
    out[i] = a[i] + b[i];
  }
}
