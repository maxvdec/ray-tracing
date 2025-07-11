//
//  Shaders.metal
//  Ray Tracer
//
//  Created by Max Van den Eynde on 10/7/25.
//

#include <metal_stdlib>
#include "Definitions.h"
using namespace metal;

struct Interval {
    float max;
    float min;
    
    float span() {
        return max - min;
    }
    
    bool contains(float x) {
        return min <= x && x <= max;
    }
    
    bool surrounds(float x) {
        return min < x && max > x;
    }
    
    float clamp(float x) {
        return metal::clamp(x, min, max);
    }
};

struct Ray {
    float3 direction;
    float3 origin;
    
    Interval distance = { 1000, 0.001 };
    
    float3 at(float t) {
        return origin + t * direction;
    }
};

struct HitInfo {
    float3 point;
    float3 normal;
    float distance;
    bool hit_front;
    
    void apply_normals(Ray r, float3 outward_normals) {
        hit_front = dot(r.direction, outward_normals) < 0;
        normal = hit_front ? outward_normals : -outward_normals;
    }
};

float random_double(float2 seed) {
    return fract(sin(dot(seed, float2(12.9898, 78.233))) * 43758.5453123);
}

float random_in_range(Interval interval, float2 seed) {
    return interval.min + (interval.max - interval.min) * random_double(seed);
}

float3 random_square(float2 seed) {
    float x = random_double(seed) - 0.5;
    float y = random_double(seed + float2(37.719, 11.135)) - 0.5;
    return float3(x, y, 0.0);
}

bool hitSphere(Sphere s, Ray r, thread HitInfo& hit) {
    float3 oc = s.center - r.origin;
    auto a = dot(r.direction, r.direction);
    auto h = dot(r.direction, oc);
    auto c = dot(oc, oc) - s.radius * s.radius;
    
    auto discriminant = h * h - a * c;
    if (discriminant < 0) {
        return false;
    }
    
    auto sqrtd = sqrt(discriminant);
    
    auto root = (h - sqrtd) / a;
    if (!r.distance.surrounds(root)) {
        root = (h + sqrtd) / a;
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

float4 color_ray(constant Object *objs, int objectCount, Ray r) {
    HitInfo info;
    if (world_hit(objs, objectCount, r, info)) {
        return float4(0.5 * (info.normal + float3(1, 1, 1)), 1.0);
    }
    
    float3 unitDirection = normalize(r.direction);
    auto a = 0.5 * (unitDirection.y + 1.0);
    auto result = (1.0 - a) * float3(1.0, 1.0, 1.0) + a * float3(0.5, 0.7, 1.0);
    return float4(result, 1.0);
}

void write_color(texture2d<float, access::write> texture, uint2 pos, float4 color) {
    Interval i = {1, 0};
    float r = i.clamp(color.r);
    float g = i.clamp(color.g);
    float b = i.clamp(color.b);
    float a = i.clamp(color.a);
    float4 result = float4(r, g, b, a);
    texture.write(result, pos);
}

Ray getRay(int i, int j, Uniforms uniforms, float2 seed) {
    float3 offset = random_square(seed);
    auto pixel_sample = uniforms.pixelOrigin + ((i + offset.x) * uniforms.pixelDeltaX) + ((j + offset.y) * uniforms.pixelDeltaY);
    auto ray_origin = uniforms.cameraCenter;
    auto ray_dir = pixel_sample - ray_origin;
    
    return {ray_dir, ray_origin};
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
    
    for (int sample = 0; sample < uniforms.sampleCount; ++sample) {
        float2 seed = float2(
            float(gid.x) * 12.9898 + float(gid.y) * 78.233 + float(sample) * 37.719,
            float(gid.y) * 39.346 + float(sample) * 11.135 + uniforms.time * 0.1
        );
        
        Ray r = getRay(pixel.x, pixel.y, uniforms, seed);
        color += color_ray(objs, uniforms.objCount, r);
    }
    
    color *= uniforms.pixelSampleScale;
    
    write_color(outputTexture, gid, color);
}
