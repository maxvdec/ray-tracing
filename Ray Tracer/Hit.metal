//
//  Hit.metal
//  Ray Tracer
//
//  Created by Max Van den Eynde on 12/7/25.
//

#ifndef HIT_METAL
#define HIT_METAL

#include <metal_stdlib>
#include "Definitions.h"
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

bool hit_object(Object obj, thread Ray& r, thread HitInfo& hit) {
    if (obj.type == TYPE_SPHERE) {
        hitSphere(obj.s, r, hit);
    } else {
        return false;
    }
}

#endif
