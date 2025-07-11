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

bool world_hit(constant Object* objs, int objectCount, thread Ray& r, thread HitInfo& hit, thread int& hitObjectIndex) {
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
                hitObjectIndex = i;
                r.distance.max = closest_so_far;
            }
        }
    }
    
    return hit_anything;
}

float4 color_ray(constant Object* objs, int objectCount, thread Ray& r, thread float2& seed, int depth) {
    if (depth <= 0) {
        return float4(0, 0, 0, 1);
    }

    HitInfo info;
    int hitObjectIndex = -1;
    r.distance = {0.001, MAXFLOAT};
    
    if (world_hit(objs, objectCount, r, info, hitObjectIndex)) {
        Object hitObject = objs[hitObjectIndex];
        
        if (hitObject.emission > 0.0) {
            float3 emissionColor = float3(hitObject.emission, hitObject.emission, hitObject.emission);
            return float4(emissionColor, 1.0);
        }
        
        float3 direction = info.normal + random_unit_vec(seed);

        if (length(direction) < 1e-6) {
            direction = info.normal;
        }

        Ray scatteredRay;
        scatteredRay.origin = info.point;
        scatteredRay.direction = normalize(direction);
        scatteredRay.distance = {0.001, INFINITY};

        float4 bouncedColor = color_ray(objs, objectCount, scatteredRay, seed, depth - 1);

        float3 albedo = float3(0.7, 0.7, 0.7);
        
        return float4(albedo * bouncedColor.rgb, 1.0);
    }

    return float4(0.0, 0.0, 0.0, 1.0);
}

void write_color(texture2d<float, access::read_write> texture, uint2 pos, float4 color) {
    Interval i = {0, 1};
    
    float r = i.clamp(isnan(color.r) ? 0.0 : color.r);
    float g = i.clamp(isnan(color.g) ? 0.0 : color.g);
    float b = i.clamp(isnan(color.b) ? 0.0 : color.b);
    float a = i.clamp(isnan(color.a) ? 1.0 : color.a);
    r = linear_to_gamma(r);
    g = linear_to_gamma(g);
    b = linear_to_gamma(b);
    a = linear_to_gamma(a);
    
    float4 result = float4(r, g, b, a);
    texture.write(result, pos);
}

void error_write(texture2d<float, access::read_write> texture, uint2 pos) {
    texture.write(float4(1.0, 1.0, 0.0, 1.0), pos);
}

kernel void computeShader(texture2d<float, access::read_write> outputTexture [[texture(0)]],
                                    constant Uniforms& uniforms [[buffer(0)]],
                                    constant Object* objs [[buffer(1)]],
                                    uint2 gid [[thread_position_in_grid]]) {
    
    uint width = outputTexture.get_width();
    uint height = outputTexture.get_height();
    
    uint2 pixelPos = uint2(uniforms.tileX + gid.x, uniforms.tileY + gid.y);
    
    if (gid.x >= uint(uniforms.tileWidth) || gid.y >= uint(uniforms.tileHeight)) {
        error_write(outputTexture, gid);
        return;
    }
    
    if (pixelPos.x >= width || pixelPos.y >= height) {
        error_write(outputTexture, gid);
        return;
    }
    
    const int samplesPerFrame = uniforms.sampleCount;
    
    float4 accumulatedColor = float4(0.0);
    
    for (int sample = 0; sample < samplesPerFrame; sample++) {
        float2 seed = float2(
            float(pixelPos.x * 1973 + pixelPos.y * 9277 + (uniforms.currentSample * samplesPerFrame + sample) * 2699) / 65536.0,
            float(pixelPos.y * 4513 + width * 6389 + (uniforms.currentSample * samplesPerFrame + sample) * 3011) / 65536.0
        );
        
        Ray r = getRay(pixelPos.x, pixelPos.y, uniforms, seed);
        
        if (length(r.direction) < 1e-6 || isnan(r.direction.x) || isnan(r.direction.y) || isnan(r.direction.z)) {
            continue; // Skip bad rays
        }
        
        int safeMaxDepth = min(uniforms.maxRayDepth, 10);
        float4 sampleColor = color_ray(objs, uniforms.objCount, r, seed, safeMaxDepth);
        
        accumulatedColor += sampleColor;
    }
    
    accumulatedColor /= float(samplesPerFrame);
    
    float4 existingColor = outputTexture.read(pixelPos);
    float4 finalColor;
    
    if (uniforms.currentSample == 0) {
        finalColor = accumulatedColor;
    } else {
        float totalSamples = float(uniforms.currentSample * samplesPerFrame + samplesPerFrame);
        float weight = float(samplesPerFrame) / totalSamples;
        finalColor = existingColor * (1.0 - weight) + accumulatedColor * weight;
    }
    
    write_color(outputTexture, pixelPos, finalColor);
}
