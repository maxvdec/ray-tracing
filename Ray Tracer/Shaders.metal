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
        return min <= x && x >= max;
    }
    
    bool surrounds(float x) {
        return min < x && max > x;
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

/// Mapped from 0 to 1
float random_double(float seed) {
    return fract(sin(seed) * 43758.5453123);
}

float random_in_range(Interval interval, float seed) {
    return interval.min + (interval.max - interval.min) * random_double(seed);
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


kernel void computeShader(texture2d<float, access::write> outputTexture [[texture(0)]],
                         constant Uniforms& uniforms [[buffer(0)]],
                         constant Object* objs [[buffer(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
    
    float seed = float(gid.x) * 12.9898 + float(gid.y) * 78.233;
    
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
    
    outputTexture.write(color_ray(objs, uniforms.objCount, r), gid);
}
