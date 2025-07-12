//
//  Shaders.metal
//  Ray Tracer
//
//  Created by Max Van den Eynde on 10/7/25.
//

#include <metal_stdlib>
#include "Lib.metal"
#include "Hit.metal"
#include "BVH.metal"
using namespace metal;

bool world_hit(device Object* objs, int objectCount, thread Ray& r, thread HitInfo& hit, thread int& hitObjectIndex) {
    HitInfo temp_hit;
    bool hit_anything = false;
    auto closest_so_far = r.distance.max;
    
    for (int i = 0; i < objectCount; ++i) {
        Object obj = objs[i];
        if (hit_object(obj, r, temp_hit)) {
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

bool world_hit_bvh(device Object* objs, device BVHNode* nodes, int rootNodeIndex, thread Ray& r, thread HitInfo& hit, thread int& hitObjectIndex) {
    if (rootNodeIndex < 0) {
        return false;
    }
    
    HitInfo temp_hit;
    bool hit_anything = false;
    auto closest_so_far = r.distance.max;
    
    int stack[64];
    int stackSize = 0;
    
    stack[stackSize++] = rootNodeIndex;
    
    while (stackSize > 0) {
        int nodeIndex = stack[--stackSize];
        BVHNode node = nodes[nodeIndex];
        
        Ray tempRay = r;
        if (!node.box.hit(tempRay)) {
            continue;
        }
        
        if (node.is_leaf) {
            for (int objIdx = node.left_index; objIdx <= node.right_index; objIdx++) {
                Object obj = objs[objIdx];
                if (hit_object(obj, r, temp_hit)) {
                    if (temp_hit.distance < closest_so_far) {
                        hit_anything = true;
                        closest_so_far = temp_hit.distance;
                        hit = temp_hit;
                        hitObjectIndex = objIdx;
                        r.distance.max = closest_so_far;
                    }
                }
            }
        } else {
            if (stackSize < 62) {
                stack[stackSize++] = node.left_index;
                stack[stackSize++] = node.right_index;
            }
        }
    }
    
    return hit_anything;
}

float4 color_ray(device Object* objs, int objectCount, device BVHNode* nodes, int rootNodeIndex, Ray r, thread float2& seed, int maxDepth, float4 baseSkyColor, bool useBVH) {
    float4 accumulatedColor = float4(1.0, 1.0, 1.0, 1.0);
    float4 finalColor = float4(0.0);
    
    for (int depth = 0; depth < maxDepth; ++depth) {
        r.distance = {0.001, MAXFLOAT};
        
        HitInfo info;
        int hitObjectIndex = -1;
        bool hit_something = false;
        
        if (useBVH && rootNodeIndex >= 0) {
            hit_something = world_hit_bvh(objs, nodes, rootNodeIndex, r, info, hitObjectIndex);
        } else {
            hit_something = world_hit(objs, objectCount, r, info, hitObjectIndex);
        }
        
        if (hit_something) {
            return float4(1.0, 0.0, 0.0, 1.0);
            Object hitObject = objs[hitObjectIndex];
            
            if (hitObject.mat.emission > 0.0) {
                float4 emissionColor = hitObject.mat.emission;
                finalColor += accumulatedColor * emissionColor;
                break;
            }
            
            Ray scattered;
            
            float4 attenuation;
            if (materialScatters(hitObject.mat, r, info, attenuation, scattered, seed)) {
                accumulatedColor *= attenuation;
                r = scattered;
            } else {
                break;
            }
        } else {
            float t = 0.5f * (normalize(r.direction).y + 1.0f);
            float4 skyColor = baseSkyColor * (1.0f + t);
            finalColor += skyColor;
            break;
        }
    }

    return finalColor;
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

AABB makeMainBox(device Object* objs, Uniforms uniforms) {
    AABB box;
    for (int i = 0; i < uniforms.objCount; ++i) {
        Object obj = objs[i];
        if (obj.type == TYPE_SPHERE) {
            addChildren(box, aabbForSphere(obj.s));
        }
    }
    return box;
}

kernel void computeShader(texture2d<float, access::read_write> outputTexture [[texture(0)]],
                                          constant Uniforms& uniforms [[buffer(0)]],
                                          device Object* objs [[buffer(1)]],
                                          device BVHNode* nodes [[buffer(2)]],
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
    
    if (uniforms.currentSample > 10000) {
        error_write(outputTexture, gid);
        return;
    }
    
    const int raysPerPass = uniforms.sampleCount;
    
    float4 passAccumulator = float4(0.0);
    
    // Determine if we should use BVH (you might want to add a flag to uniforms for this)
    bool useBVH = false; // You can make this configurable via uniforms
    int rootNodeIndex = 0; // Assuming root is at index 0, adjust as needed
    
    for (int rayIndex = 0; rayIndex < raysPerPass; rayIndex++) {
        float2 seed = float2(
            float(pixelPos.x * 1973 + pixelPos.y * 9277 + uniforms.currentSample * 26699 + rayIndex * 7919) / 65536.0,
            float(pixelPos.y * 4513 + pixelPos.x * 6389 + uniforms.currentSample * 30103 + rayIndex * 8191) / 65536.0
        );
        
        seed = fract(seed + float2(0.618034, 0.381966));
        
        Ray r = getRay(pixelPos.x, pixelPos.y, uniforms, seed);
        
        if (length(r.direction) < 1e-6 || isnan(r.direction.x) || isnan(r.direction.y) || isnan(r.direction.z)) {
            continue; // Skip invalid rays
        }
        
        int safeMaxDepth = min(uniforms.maxRayDepth, 10);
        float4 rayColor = color_ray(objs, uniforms.objCount, nodes, rootNodeIndex, r, seed, safeMaxDepth, uniforms.globalIllumation, useBVH);
        
        rayColor.rgb = clamp(rayColor.rgb, 0.0, 10.0);
        
        passAccumulator += rayColor;
    }

    passAccumulator /= float(raysPerPass);
    
    float4 existingColor = outputTexture.read(pixelPos);
    
    existingColor.rgb = existingColor.rgb * existingColor.rgb;
    
    float4 finalColor;
    if (uniforms.currentSample == 0) {
        finalColor = passAccumulator;
    } else {
        
        float totalRaysSoFar = float(uniforms.currentSample * raysPerPass + raysPerPass);
        float passWeight = float(raysPerPass) / totalRaysSoFar;
        
        finalColor.rgb = existingColor.rgb * (1.0 - passWeight) + passAccumulator.rgb * passWeight;
        finalColor.a = 1.0;
    }
    
    write_color(outputTexture, pixelPos, finalColor);
}
