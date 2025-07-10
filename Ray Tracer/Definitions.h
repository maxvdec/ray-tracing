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
    
    simd_float3 cameraCenter;
    simd_float2 viewportSize;
};

struct Sphere {
    simd_float3 center;
    float radius;
};

struct Ray {
    simd_float3 direction;
    simd_float3 origin;
};


#endif /* Definitions_h */
