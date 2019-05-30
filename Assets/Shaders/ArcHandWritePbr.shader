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
				float3 lightDir = _WorldSpaceLightPos0.xyz;
				float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
				float3 lightColor = _LightColor0.rgb;

				//漫反射部分
                float4 Albedo = _Tint * tex2D(_MainTex, i.uv);
				float4 diffuseResult = float4(Albedo.rgb / PI * lightColor * DotClamped(lightDir, i.normal),1);

				//镜面反射部分
				float3 halfVector = normalize(lightDir + viewDir);  //半角向量
				float squareSmoothness = pow(_Smoothness, 2);
				float4 D = squareSmoothness / (pow((pow(DotClamped(halfVector, i.normal),2) * (squareSmoothness - 1)+1),2) * PI);

				float4 result = diffuseResult;
                return result;
            }
            ENDCG
        }
    }
}
