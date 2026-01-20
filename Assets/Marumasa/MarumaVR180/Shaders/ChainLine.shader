Shader "Marumasa/ChainLine"
{
    Properties
    {
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="BodySurface" }
        LOD 100

        Cull Off

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // カメラとオブジェクトの回転が一致していない場合は描画しない
                // カメラのForwardはUNITY_MATRIX_I_Vの第3列（Z軸）の逆方向（OpenGL規約のため）
                float3 camFwd = -normalize(float3(UNITY_MATRIX_I_V._m02, UNITY_MATRIX_I_V._m12, UNITY_MATRIX_I_V._m22));
                float3 camUp = normalize(float3(UNITY_MATRIX_I_V._m01, UNITY_MATRIX_I_V._m11, UNITY_MATRIX_I_V._m21));

                float3 objFwd = normalize(float3(unity_ObjectToWorld._m02, unity_ObjectToWorld._m12, unity_ObjectToWorld._m22));
                float3 objUp = normalize(float3(unity_ObjectToWorld._m01, unity_ObjectToWorld._m11, unity_ObjectToWorld._m21));

                if (dot(camFwd, objFwd) > 0.999 && dot(camUp, objUp) > 0.999 && abs(_ScreenParams.x - _ScreenParams.y) < 0.1 ) discard;

                fixed4 c = tex2D(_MainTex, i.uv);
                return c;
            }
            ENDCG
        }
    }
    FallBack "Unlit/Texture"
}
