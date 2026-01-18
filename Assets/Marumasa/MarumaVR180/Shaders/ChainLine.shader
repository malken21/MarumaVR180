Shader "Marumasa/ChainLine"
{
    Properties
    {
        _Color ("Color", Color) = (1.0, 0.25, 0.25, 1) // 自然な赤 (朱色寄り)
        _Color2 ("Color 2", Color) = (0.95, 0.95, 0.95, 1) // 自然な白 (オフホワイト)
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 100

		Cull Off

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
                float dist : TEXCOORD1;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            fixed4 _Color;
            fixed4 _Color2;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                // _MainTex_ST might not be set if not in Properties, but safe to use TRANSFORM_TEX if we define it
                o.uv = v.uv; 

                // オブジェクトのZ軸スケールを取得
                float scaleZ = length(float3(unity_ObjectToWorld[0].z, unity_ObjectToWorld[1].z, unity_ObjectToWorld[2].z));
                // ローカルZ位置にスケールを掛けて、実世界での距離（Z軸沿い）を算出
                o.dist = v.vertex.z * scaleZ;

                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // 正方形のカメラ（アスペクト比1:1）の場合は描画しない
                if (abs(_ScreenParams.x - _ScreenParams.y) < 0.1) clip(-1);

                // 0.2m (200mm) 周期で 0.1m (100mm) ごとに色を切り替え
                fixed4 c = (frac(i.dist / 0.2) < 0.5) ? _Color : _Color2;
                
                // _MainTex logic if needed, previously: c *= tex2D (_MainTex, IN.uv_MainTex);
                // Note: TRANSFORM_TEX not strictly needed if _MainTex_ST not populated, but good practice.
                // Assuming simple UV sampling:
                c *= tex2D(_MainTex, i.uv);

                UNITY_APPLY_FOG(i.fogCoord, c);
                return c;
            }
            ENDCG
        }
    }
    FallBack "Diffuse"
}
