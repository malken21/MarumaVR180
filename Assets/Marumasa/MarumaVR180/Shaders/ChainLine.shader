Shader "Marumasa/ChainLine"
{
    Properties
    {
        _Color ("Color", Color) = (1.0, 0.25, 0.25, 1) // 自然な赤 (朱色寄り)
        _Color2 ("Color 2", Color) = (0.95, 0.95, 0.95, 1) // 自然な白 (オフホワイト)
        _Thickness ("Thickness", Float) = 0.01 // 線の太さ (メートル単位)
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
            fixed4 _Color2;
            float _Thickness;

            v2f vert (appdata v)
            {
                v2f o;
                
                // オブジェクトのスケールを無視して、回転と位置のみを適用する
                // unity_ObjectToWorld行列から正規化された基底ベクトル（回転成分）を抽出
                float3 right = normalize(unity_ObjectToWorld._m00_m10_m20);
                float3 up = normalize(unity_ObjectToWorld._m01_m11_m21);
                float3 forward = normalize(unity_ObjectToWorld._m02_m12_m22);
                float3 origin = unity_ObjectToWorld._m03_m13_m23;

                // Z軸方向に無限に伸ばす（10000倍）
                float z = v.vertex.z * 10000;
                
                // ローカル座標をワールド座標へ変換（スケール無視）
                // X, Y 成分に太さ(_Thickness)を適用
                float3 worldPos = origin + right * (v.vertex.x * _Thickness) + up * (v.vertex.y * _Thickness) + forward * z;

                o.worldPos = worldPos;
                o.vertex = mul(UNITY_MATRIX_VP, float4(worldPos, 1.0));
                
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // 正方形のカメラ（アスペクト比1:1）の場合は描画しない for VR180Preview
                if (abs(_ScreenParams.x - _ScreenParams.y) < 0.1) discard;

                // オブジェクト原点からの距離(球状)だと原点付近でパターンが歪む(丸くなる)ため、
                // Z軸ベクトルへの射影距離(直線性)を使用する
                float3 objectOrigin = mul(unity_ObjectToWorld, float4(0,0,0,1)).xyz;
                float3 objectZAxis = normalize(mul(unity_ObjectToWorld, float4(0,0,1,0)).xyz);
                
                float3 vec = i.worldPos - objectOrigin;
                float dist = abs(dot(vec, objectZAxis));
                
                float cycle = 0.1;

                // 周期ごとに色を切り替える
                float cycleIndex = floor(dist / cycle);
                return (fmod(cycleIndex, 2.0) == 0.0) ? _Color : _Color2;
            }
            ENDCG
        }
    }
}
