Shader "Marumasa/ChainLine"
{
    Properties
    {
        _Color ("Color", Color) = (1,0,0,1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float3 worldPos : TEXCOORD0;
            };

            fixed4 _Color;

            v2f vert (appdata v)
            {
                v2f o;
                // Z軸方向に無限に伸ばす（10000倍）
                v.vertex.z *= 10000;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // 正方形のカメラ（アスペクト比1:1）の場合は描画しない for VR180Preview
                if (abs(_ScreenParams.x - _ScreenParams.y) < 0.1) discard;

                // 100mm (0.1m) 周期の一点鎖線
                // パターン:
                // 0.0 - 0.6 : 線 (0.06m)
                // 0.6 - 0.7 : 空白 (0.01m)
                // 0.7 - 0.8 : 点 (0.01m)
                // 0.8 - 1.0 : 空白 (0.02m)

                // オブジェクト原点からの距離(球状)だと原点付近でパターンが歪む(丸くなる)ため、
                // Z軸ベクトルへの射影距離(直線性)を使用する
                float3 objectOrigin = mul(unity_ObjectToWorld, float4(0,0,0,1)).xyz;
                float3 objectZAxis = normalize(mul(unity_ObjectToWorld, float4(0,0,1,0)).xyz);
                
                float3 vec = i.worldPos - objectOrigin;
                float dist = abs(dot(vec, objectZAxis));
                
                float cycle = 0.1;
                float t = fmod(dist, cycle) / cycle;

                if (t > 0.6 && t < 0.7) discard;
                if (t > 0.8) discard;

                return _Color;
            }
            ENDCG
        }
    }
}
