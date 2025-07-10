//
//  Shaders.metal
//  Ray Tracer
//
//  Created by Max Van den Eynde on 10/7/25.
//

#include <metal_stdlib>
#include "Definitions.h"
using namespace metal;

float4 color_ray(Ray r) {
    float3 unitDirection = normalize(r.direction);
    auto a = 0.5 * (unitDirection.y + 1.0);
    auto result = (1.0 - a) * float3(1.0, 1.0, 1.0) + a * float3(0.5, 0.7, 1.0);
    return float4(result, 1.0);
}

kernel void computeShader(texture2d<float, access::write> outputTexture [[texture(0)]],
                         constant Uniforms& uniforms [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    
    uint width = outputTexture.get_width();
    uint height = outputTexture.get_height();
    
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    float2 pixel = float2(gid.x, gid.y);
    
    float3 pixelCenter = uniforms.pixelOrigin +
                        pixel.x * uniforms.pixelDeltaX +
                        pixel.y * uniforms.pixelDeltaY;
    
    float3 ray_dir = normalize(pixelCenter - uniforms.cameraCenter);
    
    Ray r;
    r.origin = uniforms.cameraCenter;
    r.direction = ray_dir;
    
    outputTexture.write(color_ray(r), gid);
}
