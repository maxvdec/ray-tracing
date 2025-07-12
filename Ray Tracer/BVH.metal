//
//  BVH.metal
//  Ray Tracer
//
//  Created by Max Van den Eynde on 12/7/25.
//

#ifndef BVH_METAL
#define BVH_METAL

#include <metal_stdlib>
#include "Definitions.h"
#include "Lib.metal"
#include "Hit.metal"
using namespace metal;

class AABB {
public:
    Interval x, y, z;
    
    AABB() {}
    
    AABB(Interval x, Interval y, Interval z) : x(x), y(y), z(z) {}
    
    AABB(float3 a, float3 b) {
        x = (a.x <= b.x) ? Interval(a.x, b.x) : Interval(b.x, a.x);
        y = (a.y <= b.y) ? Interval(a.y, b.y) : Interval(b.y, a.y);
        z = (a.z <= b.z) ? Interval(a.z, b.z) : Interval(b.z, a.z);
    }
    
    AABB(AABB box0, AABB box1) {
        x = Interval(box0.x, box1.x);
        y = Interval(box0.y, box1.y);
        z = Interval(box0.z, box1.z);
    }
    
    Interval axis_interval(Axis a) {
        if (a == Axis::X) return x;
        if (a == Axis::Y) return y;
        return z;
    }
    
    bool hit(thread Ray& r) {
        float3 origin = r.origin;
        float3 direction = r.direction;
        
        for (int axis = 0; axis < 3; ++axis) {
            Axis a = axisFromNumber(axis);
            Interval ax = axis_interval(a);
            float adinv = 1.0 / vectorAtAxis(direction, a);
            
            auto t0 = (ax.min - vectorAtAxis(origin, a)) * adinv;
            auto t1 = (ax.max - vectorAtAxis(origin, a)) * adinv;
            
            if (t0 < t1) {
                if (t0 > r.distance.min) r.distance.min = t0;
                if (t1 < r.distance.max) r.distance.max = t1;
            } else {
                if (t1 > r.distance.min) r.distance.min = t1;
                if (t0 < r.distance.max) r.distance.max = t0;
            }
            
            if (r.distance.max <= r.distance.min) {
                return false;
            }
        }
        return true;
    }
};

AABB aabbForSphere(Sphere s) {
    return AABB(s.aabbData.a, s.aabbData.b);
}

AABB aabbForObject(Object obj) {
    if (obj.type == TYPE_SPHERE) {
        return aabbForSphere(obj.s);
    } else {
        return AABB();
    }
}

void addChildren(thread AABB& father, AABB children) {
    father = AABB(father, children);
}

struct BVHNode {
    int left_index;
    int right_index;
    bool is_leaf;
    AABB box;
};

void sort_objects_by_axis(device Object* objects, int start, int end, int axis) {
    for (int i = start; i < end - 1; ++i) {
        for (int j = i + 1; j < end; ++j) {
            float a_min = aabbForObject(objects[i]).axis_interval(axisFromNumber(axis)).min;
            float b_min = aabbForObject(objects[j]).axis_interval(axisFromNumber(axis)).min;

            if (b_min < a_min) {
                Object temp = objects[i];
                objects[i] = objects[j];
                objects[j] = temp;
            }
        }
    }
}

int build_bvh(device Object* objects, int start, int end, device BVHNode* nodes, thread int& nodeCount, thread float2& seed) {
    int axis = random_int(0, 2, seed);
    int object_span = end - start;
    int node_index = nodeCount++;

    device BVHNode& node = nodes[node_index];

    if (object_span == 1) {
        node.left_index = start;
        node.right_index = start;
        node.is_leaf = true;
        node.box = aabbForObject(objects[start]);
    } else if (object_span == 2) {
        node.left_index = start;
        node.right_index = start + 1;
        node.is_leaf = true;
        node.box = AABB(aabbForObject(objects[start]), aabbForObject(objects[start + 1]));
    } else {
        sort_objects_by_axis(objects, start, end, axis);
        int mid = start + object_span / 2;

        node.left_index = build_bvh(objects, start, mid, nodes, nodeCount, seed);
        node.right_index = build_bvh(objects, mid, end, nodes, nodeCount, seed);
        node.is_leaf = false;

        node.box = AABB(
            nodes[node.left_index].box,
            nodes[node.right_index].box
        );
    }

    return node_index;
}

// Corrected hit_bvh function
bool hit_bvh(
    thread Ray& r,
    device BVHNode* nodes,
    device Object* objects,
    int node_index,
    thread HitInfo& info,
    thread int& hitObjectIndex
) {
    BVHNode node = nodes[node_index];
    
    // Create a temporary ray for AABB testing to avoid modifying the original ray's distance
    Ray tempRay = r;
    if (!node.box.hit(tempRay)) return false;

    bool hit_anything = false;
    HitInfo temp_hit;
    float closest_so_far = r.distance.max;

    if (node.is_leaf) {
        // Test intersection with objects in this leaf
        for (int objIdx = node.left_index; objIdx <= node.right_index; objIdx++) {
            if (hit_object(objects[objIdx], r, temp_hit)) {
                if (temp_hit.distance < closest_so_far) {
                    hit_anything = true;
                    closest_so_far = temp_hit.distance;
                    info = temp_hit;
                    hitObjectIndex = objIdx;
                    r.distance.max = closest_so_far;
                }
            }
        }
    } else {
        // Test both children
        int leftHitIndex = -1, rightHitIndex = -1;
        HitInfo leftHit, rightHit;
        
        bool hit_left = hit_bvh(r, nodes, objects, node.left_index, leftHit, leftHitIndex);
        bool hit_right = hit_bvh(r, nodes, objects, node.right_index, rightHit, rightHitIndex);
        
        if (hit_left && hit_right) {
            if (leftHit.distance < rightHit.distance) {
                info = leftHit;
                hitObjectIndex = leftHitIndex;
            } else {
                info = rightHit;
                hitObjectIndex = rightHitIndex;
            }
            hit_anything = true;
        } else if (hit_left) {
            info = leftHit;
            hitObjectIndex = leftHitIndex;
            hit_anything = true;
        } else if (hit_right) {
            info = rightHit;
            hitObjectIndex = rightHitIndex;
            hit_anything = true;
        }
    }
    
    return hit_anything;
}

#endif
