Shader "Unlit/Height2"
{
    Properties
    {
        _base("BaseTexture",2D) = "white"{}
        _MainTex ("HeightTexture", 2D) = "white" {}
        _normal ("normal",2D)= "bump"{}
        _Scele("Scale",Range(0,1))=0.01
        _minlayer("MiniScale",Range(2,60))=10
        _maxlayer("MaxLayer",Range(10,700))=50
        _roughness("roughness",Range(0,1)) = 1
        _metal("metal",Range(0,1)) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {   
            Name "FORWARD"
            Tags{
                "LightMode"="ForwardBase"
            }

            //Cull Front
            CGPROGRAM
            #include "AutoLight.cginc"
            #include "lighting.cginc"
            #include "UnityCG.cginc"
            // #include "UnityPBSLighting.cginc"


            #pragma multi_compile_fwdbase_fullshadows
            #pragma vertex vert
            #pragma fragment frag
             #pragma multi_compile_fwdbase nolightmap nodirlightmap nodynlightmap novertexlight
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"




            // struct appdata
            // {
            //     float4 vertex : POSITION;
            //     float2 uv : TEXCOORD0;
            //     float3 normal : NORMAL;
            //     float4 tangent : TANGENT;
            // };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 pos : SV_POSITION;
                float4 posWorld : TEXCOORD1;
                float3 normalDir :TEXCOORD2;
                float3 tangentDir : TEXCOORD3;
                float3 bittangentDir : TEXCOORD4;
                fixed3 ambient : COLOR0;
                LIGHTING_COORDS(5,6)
                //SHADOW_COORDS(7)
                //SHADOW_COORDS(7)
                //float3 viewDir : TEXCOORD1;
            };

            sampler2D _MainTex;
            sampler2D _normal;
            sampler2D _base;
            float _Scele;
            float _minlayer;
            float _maxlayer;
            float4 _MainTex_ST;
            float4 _normal_ST;
            float4 _base_ST;
            half _roughness ;
            half _metal ;
            


            //视差贴图函数
            float2 parallaxmaping(in float3 tangentT,in float3 V ,in v2f X,in float2 T,out float ParallaxHeight)
            {   
                
                float3 normalDirection = X.normalDir;
                
                float3 TangentVD = tangentT;
                // float3 TangentColor = TangentVD.rgb;
                //fixed4 finalTangentColor = fixed4(TangentColor,1);//viewDir.xyz,1


                //用于控制迭代层数
                int nNamberSamples =(int) (lerp(_minlayer,_maxlayer,1-dot(normalDirection,V)));

                float layerheight = 1.0 / nNamberSamples;
                float currentHeight = 0;
                float2 currentTextureCoords  = T;
                float h =1-tex2D(_MainTex,currentTextureCoords).a;
                //float heightFromTexture = tex2D(_MainTex,currentTextureCoords).r;

                //这边是用来计算视差偏移的
                float2 p = _Scele*TangentVD.xy/TangentVD.z/nNamberSamples ;

                [unroll(60)]
                while(h > currentHeight)
                {   
                   
                    currentHeight += layerheight;
                    currentTextureCoords -= p;
                    h =1-tex2D(_MainTex,currentTextureCoords).a;
                    // if (h<=currentHeight)
                    // {
                    //     break;
                    // }
                }
                
                float2 prevTCoords = currentTextureCoords + p;
                float nextH = h - currentHeight ;
                float prevH =  (1-tex2D(_MainTex,prevTCoords).a) - currentHeight + layerheight ;

                float weight = nextH/(nextH - prevH);

                float2 finalTexcoods = prevTCoords * weight + currentTextureCoords * (1.0-weight) ;
                ParallaxHeight = currentHeight + prevH * weight + nextH * (1.0 - weight);






                return finalTexcoods;
            }


            //shadow
            float ParallaxSoftShadow (in float3 lightD,in float3 L , in float3 normalD, in float2 initialTexCoord ,in float initialHeight)
            {
                float shadowMultiplier = 1;

                float minLayers = 1;
                float maxLayers = 24;

                 // calculate lighting only for surface oriented to the light source
                if(dot(normalD, lightD) > 0)
                {
                // calculate initial parameter
                float numSamplesUnderSurface    = 0;
                shadowMultiplier    = 0;
                float numLayers    = lerp(maxLayers, minLayers, abs(dot(normalD, lightD)));
                float layerHeight    = initialHeight / numLayers;
                float2 texStep    = _Scele * L.xy / L.z / numLayers;

                 // current parameters
                float currentLayerHeight    = initialHeight - layerHeight;
                float2 currentTextureCoords    = initialTexCoord + texStep;
                float heightFromTexture    = (1-tex2D(_MainTex,currentTextureCoords).a);
                int stepIndex    = 1;

                // while point is below depth 0.0 )
                [unroll(24)]
                while(currentLayerHeight > 0)
                {
                    // if point is under the surface
                    if(heightFromTexture < currentLayerHeight)
                    {
                     // calculate partial shadowing factor
                        numSamplesUnderSurface    += 1;
                        float newShadowMultiplier    = (currentLayerHeight - heightFromTexture) *
                                                         (1.0 - stepIndex / numLayers);
                     shadowMultiplier    = max(shadowMultiplier, newShadowMultiplier);
                     }

                    // offset to the next layer
                     stepIndex    += 1;
                     currentLayerHeight    -= layerHeight;
                     currentTextureCoords    += texStep;
                    heightFromTexture    = (1-tex2D(_MainTex,currentTextureCoords).a);
                  }

                // Shadowing factor should be 1 if there were no points under the surface
                 if(numSamplesUnderSurface < 1)
                {
                    shadowMultiplier = 1;
                }
                else
                {
                    shadowMultiplier = pow(1 - shadowMultiplier,16);
                }
            }
            else{
                shadowMultiplier = 0;
            }
            return shadowMultiplier;
            }
        



            v2f vert (appdata_full v)
            {
                v2f o;
                o.normalDir = UnityObjectToWorldNormal(v.normal);
                o.tangentDir =normalize(mul(unity_ObjectToWorld,float4(v.tangent.xyz,0.0)).xyz);
                o.bittangentDir =normalize(cross(o.normalDir,o.tangentDir)*v.tangent.w);
                o.posWorld = mul(unity_ObjectToWorld,v.vertex);
                o.pos = UnityObjectToClipPos(v.vertex); 
                o.uv = TRANSFORM_TEX(v.texcoord,_MainTex);
                //光线
                TRANSFER_VERTEX_TO_FRAGMENT(o)
               
                //o.ambient = ShadeSH9(half4(o.normalDir,1));
                //TRANSFER_SHADOW(O)
                //TRANSFER_SHADOW(o)
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {   
               float attenuation = LIGHT_ATTENUATION(i);


                float3x3 tangentTransform = float3x3(i.tangentDir,i.bittangentDir,i.normalDir);

               

                //视线方向
                float3 viewDirection = normalize(_WorldSpaceCameraPos.xyz - i.posWorld.xyz);

                float ParallaxHeight = 0;

                //NORMAL
                i.normalDir = normalize(i.normalDir);
                
                float3 TangentVD = mul(tangentTransform,viewDirection).xyz;


                float2 po =parallaxmaping(TangentVD,viewDirection,i,i.uv,ParallaxHeight);


                //光线方向
                float3 lightDirection = normalize(_WorldSpaceLightPos0.xyz);

                //Half
                float3 HalfDir = normalize(lightDirection + viewDirection);

                float3 TangentLD =normalize(mul(tangentTransform,lightDirection));

                




                
                float3 Basecolor = tex2D(_base,po);//Basecolor     


                 //TEXTURE
                float RouG = tex2D(_MainTex,po).g ;//Roughness
                float AO = tex2D(_MainTex,po).b ;
                float Metal = tex2D(_MainTex,po).r;
                
                //float3 ParallaxTexNor = tex2D(_normal)
                float me = pow(_metal*Metal,2.19);
                AO = pow(AO,2.19);

                //normal map部分
                float3 _normal_var = UnpackNormal(tex2D(_normal,po));
                float3 normalaLocal = float3(_normal_var.x,-1*_normal_var.y,_normal_var.z);
                float3 normalDirectionMap = normalize(mul(normalaLocal,tangentTransform));


                //SELFSHADOW   ???????????????????????????????????????????????????????????????????????????
                float SelfShadow =  ParallaxSoftShadow (lightDirection,TangentLD, normalDirectionMap , po ,1-tex2D(_MainTex,po).a);
                
                

                //HighLight 
                float lh =  max(0.00001,dot(lightDirection,HalfDir));
                float PI = 3.141592653589793238462 ;
                float hfdot =max(0.00001,dot(HalfDir,normalDirectionMap));
                float h2 = hfdot*hfdot ;
                float r1 = pow(_roughness*RouG,2.19); 
                float r2 = r1*r1;
                float D =r2/(PI*(h2*(r2-1)+1)*(h2*(r2-1)+1));

                //Lambert
                float ln = max(0,dot(lightDirection,normalDirectionMap));
                float vn = max(0,dot(viewDirection,normalDirectionMap));
                float k = ((r1 + 1)*(r1 + 1))/8 ;
                float G =(ln /lerp(ln,1,k)) * (vn/lerp(vn,1,k)); 

                //Fresnel 
                float F0 = lerp(0.04,Basecolor.r,_metal*Metal) ;
                float F = lerp((pow((1-vn),5)),1,F0) ;

                //漫反射部分
                float3 DiffuseReflection = Basecolor ;

                //DGF配平镜面反射部分
                // float DGF = (D*G*F) / (4*(vn)*(ln)) ;
                float ln2 = max(0.7,ln);                       // 这边0.7也是瞎加的
                float vn2 = max(0.001,vn);                       // 这边0.001也是瞎加的  配平系数
                float DGF = (D*G*F) / (4*(vn2)*(ln2)) ;

                    
                    
                //ambient
                 i.ambient = ShadeSH9(half4(normalDirectionMap,1));

                //reflection
                half3 worldViewDir = normalize(UnityWorldSpaceViewDir(i.posWorld));
                half3 worldRefl = reflect(-worldViewDir, normalDirectionMap);
                half4 skyData = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, worldRefl,_roughness*9*RouG);
                half3 skyColor = DecodeHDR (skyData, unity_SpecCube0_HDR);

                //FinalColor
                float3 finalColor =
                ((
                
                DiffuseReflection * (i.ambient + fixed3(G,G,G)*attenuation*_LightColor0.rgb*SelfShadow) * (1-me) *(1-F)      //漫反射
                // /PI   //能量守恒？？？？？？
                + DGF*attenuation*_LightColor0.rgb *SelfShadow
                + skyColor * F *saturate(1-r1)    //这边1是瞎配的
                //+ HighLight d
                )
                // *ln
                // *PI
                
                // +i.ambient*0.1
                // +skyColor*0.1
                )
                *AO
                
                ;
                // fixed shadow = SHADOW_ATTENUATION(i);
               



                
                

                //fixed4 f = fixed4 (finalColor.r,0,0,1);

                //float3 viewDir = normalize(UnityWorldSpaceViewDir);
                return fixed4(finalColor,1);
                // return fixed4(po,0,1);
                // return SelfShadow;
                // return fixed4(DiffuseReflection * (i.ambient + fixed3(G,G,G)) /PI,1);
                // return fixed4(TangentLD,1);
            }

            
            ENDCG
        }
         //UsePass "Legacy Shaders/VertexLit/SHADOWCASTER"
        
    }
    
    Fallback "Diffuse"
}
