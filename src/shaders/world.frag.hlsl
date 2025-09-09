#include "oak.hlsli"

[[vk::push_constant]]
Sprite_Push_Constants push;

struct VertexOutput {
  float4 position : SV_POSITION;
  float2 uv : UV;
  int image : IMAGE_INDEX;
};

float4 main(VertexOutput vertex) : SV_Target {
  Texture2D tex = getTexture2D(vertex.image);
  SamplerState ss = getSamplerState(0);
  return tex.Sample(ss, vertex.uv);
}
