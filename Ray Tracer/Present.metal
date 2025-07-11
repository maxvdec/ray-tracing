//
//  Present.metal
//  Ray Tracer
//
//  Created by Max Van den Eynde on 10/7/25.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]]) {
    VertexOut out;
    
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    
    float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                              texture2d<float> colorTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::nearest, min_filter::nearest);
    
    return colorTexture.sample(textureSampler, in.texCoord);
}
