//
//  Shaders.metal
//  Ray Tracer
//
//  Created by Max Van den Eynde on 10/7/25.
//

#include <metal_stdlib>
#include "Definitions.h"
using namespace metal;

kernel void computeShader(texture2d<float, access::write> outputTexture [[texture(0)]],
                         constant Uniforms& uniforms [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    
    uint width = outputTexture.get_width();
    uint height = outputTexture.get_height();
    
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    
    float2 uv = float2(gid) / float2(width, height);
    
    float4 color = float4(uv.x, uv.y, 0.0, 1.0);
    outputTexture.write(color, gid);
}
