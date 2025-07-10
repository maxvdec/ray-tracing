//
//  Shaders.metal
//  Ray Tracer
//
//  Created by Max Van den Eynde on 10/7/25.
//

#include <metal_stdlib>
#include "Definitions.h"
using namespace metal;

float3 ray_at(Ray r, float t) {
    return r.origin + t * r.direction;
}

float hitSphere(Sphere sph, Ray r) {
    float3 oc = sph.center - r.origin;
    auto a = dot(r.direction, r.direction);
    auto h = dot(r.direction, oc);
    auto c = dot(oc, oc) - sph.radius * sph.radius;
    auto discriminant = h * h - a * c;
    
    if (discriminant < 0) {
        return -1.0;
    } else {
        return (h - sqrt(discriminant)) / a;
    }
}

float4 color_ray(Ray r) {
    Sphere s;
    s.center = float3(0, 0, -1);
    s.radius = 0.5;
    
    float hitResult = hitSphere(s, r);
    if (hitResult > 0.0) {
        float3 N = normalize(ray_at(r, hitResult) - float3(0, 0, -1));
        return 0.5 * float4(N.x + 1, N.y + 1, N.z + 1, 1.0);
    }
    
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
