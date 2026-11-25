//
//  TileShaders.metal
//  RagnarokShaders
//
//  Created by Leon Li on 2026/3/23.
//

#include <metal_stdlib>
using namespace metal;

#include "TileShaderTypes.h"

typedef struct {
    float4 position [[position]];
    float fogDepth;
} RasterizerData;

vertex RasterizerData
tileVertexShader(const device TileVertex *vertices [[buffer(0)]],
                 unsigned int vertexIndex [[vertex_id]],
                 constant TileVertexUniforms &uniforms [[buffer(1)]])
{
    TileVertex in = vertices[vertexIndex];

    float4 viewPosition = uniforms.viewMatrix * uniforms.modelMatrix * float4(in.position, 1.0);

    RasterizerData out;
    out.position = uniforms.projectionMatrix * viewPosition;
    out.fogDepth = -viewPosition.z;
    return out;
}

fragment float4
tileFragmentShader(RasterizerData in [[stage_in]],
                   constant TileFragmentUniforms &uniforms [[buffer(0)]])
{
    float4 color = uniforms.color;

    if (uniforms.fogUse) {
        float fogAmount = smoothstep(uniforms.fogNear, uniforms.fogFar, in.fogDepth);
        color.rgb = mix(color.rgb, uniforms.fogColor, fogAmount);
    }

    return color;
}

// Native ground navigation marker; skin loaded from the user's GRF at runtime.
struct NavigationRaster {
    float4 position [[position]];
    float2 uv;
    float fogDepth;
};
vertex NavigationRaster navigationVertexShader(const device TileVertex *vertices [[buffer(0)]],
    constant TileVertexUniforms &uniforms [[buffer(1)]], const device float2 *uvs [[buffer(2)]],
    unsigned int index [[vertex_id]]) {
    float4 view = uniforms.viewMatrix * uniforms.modelMatrix * float4(vertices[index].position, 1);
    return { uniforms.projectionMatrix * view, uvs[index], -view.z };
}
fragment float4 navigationFragmentShader(NavigationRaster in [[stage_in]],
    constant TileFragmentUniforms &uniforms [[buffer(0)]], constant int &textured [[buffer(1)]],
    texture2d<float> skin [[texture(0)]]) {
    constexpr sampler sample(filter::linear, address::clamp_to_edge);
    float4 color;
    if (textured) { color = skin.sample(sample, in.uv); }
    else {
        float2 p = float2(in.uv.x * 2 - 1, 1 - in.uv.y * 2);
        bool shaft = abs(p.x) <= 0.17 && p.y >= -0.80 && p.y <= 0.16;
        bool head = p.y >= 0.02 && p.y <= 0.86 && abs(p.x) <= 0.58 * (0.86 - p.y) / 0.84;
        bool edge = (abs(p.x) <= 0.23 && p.y >= -0.86 && p.y <= 0.22) ||
            (p.y >= -0.04 && p.y <= 0.92 && abs(p.x) <= 0.64 * (0.92 - p.y) / 0.96);
        if (!shaft && !head && !edge) discard_fragment();
        color = shaft || head ? float4(1, 0.86, 0.1, 0.95) : float4(0.20, 0.12, 0, 0.95);
    }
    if (color.a < 0.025) discard_fragment();
    if (uniforms.fogUse) color.rgb = mix(color.rgb, uniforms.fogColor, smoothstep(uniforms.fogNear, uniforms.fogFar, in.fogDepth));
    return color;
}
