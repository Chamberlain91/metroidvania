#include "oak.hlsli"

[[vk::push_constant]]
Sprite_Push_Constants push;

struct VertexOutput {
  float4 position : SV_POSITION;
  float2 uv       : UV;
  int    image    : IMAGE_INDEX;
};

static float2 offsets[6] = {
  float2(0.0, 0.0), // 0
  float2(1.0, 0.0), // 1
  float2(1.0, 1.0), // 2
  float2(0.0, 0.0), // 0
  float2(1.0, 1.0), // 2
  float2(0.0, 1.0), // 3
};

Sprite_Instance get_sprite(int index) {
  return push.sprite_buffer.Get().sprites[index];
}

VertexOutput main(int vertexIndex : SV_VertexID) {

  Sprite_Instance sprite = get_sprite(vertexIndex / 6);
  
  // Computes the vertices of the sprite quad.
  float2 uv  = offsets[vertexIndex % 6];
  float2 pos = sprite.rect.xy + (uv * sprite.rect.zw);

  VertexOutput output;
  output.position = mul(push.camera_matrix, float4(pos, 0.0, 1.0));
  output.uv       = uv;
  output.image    = sprite.image;

  return output;
}
