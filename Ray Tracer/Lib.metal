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
        return min < x && x < max;
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

uint pcg_hash(uint input) {
    uint state = input * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

float random_double(thread float2& seed) {
    uint2 iseed = uint2(seed * 65536.0);
    uint hash = pcg_hash(iseed.x ^ pcg_hash(iseed.y));

    seed = fract(seed + float2(0.618034, 0.381966));
    
    return float(hash) / 4294967296.0;
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
    float x1, x2, w;
    do {
        x1 = 2.0 * random_double(seed) - 1.0;
        x2 = 2.0 * random_double(seed) - 1.0;
        w = x1 * x1 + x2 * x2;
    } while (w >= 1.0);
    
    float multiplier = 2.0 * sqrt(1.0 - w);
    
    return float3(
        x1 * multiplier,
        x2 * multiplier,
        1.0 - 2.0 * w
    );
}

float3 random_on_hemisphere(float3 normals, thread float2& seed) {
    float3 on_unit_sphere = random_unit_vec(seed);
    if (dot(on_unit_sphere, normals) > 0.0) {
        return on_unit_sphere;
    } else {
        return -on_unit_sphere;
    }
}
