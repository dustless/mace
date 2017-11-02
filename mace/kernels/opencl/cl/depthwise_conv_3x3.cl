inline float4 conv1x3(const float *input_ptr,
                      const float *filter_ptr) {
  float8 input = vload8(0, input_ptr);
  float4 row0 = convert_float4(input.s0123);
  float4 row1 = convert_float4(input.s1234);
  float4 row2 = convert_float4(input.s2345);
  return (float4)filter_ptr[0] * row0 + (float4)filter_ptr[1] * row1
            + (float4)filter_ptr[2] * row2;
}

inline float4 conv3x3x4(const float *input_ptr,
                        const float *filter_ptr,
                        const int row_width) {
  float4 res;
  res = conv1x3(input_ptr + 0 * row_width, filter_ptr + 0 * 3);
  res += conv1x3(input_ptr + 1 * row_width, filter_ptr + 1 * 3);
  res += conv1x3(input_ptr + 2 * row_width, filter_ptr + 2 * 3);

  return res;
}

inline float conv3x3(const float *input_ptr,
                     const float *filter_ptr,
                     const int row_width) {
  float res = input_ptr[0] * filter_ptr[0] + input_ptr[1] * filter_ptr[1] + input_ptr[2] * filter_ptr[2];
  input_ptr += row_width;
  filter_ptr += 3;
  res += input_ptr[0] * filter_ptr[0] + input_ptr[1] * filter_ptr[1] + input_ptr[2] * filter_ptr[2];
  input_ptr += row_width;
  filter_ptr += 3;
  res += input_ptr[0] * filter_ptr[0] + input_ptr[1] * filter_ptr[1] + input_ptr[2] * filter_ptr[2];

  return res;
}

void kernel depthwise_conv_3x3_s1(global const float *input, /* n, c, h, w */
                                  global const float *filter, /* m, i, kh, kw */
                                  global const float *bias, /* o */
                                  global float *output, /* n, c, h, w */
                                  private const int in_chan_num,
                                  private const int out_chan_num,
                                  private const int in_height,
                                  private const int in_width,
                                  private const int out_height,
                                  private const int out_width) {
  int batch = get_global_id(0);
  int out_chan_blk = get_global_id(1);
  int out_pixel_blk = get_global_id(2);

  const int in_pixel = in_height * in_width;
  const int out_pixel = out_height * out_width;
  const int multiplier = out_chan_num / in_chan_num;

  const int round_out_width = (out_width + 3) / 4;
  const int out_pixel_height = out_pixel_blk / round_out_width;
  const int out_pixel_width = out_pixel_blk % round_out_width;

  const int out_chan_begin = out_chan_blk * 4;
  const int out_chan_end = min(out_chan_begin + 4, out_chan_num);
  const int out_pixel_begin = out_pixel_height * out_width + out_pixel_width * 4;
  const int out_pixel_end = min(out_pixel_begin + 4, (out_pixel_height + 1) * out_width);
  const int in_pixel_begin = out_pixel_height * in_width + out_pixel_width * 4;

  const int in_offset = batch * in_chan_num * in_pixel;
  const int out_offset = batch * out_chan_num * out_pixel;
  const float *input_base = input + in_offset + in_pixel_begin;
  float *output_base = output + out_offset + out_pixel_begin;

  int pixels = out_pixel_end - out_pixel_begin;

  for (int i = out_chan_begin; i < out_chan_end; ++i) {
    float bias_value = bias[i];
    const float *input_ptr = input_base + (i / multiplier) * in_pixel;
    const float *filter_ptr = filter + i * 9;
    float *output_ptr = output_base + i * out_pixel;
    if (pixels < 4) {
      for (int out_idx = 0; out_idx < pixels; ++out_idx) {
        output_ptr[out_idx] = bias_value;
        output_ptr[out_idx] += conv3x3(input_ptr, filter_ptr, in_width);
        input_ptr += 1;
      }
    } else {
      float4 res = conv3x3x4(input_ptr, filter_ptr, in_width);
      res += (float4)bias_value;
      vstore4(res, 0, output_ptr);
    }
  }

}