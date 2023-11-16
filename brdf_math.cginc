#ifndef BRDF_MATH_INCLUDED
#define BRDF_MATH_INCLUDED

static const float PI = 3.14159265358979323846;
float sqr (float x) { return x * x; } // squaring function

// Cook-Torrance part of equation
//----------------------------------------------------------------------------------------------------------

// Distribution function D (Non-Generalized)
float TrowbridgeReitzGGX (float NdotH, float roughness) {
    float a2 = roughness * roughness;
    float denom2 = pow(sqr(NdotH) * (a2-1) + 1, 2); // (denominator squared)
    
    return a2 / (PI * denom2); // TRGGX equation
}

// Distribution function D (GTR1) (Generalized Trowbridge-Reitz)
float GTR1 (float NdotH, float roughness) {
    float a2 = roughness * roughness;
    float denom = PI * log(a2) * (1 + (a2-1) * sqr(NdotH));
    
    return (a2-1) / denom;
}

// Distribution function D (GTR2)
float GTR2 (float NdotH, float roughness) {
    float a2 = roughness * roughness;
    float denom = PI * sqr(1 + (a2-1) * sqr(NdotH));
    
    return a2 / denom;
}

// Anisotropic GTR2 (varied roughness ax and ay)
float GTR2Aniso (float NdotH, float HdotX, float HdotY, float ax, float ay) {
    float ax2 = ax*ax;
    float ay2 = ay*ay;
    
    return 1 / (PI * ax * ay * sqr(sqr(HdotX/ax2) + sqr(HdotY/ay2) + sqr(NdotH)));
}

// Fresnel Equation
float SchlickFresnel(float u) {
    float m = clamp(1-u, 0, 1);
    return pow(m,5);
}

// Geometry function G (combination of GGX and Schlick-Beckmann)
float SchlickGGX (float NdotV, float roughness) {
    float ag = sqr(0.5 + roughness/2);
    float denom = NdotV * (1-ag) + ag;
    return NdotV / denom;
}

// Geometry function G (Smith derivation of GGX)
float SmithG (float NdotV, float NdotL, float roughness) {
    return SchlickGGX(NdotV, roughness) * SchlickGGX(NdotL, roughness);
}

float SmithG_GGXAniso(float NdotV, float VdotX, float VdotY, float ax, float ay) {
    return 1 / (NdotV + sqrt( sqr(VdotX*ax) + sqr(VdotY*ay) + sqr(NdotV) ));
}
            
// Diffuse portion of equation
//----------------------------------------------------------------------------------------------------------

// Fresnel equation F to be used in diffuse component
float diffuseFresnelSchlick (float NdotH, float F0) {
    return max(F0 + (1-F0)*pow(1 - NdotH, 5), 0.0);
}

float diffuse (float NdotL, float NdotV, float NdotH, float roughness, float color) {
    float FD90 = 0.5 + 2*roughness*sqr(NdotH);
    return color/PI * (diffuseFresnelSchlick(NdotL, FD90) * diffuseFresnelSchlick(NdotV, FD90));
}

#endif // BRDF_MATH_INCLUDED