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

		Cull Off

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
                float4 localPos : TEXCOORD0;
            };

            fixed4 _Color;
            fixed4 _Color2;
            float _Thickness;

            v2f vert (appdata v)
            {
                v2f o;

                
                float4 pos = v.vertex;
                pos.x *= _Thickness;
                pos.y *= _Thickness;
                pos.z *= 10000; // Z軸方向に無限に伸ばす（10000倍）

                o.worldPos = worldPos;
                o.vertex = mul(UNITY_MATRIX_VP, float4(worldPos, 1.0));
                
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // 正方形のカメラ（アスペクト比1:1）の場合は描画しない for VR180-Camera
                if (abs(_ScreenParams.x - _ScreenParams.y) < 0.1) discard;

                // 距離はローカル座標のZ成分から直接計算可能
                float dist = abs(i.localPos.z);
                
                float cycle = 0.1;

                // 周期ごとに色を切り替える
                float cycleIndex = floor(dist / cycle);
                return (fmod(cycleIndex, 2.0) == 0.0) ? _Color : _Color2;
            }
            ENDCG
        }
    }
}
