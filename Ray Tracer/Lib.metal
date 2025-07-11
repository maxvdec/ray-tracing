//
//  Lib.metal
//  Ray Tracer
//
//  Created by Max Van den Eynde on 11/7/25.
//

#include <metal_stdlib>
#include "Definitions.h"
using namespace metal;

struct Interval {
    float min;
    float max;
    
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
    
    Interval distance = { 0.001, 1000 };
    
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

float random_double(thread float2& seed) {
    seed = fract(sin(seed * float2(12.9898, 78.233)) * 43758.5453123);
    return seed.x;
}

float random_in_range(Interval interval, thread float2& seed) {
    return interval.min + (interval.max - interval.min) * random_double(seed);
}

float3 random_square(thread float2& seed) {
    float x = random_double(seed) - 0.5;
    float y = random_double(seed) - 0.5;
    return float3(x, y, 0.0);
}

Ray getRay(int i, int j, Uniforms uniforms, thread float2& seed) {
    float3 offset = random_square(seed);
    auto pixel_sample = uniforms.pixelOrigin + ((i + offset.x) * uniforms.pixelDeltaX) + ((j + offset.y) * uniforms.pixelDeltaY);
    auto ray_origin = uniforms.cameraCenter;
    auto ray_dir = normalize(pixel_sample - ray_origin);
    
    return {ray_dir, ray_origin};
}

float3 random_vector(thread float2& seed) {
    return float3(random_double(seed), random_double(seed), random_double(seed));
}

float3 random_vec_clamped(Interval interval, thread float2& seed) {
    return float3(random_in_range(interval, seed), random_in_range(interval, seed), random_in_range(interval, seed));
}

float3 random_unit_vec(thread float2& seed) {
    while (true) {
        float3 p = float3(
            random_double(seed) * 2.0 - 1.0,
            random_double(seed) * 2.0 - 1.0,
            random_double(seed) * 2.0 - 1.0
        );
        
        float len_sq = dot(p, p);
        if (len_sq >= 1e-30 && len_sq <= 1.0) {
            return p / sqrt(len_sq);
        }
    }
}

float3 random_on_hemisphere(float3 normals, thread float2& seed) {
    float3 on_unit_sphere = random_unit_vec(seed);
    if (dot(on_unit_sphere, normals) > 0.0) {
        return on_unit_sphere;
    } else {
        return -on_unit_sphere;
    }
}
