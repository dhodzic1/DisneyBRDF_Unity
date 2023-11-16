Shader "Custom/DisneyBRDF_Lit" {
    Properties {
        // BRDF Parameters
        _Subsurface("Subsurface", Range(0,1)) = 0
        _Metallic("Metallic", Range(0,1)) = 0
        _Specular("Specular", Range(0,1)) = 0.5
        _SpecularTint("Specular Tint", Range(0,1)) = 0
        _Roughness("Roughness", Range(0,1)) = 0.5
        _Anisotropic("Anisotropic", Range(0,1)) = 0
        _Sheen("Sheen", Range(0,1)) = 0
        _SheenTint("SheenTint", Range(0,1)) = 0.5
        _ClearCoat("Clearcoat", Range(0,1)) = 0
        _ClearCoatGloss("Clearcoat Gloss", Range(0,1)) = 0
        _Color("Color", Color) = (1,1,1,1)
        
        // Texture Maps
        _BumpMap("Normal Map", 2D) = "bump" {}
        _MainTex("Base Texture", 2D) = "white" {}
        _OcclusionMap("Ambient Occlusion", 2D) = "white" {}
        _MetallicMap("Metallic Map", 2D) = "white" {}
        _RoughnessMap("Roughness Map", 2D) = "white" {}
        _CubeMap("Reflection Map", Cube) = "white" {}
        _reflectionAmount("Reflection Amount", Range (0.0,1.0)) = 0.3
    }
    SubShader {
        Pass {
            Tags {
				"LightMode" = "ForwardBase"
                "RenderType"="Opaque" 
			}
            
            // Shaderlab commands
            ZWrite On
            Blend One Zero

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdbase nolightmap nodirlightmap nodynlightmap novertexlight

            #include "UnityCG.cginc"
            #include "AutoLight.cginc" // Needed for shadows
            #include "brdf_math.cginc" // This file contains all the math functions for the Disney BRDF
    
            // Parameters
            float4 _Color;
            float _Subsurface, _Metallic, _Specular, _SpecularTint,
            _Roughness, _Anisotropic, _Sheen, _SheenTint, _ClearCoat, _ClearCoatGloss;
         
            // Save on samplers by using DX11 HLSL style for declaration of texture and sampler
            Texture2D _BumpMap, _OcclusionMap, _MainTex, _RoughnessMap, _MetallicMap;
            SamplerState sampler_MainTex;
            uniform samplerCUBE _CubeMap; // Cube map sampler used for reflection map
            uniform fixed _reflectionAmount; // Affect the reflection intensity of the reflection map

            // Diffuse + Cook-Torrance
            //----------------------------------------------------------------------------------------------------------

            // L - Light Direction, V - View Direction, N - Normal Direction, X - Tangent, Y - Binormal, albedo - base color + texture maps combined
            float3 DisneyBRDF (float3 L, float3 V, float3 N, float3 X, float3 Y, float3 albedo) {
                float3 H = normalize(L+V); // Calculate halfway vector
                float NdotH = max(dot(N,H), 0.0);
                float NdotV = max(dot(N,V), 0.0);
                float NdotL = max(dot(N,L), 0.0);
                float LdotH = max(dot(L,H), 0.0);
                float HdotX = dot(H,X);
                float HdotY = dot(H,Y);
                float VdotX = dot(V,X);
                float VdotY = dot(V,Y);
                float LdotX = dot(L,X);
                float LdotY = dot(L,Y);
                
                float Cdlum = Luminance(albedo); // Converts color to luminance (grayscale).
                float3 Ctint = Cdlum > 0 ? albedo/Cdlum : float3(1,1,1); // color
                float3 Cspec0 = lerp(_Specular*0.08*lerp(float3(1,1,1), Ctint, _SpecularTint), albedo, _Metallic);
                float3 Csheen = lerp(float3(1,1,1),Ctint,_SheenTint);

                // Fresnel diffuse
                float Fdiffuse = diffuse(NdotL, NdotV, NdotH, _Roughness, albedo); // CHANGED
                
                float FL = SchlickFresnel(NdotL);
                float FV = SchlickFresnel(NdotV);
                
                // Based on Hanrahan-Krueger brdf approximation of isotropic bssrdf
				// 1.25 scale is used to (roughly) preserve albedo
				// Fss90 used to "flatten" retroreflection based on roughness
                float Fss90 = sqr(LdotH)*_Roughness;
				float Fss = lerp(1.0, Fss90, FL) * lerp(1.0, Fss90, FV);
                float ss = 1.25 * (Fss * (1 / (NdotL + NdotV) - .5) + .5);

                // Specular
                float aspect = sqrt(1.0 - .9 * _Anisotropic); // .9 limits aspect ratio to 10:1
                float ax = max(.001, sqr(_Roughness)/aspect); // no zero values for ax or ay
                float ay = max(.001, sqr(_Roughness)*aspect);
                // Distribution function (NDF)
                float DSpecular = GTR2Aniso(NdotH, HdotX, HdotY, ax, ay);
                float FH = SchlickFresnel(LdotH);
                // F - Fresnel equation
                float3 FSpecular = lerp(Cspec0, float3(1,1,1), FH);
                // G - Geometry/shadowing function  
                float GSpecular = SmithG_GGXAniso(NdotL, LdotX, LdotY, ax, ay);
				GSpecular *= SmithG_GGXAniso(NdotV, VdotX, VdotY, ax, ay);
                
                // sheen (sheen · (1 − cos θd)^5)
				float3 Fsheen =  FH * _Sheen * Csheen;
                
				// D,F,G for clearcoat
				float DReflect = GTR1(NdotH, lerp(.1,.001,_ClearCoatGloss));
				float FReflect = lerp(.04, 1.0, FH);
                float GReflect = SmithG(NdotL, NdotV, .25);

                // Using pi is to ensure that the energy distributed across the hemisphere doesn't exceed the energy put in (as pi in radians is 180 degrees - i.e. a hemisphere).
                return float4((1/PI * lerp(Fdiffuse, ss, _Subsurface)*albedo + Fsheen) * 
                       (1-_Metallic) + GSpecular*FSpecular*DSpecular + 0.25 * _ClearCoat*GReflect*FReflect*DReflect,1);
            }

            // Mesh data struct to hold all relevant information about the mesh
            struct meshData {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
                float2 uv : TEXCOORD0;
                float3 world : TEXCOORD1;
            };

            // Vertex to fragment interpolator struct which will hold mesh data transformed in vertex shader
            struct v2f {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 world : TEXCOORD1;
                float3 normal : TEXCOORD2;
                float4 tangent : TEXCOORD3;
                SHADOW_COORDS(4) // put shadows data into TEXCOORD4
            };

            // Vertex shader
            v2f vert(meshData v) {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.world = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.uv = v.uv;
                o.normal = v.normal;
                o.tangent = v.tangent;
                // compute shadows data
                TRANSFER_SHADOW(o)
                return o;
            }

            // Fragment shader
            fixed4 frag(v2f i) : SV_TARGET {
                // do bump map calculations before world space conversions (pre-normalization of normal & tangent)
                float3 binormal = cross(i.normal, i.tangent.xyz) * (i.tangent.w * unity_WorldTransformParams.w);
                // sample the normal map via tex2D and decode from the Unity encoding using UnpackNormal
                float3 tnormal = UnpackNormal(_BumpMap.Sample(sampler_MainTex, i.uv));
                i.normal = normalize(
                    tnormal.x * i.tangent +
                    tnormal.y * binormal +
                    tnormal.z * i.normal
                );

                // Initialize light, normal, view, tangent, and binormal vectors (all normalized)
                float3 L = normalize(lerp(_WorldSpaceLightPos0.xyz, _WorldSpaceLightPos0.xyz - i.world, _WorldSpaceLightPos0.w));
                float3 N = normalize(mul((float3x3)unity_ObjectToWorld, i.normal)); // convert object normals to world space
                float3 V = normalize(_WorldSpaceCameraPos.xyz - i.world);
                float3 T = normalize(mul((float3x3)unity_ObjectToWorld,i.tangent.xyz)); // Tangent
				float3 B = cross(N,T)*i.tangent.w * unity_WorldTransformParams.w; // Binormal - perpendicular to tangent and normal

                // Calculate world view direction and determine the world reflection vector
                half3 worldViewDir = normalize(UnityWorldSpaceViewDir(i.world));
                half3 worldRefl = reflect(-worldViewDir, N);
                    
                // Sample all texture maps
                float3 textureColor = _MainTex.Sample(sampler_MainTex, i.uv).rgb;
                textureColor *= _OcclusionMap.Sample(sampler_MainTex, i.uv);
                textureColor *= _RoughnessMap.Sample(sampler_MainTex, i.uv);
                textureColor *= _MetallicMap.Sample(sampler_MainTex, i.uv).r;
                textureColor *= _Color;
                
                // Interpolate the reflection amount with the cubemap and world reflection vector
                fixed3 reflect = lerp(textureColor, texCUBE(_CubeMap, worldRefl), _reflectionAmount);
                float4 nReflect = normalize(float4(reflect, 1.0));

                // compute shadow attenuation (1.0 = fully lit, 0.0 = fully shadowed)
                fixed shadow = SHADOW_ATTENUATION(i);
                fixed4 color = fixed4(DisneyBRDF(L, V, N, T, B, textureColor), 1.0);
                color *= shadow;
                
                return color + nReflect;
            }
            ENDHLSL
        }

        // shadow caster rendering pass, implemented manually
        // using macros from UnityCG.cginc
        // Reference https://docs.unity3d.com/2020.1/Documentation/Manual/SL-VertexFragmentShaderExamples.html
        Pass
        {
            Tags {"LightMode"="ShadowCaster"}

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_shadowcaster
            #include "UnityCG.cginc"

            struct v2f { 
                V2F_SHADOW_CASTER;
            };

            v2f vert(appdata_base v) {
                v2f o;
                TRANSFER_SHADOW_CASTER_NORMALOFFSET(o)
                return o;
            }

            float4 frag(v2f i) : SV_Target {
                SHADOW_CASTER_FRAGMENT(i)
            }
            ENDHLSL
        }
    }
}