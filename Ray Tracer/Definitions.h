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
    simd_float3 defocusDiskU;
    simd_float3 defocusDiskV;
    float defocusAngle;
    
    int objCount;
    int lightCount;
    int sampleCount;
    
    int maxRayDepth;
    int currentSample;
    int totalSamples;
    
    // Tile information
    int tileX;
    int tileY;
    int tileWidth;
    int tileHeight;
    
    simd_float4 globalIllumation;
};

struct Sphere {
    simd_float3 center;
    float radius;
};

#define LAMBIERTIAN 0
#define REFLECTEE 1
#define DIELECTRIC 2

struct MeshMaterial {
    int type;
    float emission;
    simd_float4 albedo;
    simd_float4 emission_color;
    
    float reflection_fuzz;
    float refraction_index;
};

#define TYPE_SPHERE 0

struct Object {
    int type;
    struct Sphere s; // Only used when Sphere is selected
    struct MeshMaterial mat;
};


#endif /* Definitions_h */
