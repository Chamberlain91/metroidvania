#include "oak.hlsli"

[[vk::push_constant]]
Line_Push_Constants push;

struct VertexOutput {
  float4 position : SV_POSITION;
  float4 color : COLOR;
};

Line_Instance get_line(int index) {
  return push.line_buffer.Get().lines[index];
}

VertexOutput main(int vertexIndex: SV_VertexID) {
  Line_Instance ln = get_line(vertexIndex / 2);

  float2 pos = ln.points[vertexIndex % 2];

  VertexOutput output;
  output.position = mul(push.camera_matrix, float4(pos, 0.0, 1.0));
  output.color = ln.color;

  return output;
}
