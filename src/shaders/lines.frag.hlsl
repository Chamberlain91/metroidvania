#include "oak.hlsli"

[[vk::push_constant]]
Line_Push_Constants push;

struct VertexOutput {
  float4 position : SV_POSITION;
  float4 color : COLOR;
};

float4 main(VertexOutput vertex) : SV_Target {
  return vertex.color;
}
