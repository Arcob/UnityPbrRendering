Shader "Arc/ArcHandWritePbr"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
		_Tint("Tint", Color) = (1 ,1 ,1 ,1)
		_AO("AO", Range(0, 1)) = 0.1
		[Gamma] _Metallic("Metallic", Range(0, 1)) = 0
		_Smoothness("Smoothness", Range(0, 1)) = 0.5
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
			Tags {
				"LightMode" = "ForwardBase"
			}
            CGPROGRAM
			

			#pragma target 3.0

            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
			#include "UnityStandardBRDF.cginc" 
			#include "UnityPBSLighting.cginc"

#define PI 3.1415926

            struct appdata
            {
                float4 vertex : POSITION;
				float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

			struct v2f
			{
				float4 vertex : SV_POSITION;
				float2 uv : TEXCOORD0;
				float3 normal : TEXCOORD1;
				float3 worldPos : TEXCOORD2;
			};

			float4 _Tint;
			float _Metallic;
			float _AO;
			float _Smoothness;
            sampler2D _MainTex;
            float4 _MainTex_ST;

            v2f vert (appdata v)
            {
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.worldPos = mul(unity_ObjectToWorld, v.vertex);
				o.uv = TRANSFORM_TEX(v.uv, _MainTex);
				o.normal = UnityObjectToWorldNormal(v.normal);
				o.normal = normalize(o.normal);
				return o;
            }

			/*UnityGI Arc_UnityGI_Base(UnityGIInput data, half occlusion, half3 normalWorld)
			{
				UnityGI o_gi;
				ResetUnityGI(o_gi);

				o_gi.light = data.light;
				o_gi.light.color *= data.atten;

				//o_gi.indirect.diffuse = ShadeSHPerPixel(normalWorld, data.ambient, data.worldPos);
				half3 ambient_contrib = 0.0;
				//ambient_contrib = SHEvalLinearL0L1(half4(normalWorld, 1.0));

				// Linear (L1) + constant (L0) polynomial terms 
				ambient_contrib.r = dot(unity_SHAr, half4(normalWorld, 1.0));
				ambient_contrib.g = dot(unity_SHAg, half4(normalWorld, 1.0));
				ambient_contrib.b = dot(unity_SHAb, half4(normalWorld, 1.0));

				float3 ambient = max(half3(0, 0, 0), data.ambient + ambient_contrib);
				o_gi.indirect.diffuse = ambient;

				o_gi.indirect.diffuse *= occlusion;
				return o_gi;
			}*/

            fixed4 frag (v2f i) : SV_Target
            {
				i.normal = normalize(i.normal);
				float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);
				float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.worldPos.xyz);
				float3 lightColor = _LightColor0.rgb;
				float3 halfVector = normalize(lightDir + viewDir);  //半角向量

				float nl = max(saturate(dot(i.normal, lightDir)), 0.000001);
				float nv = max(saturate(dot(i.normal, viewDir)), 0.000001);//防止除0
				float vh = max(saturate(dot(viewDir, halfVector)), 0.000001);
				float lh = max(saturate(dot(lightDir, halfVector)), 0.000001);
				float nh = max(saturate(dot(i.normal, halfVector)), 0.000001);			

				//漫反射部分
                float3 Albedo = _Tint * tex2D(_MainTex, i.uv);
				float4 diffuseResult = float4(Albedo.rgb, 1);

				//环境光
				float3 ambientPre = 0.03 * Albedo * _AO;
				float4 ambient = float4(ambientPre, 1);

				//镜面反射部分
				//D是镜面分布函数，从统计学上估算微平面的取向
				float squareSmoothness = pow(_Smoothness, 2);
				float D = squareSmoothness / (pow((pow(nh,2) * (squareSmoothness - 1)+1),2) * PI);

				//几何遮蔽
				float kInDirectLight = pow(_Smoothness + 1, 2) / 8;
				float kInIBL = pow(_Smoothness, 2) / 8;
				float GLeft = nl / lerp(nl, 1, kInDirectLight);
				float GRight = nv / lerp(nv, 1, kInDirectLight);
				float G = GLeft * GRight;

				//菲涅尔
				//float3 F0 = _Metallic;
				float3 F0 = lerp(float3(0.04, 0.04, 0.04), Albedo, _Metallic);
				float F = lerp(pow((1 - max(vh, 0)),5), 1, F0);
				//float F = lerp(pow((1 - (vh + nv + lh) / 3), 5), 1, F0);
				//float F = F0 + (1 - F0) * exp2((-5.55473 * vh - 6.98316) * vh);
				
				//镜面反射
				float4 SpecularResult = D * G * F * 0.25/(nv * nl);
				
				
				//漫反射系数
				float kd = (1 - F)*(1 - _Metallic);
				
				//直接光照部分结果
				float4 DirectLightResult = (kd * diffuseResult + SpecularResult) * float4(lightColor, 1) * nl;
				//float4 result = (diffuseResult) * float4(lightColor, 1) * DotClamped(lightDir, i.normal);

				float3 reflectDir = reflect(-viewDir, i.normal);
				reflectDir = BoxProjectedCubemapDirection(reflectDir, i.worldPos, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax);
				//得到环境采样
				float4 envSample = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, reflectDir);

				//天空盒可能是HDR的，要转回普通的颜色
				float3 env = DecodeHDR(envSample, unity_SpecCube0_HDR);

				float4 IblResult = float4(env,1);

				float roughness = pow(pow(_Smoothness * Albedo.g, 2.19), 2);
				
				half occlusion = 1;

				UnityLight light; //光照
				light.color = _LightColor0.rgb;
				light.dir = lightDir;

				UnityGIInput d;
				d.light = light;
				d.worldPos = i.worldPos;
				d.worldViewDir = -viewDir;
				d.atten = 1;
				d.ambient = ambient.rgb;
				d.lightmapUV = 0;
				d.probeHDR[0] = unity_SpecCube0_HDR;
				d.probeHDR[1] = unity_SpecCube1_HDR;
				d.boxMin[0] = unity_SpecCube0_BoxMin; // .w holds lerp value for blending
				d.boxMax[0] = unity_SpecCube0_BoxMax;
				d.probePosition[0] = unity_SpecCube0_ProbePosition;
				d.boxMax[1] = unity_SpecCube1_BoxMax;
				d.boxMin[1] = unity_SpecCube1_BoxMin;
				d.probePosition[1] = unity_SpecCube1_ProbePosition;

				Unity_GlossyEnvironmentData g = UnityGlossyEnvironmentSetup(_Smoothness, -viewDir, i.normal, SpecularResult);

				//UnityGI gi = UnityGlobalIllumination(d, occlusion, i.normal, g);
				//UnityGI gi = Arc_UnityGI_Base(d, 1, i.normal);

				UnityGI o_gi;
				ResetUnityGI(o_gi);

				o_gi.light = light;

				//o_gi.indirect.diffuse = ShadeSHPerPixel(normalWorld, data.ambient, data.worldPos);
				half3 ambient_contrib = 0.0;
				//ambient_contrib = SHEvalLinearL0L1(half4(normalWorld, 1.0));

				// Linear (L1) + constant (L0) polynomial terms 
				ambient_contrib.r = dot(unity_SHAr, half4(i.normal, 1.0));
				ambient_contrib.g = dot(unity_SHAg, half4(i.normal, 1.0));
				ambient_contrib.b = dot(unity_SHAb, half4(i.normal, 1.0));

				float3 ambientIndirect = max(half3(0, 0, 0), ambient.rgb + ambient_contrib);
				o_gi.indirect.diffuse = ambientIndirect;

				float4 result = DirectLightResult + ambient + float4((o_gi.indirect.specular + o_gi.indirect.diffuse), 1);// +IblResult * F * saturate(1 - roughness);

				//Gamma矫正
				//result = result / (result + 1.0);
				//result = pow(result, 1.0 / 2.2);

				//return float4((gi.indirect.specular + gi.indirect.diffuse), 1);
				return result;
				//return nv * nl / (4 * nv * nl * lerp(nl, 1, kInDirectLight) * lerp(nv, 1, kInDirectLight));
				//return (1 / (lerp(nl, 1, kInDirectLight) * lerp(nv, 1, kInDirectLight))) / 4;
            }

			

            ENDCG
        }
    }
}


