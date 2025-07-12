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
    
    float u;
    float v;
    
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

float3 random_in_unit_disk(thread float2& seed) {
    float x, y;
    do {
        x = 2.0 * random_double(seed) - 1.0;
        y = 2.0 * random_double(seed) - 1.0;
    } while (x * x + y * y >= 1.0);
    
    return float3(x, y, 0.0);
}

float3 defocusDiskSample(Uniforms uniforms, thread float2& seed) {
    auto p = random_in_unit_disk(seed);
    return uniforms.cameraCenter + (p.x * uniforms.defocusDiskU) + (p.y * uniforms.defocusDiskV);
}

Ray getRay(int i, int j, Uniforms uniforms, thread float2& seed) {
    float3 offset = random_square(seed);
    auto pixel_sample = uniforms.pixelOrigin + ((i + offset.x) * uniforms.pixelDeltaX) + ((j + offset.y) * uniforms.pixelDeltaY);
    auto ray_origin = (uniforms.defocusAngle <= 0) ? uniforms.cameraCenter : defocusDiskSample(uniforms, seed);
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

float linear_to_gamma(float linear) {
    if (linear > 0) {
        return sqrt(linear);
    }
    
    return 0;
}

bool isVecNearZero(float3 vec) {
    auto s = 1e-8;
    return (fabs(vec.x) < s) && (fabs(vec.y) < s) && (fabs(vec.z) < s);
}

bool lambertianScatter(MeshMaterial m, Ray r, HitInfo hit, thread float4& attenuation, thread Ray& scattered, thread float2& seed) {
    auto scatter_direction = hit.normal + random_unit_vec(seed);
    
    if (isVecNearZero(scatter_direction)) {
        scatter_direction = hit.normal;
    }
    
    scattered = {hit.point, scatter_direction};
    attenuation = m.albedo;
    return true;
}

bool metalScatter(MeshMaterial m, Ray r, HitInfo hit, thread float4& attenuation, thread Ray& scattered, thread float2& seed) {
    float3 reflected = reflect(r.direction, hit.normal);
    reflected = normalize(reflected) + (m.reflection_fuzz * random_unit_vec(seed));
    scattered = { normalize(reflected), hit.point };
    attenuation = m.albedo;
    return dot(scattered.direction, hit.normal) > 0;
}

float reflectance(float cosine, float refraction_index) {
    auto r0 = (1 - refraction_index) / (1 + refraction_index);
    r0 = r0 * r0;
    return r0 + (1 - r0) * pow(1 - cosine, 5);
}

bool dielectricScatter(MeshMaterial m, Ray r, HitInfo hit, thread float4& attenuation, thread Ray& scattered, thread float2& seed) {
    attenuation = float4(1.0, 1.0, 1.0, 1.0);
    float ri = hit.hit_front ? (1.0 / m.refraction_index) : m.refraction_index;
    float3 unit_dir = normalize(r.direction);
    float cos_theta = fmin(dot(-unit_dir, hit.normal), 1.0);
    float sin_theta = sqrt(1.0 - cos_theta * cos_theta);
    
    bool cannot_refract = ri * sin_theta > 1.0;
    float3 direction;
    
    if (cannot_refract || reflectance(cos_theta, ri) > random_double(seed)) {
        direction = reflect(unit_dir, hit.normal);
    } else {
        direction = refract(unit_dir, hit.normal, ri);
    }
    
    scattered = { direction, hit.point };
    return true;
}

bool materialScatters(MeshMaterial m, Ray r, HitInfo hit, thread float4& attenuation, thread Ray& scattered, thread float2& seed) {
    if (m.type == LAMBIERTIAN) {
        return lambertianScatter(m, r, hit, attenuation, scattered, seed);
    } else if (m.type == REFLECTEE) {
        return metalScatter(m, r, hit, attenuation, scattered, seed);
    } else if (m.type == DIELECTRIC) {
        return dielectricScatter(m, r, hit, attenuation, scattered, seed);
    } else {
        return false;
    }
}

bool hitSphere(Sphere s, Ray r, thread HitInfo& hit) {
    float3 oc = r.origin - s.center;
    auto a = dot(r.direction, r.direction);
    auto b = dot(oc, r.direction);
    auto c = dot(oc, oc) - s.radius * s.radius;
    
    auto discriminant = b * b - a * c;
    if (discriminant < 0) {
        return false;
    }
    
    if (abs(a) < 1e-6) {
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

bool hitPlane(Quad q, Ray r, thread HitInfo& hit) {
    auto n = cross(q.extentX, q.extentY);
    auto normal = normalize(n);
    
    auto denom = dot(normal, r.direction);
    
    if (fabs(denom) < 1e-8) {
        return false;
    }
    
    auto t = dot(normal, q.origin - r.origin) / denom;
    if (!r.distance.contains(t)) {
        return false;
    }
    
    auto inter = r.at(t);
    
    auto toPoint = inter - q.origin;
    auto dotU = dot(toPoint, normalize(q.extentX));
    auto dotV = dot(toPoint, normalize(q.extentY));
    
    float uLen = length(q.extentX);
    float vLen = length(q.extentY);
    
    if (dotU < 0 || dotU > uLen || dotV < 0 || dotV > vLen) {
        return false;
    }
    
    hit.distance = t;
    hit.point = inter;
    hit.apply_normals(r, normal);
    return true;
}


bool hitObject(Object obj, Ray r, thread HitInfo& info) {
    if (obj.type == TYPE_SPHERE && hitSphere(obj.s, r, info)) {
        return true;
    } else if (obj.type == TYPE_QUAD && hitPlane(obj.q, r, info)) {
        return true;
    } else {
        return false;
    }
}
