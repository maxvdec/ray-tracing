//
//  Definitions.h
//  Ray Tracer
//
//  Created by Max Van den Eynde on 10/7/25.
//

#ifndef Definitions_h
#define Definitions_h

#include <simd/simd.h>

struct Uniforms {
    simd_float4 color;
    float time;
    
    simd_float3 pixelDeltaX;
    simd_float3 pixelDeltaY;
    simd_float3 pixelOrigin;
    float pixelSampleScale;
    
    simd_float3 cameraCenter;
    simd_float2 viewportSize;
    
    int objCount;
    int sampleCount;
    
    int maxRayDepth;
    int currentSample;
    int totalSamples;
};

struct Sphere {
    simd_float3 center;
    float radius;
};

#define TYPE_SPHERE 0

struct Object {
    int type;
    struct Sphere s; // Only used when Sphere is selected
};

#endif /* Definitions_h */
