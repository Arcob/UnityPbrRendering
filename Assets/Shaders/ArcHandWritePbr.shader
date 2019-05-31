Shader "Arc/ArcHandWritePbr"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
		_Tint("Tint", Color) = (1 ,1 ,1 ,1)
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

            fixed4 frag (v2f i) : SV_Target
            {
                // sample the texture
				i.normal = normalize(i.normal);
				float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);
				float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
				float3 lightColor = _LightColor0.rgb;
				float3 halfVector = normalize(lightDir + viewDir);  //半角向量

				float nl = saturate(dot(i.normal, lightDir));
				float nv = saturate(dot(i.normal, viewDir));
				float vh = saturate(dot(viewDir, halfVector));


				//漫反射部分
                float4 Albedo = _Tint * tex2D(_MainTex, i.uv);
				float4 diffuseResult = float4(Albedo.rgb, 1);

				//镜面反射部分
				
				float squareSmoothness = pow(_Smoothness, 2);
				float D = squareSmoothness / (pow((pow(DotClamped(halfVector, i.normal),2) * (squareSmoothness - 1)+1),2) * PI);

				//几何遮蔽
				float kInDirectLight = pow(_Smoothness + 1, 2) / 8;
				float kInIBL = pow(_Smoothness, 2) / 8;
				float GLeft = nl / lerp(nl, 1, kInDirectLight);
				float GRight = nv / lerp(nv, 1, kInDirectLight);
				float G = GLeft * GRight;

				//菲涅尔
				//float3 F0 = _Metallic;
				float3 F0 = lerp(float3(0.04, 0.04, 0.04), Albedo, _Metallic);
				//float F = lerp(pow((1 - vh),5), 1, F0);
				float F = F0 + (1 - F0) * exp2((-5.55473 * vh - 6.98316) * vh);
				
				//镜面反射
				float4 SpecularResult = D * G * F/(4 * nv * nl);
				
				
				//漫反射系数
				float kd = (1 - F)*(1 - _Metallic);

				//直接光照部分结果
				float4 DirectLightresult = (kd * diffuseResult + SpecularResult) * float4(lightColor, 1) * nl;
				//float4 result = (diffuseResult) * float4(lightColor, 1) * DotClamped(lightDir, i.normal);

				float3 reflectDir = reflect(-viewDir, i.normal);
				//得到环境采样
				float4 envSample = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, reflectDir);
				//天空盒可能是HDR的，要转回普通的颜色
				float3 env = DecodeHDR(envSample, unity_SpecCube0_HDR);

				float4 IblResult = float4(env,1);

				float4 result = DirectLightresult;

				return F;
            }
            ENDCG
        }
    }
}
