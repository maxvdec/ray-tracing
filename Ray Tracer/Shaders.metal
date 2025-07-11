//
//  Shaders.metal
//  Ray Tracer
//
//  Created by Max Van den Eynde on 10/7/25.
//

#include <metal_stdlib>
#include "Lib.metal"
using namespace metal;

bool hitSphere(Sphere s, Ray r, thread HitInfo& hit) {
    float3 oc = r.origin - s.center;
    auto a = dot(r.direction, r.direction);
    auto b = dot(oc, r.direction);
    auto c = dot(oc, oc) - s.radius * s.radius;
    
    auto discriminant = b * b - a * c;
    if (discriminant < 0) {
        return false;
    }
    
    if (a == 0) {
        return false;
    }
    
    auto sqrtd = sqrt(discriminant);
    
    auto root = (-b - sqrtd) / a;
    if (!r.distance.surrounds(root)) {
        root = (-b + sqrtd) / a;
        if (!r.distance.surrounds(root)) {
            return false;
        }
    }
    
    hit.distance = root;
    hit.point = r.at(root);
    float3 normals = (hit.point - s.center) / s.radius;
    hit.apply_normals(r, normals);
    
    return true;
}

bool world_hit(constant Object* objs, int objectCount, Ray r, thread HitInfo& hit) {
    HitInfo temp_hit;
    bool hit_anything = false;
    auto closest_so_far = r.distance.max;
    
    for (int i = 0; i < objectCount; ++i) {
        Object obj = objs[i];
        if (obj.type == TYPE_SPHERE && hitSphere(obj.s, r, temp_hit)) {
            if (temp_hit.distance < closest_so_far) {
                hit_anything = true;
                closest_so_far = temp_hit.distance;
                hit = temp_hit;
            }
        }
    }
    
    return hit_anything;
}

float4 color_ray(constant Object *objs, int objectCount, Ray r, thread float2& seed, int depth) {
    if (depth <= 0) {
        return float4(0, 0, 0, 1);
    }
    
    HitInfo info;
    if (world_hit(objs, objectCount, r, info)) {
        float3 direction = random_on_hemisphere(info.normal, seed);
        Ray nRay;
        nRay.origin = info.point;
        nRay.direction = direction;
        nRay.distance = {0.001, 1000};
        return float4(0.7 * color_ray(objs, objectCount, nRay, seed, depth - 1));
    }
    
    float3 unitDirection = normalize(r.direction);
    auto a = 0.5 * (unitDirection.y + 1.0);
    auto result = (1.0 - a) * float3(1.0, 1.0, 1.0) + a * float3(0.5, 0.7, 1.0);
    return float4(result, 1.0);
}

void write_color(texture2d<float, access::write> texture, uint2 pos, float4 color) {
    Interval i = {0, 1};
    float r = i.clamp(color.r);
    float g = i.clamp(color.g);
    float b = i.clamp(color.b);
    float a = i.clamp(color.a);
    float4 result = float4(r, g, b, a);
    texture.write(result, pos);
}

kernel void computeShader(texture2d<float, access::write> outputTexture [[texture(0)]],
                         constant Uniforms& uniforms [[buffer(0)]],
                         constant Object* objs [[buffer(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
    
    uint width = outputTexture.get_width();
    uint height = outputTexture.get_height();
    
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    float2 pixel = float2(gid.x, gid.y);
    
    float4 color = float4(0, 0, 0, 1.0);
    
    float2 seed = float2(
        float(gid.x) * 12.9898 + float(gid.y) * 78.233 + float(height) * 37.719,
        float(gid.y) * 39.346 + float(width) * 11.135 + uniforms.time * 0.1
    );
    
    for (int sample = 0; sample < uniforms.sampleCount; ++sample) {
        Ray r = getRay(pixel.x, pixel.y, uniforms, seed);
        color += color_ray(objs, uniforms.objCount, r, seed, uniforms.maxRayDepth);
    }
    
    color *= uniforms.pixelSampleScale;
    
    write_color(outputTexture, gid, color);
}
