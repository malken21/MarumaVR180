Shader "Custom/VisionJack4x1"
{
    Properties
    {
        // 右、前、上、下 の順に並んだ 4:1 のテクスチャ
        [NoScaleOffset] _MainTex ("4:1 Texture (R, F, U, D)", 2D) = "black" {}
        _Exposure ("Exposure (Brightness)", Range(0, 8)) = 1.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 100

        // 両面描画
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
                float3 worldViewDir : TEXCOORD0;
            };

            sampler2D _MainTex;
            float _Exposure;

            // 頂点シェーダーは前回と同じく視線ベクトルを計算
            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.worldViewDir = worldPos - _WorldSpaceCameraPos;
                return o;
            }

            // 視線ベクトルを元に、4:1テクスチャ上のUVと、描画マスク(1=表示, 0=黒)を計算する関数
            // テクスチャレイアウト: [ Right(+X) | Front(+Z) | Up(+Y) | Down(-Y) ]
            void CalculateCubeUV(float3 dir, out float2 uv, out float mask)
            {
                float3 absDir = abs(dir);
                mask = 1.0; // 初期値は表示
                uv = float2(0,0);
                
                float u_local, v_local;
                float u_offset;

                // どの軸方向が支配的かによって分岐
                if (absDir.x >= absDir.y && absDir.x >= absDir.z)
                {
                    // X軸方向 (右 or 左)
                    if (dir.x > 0) {
                        // 右面 (+X) -> テクスチャの左端 (Offset 0.0)
                        // 投影面ZY基準: Uは-Z方向, Vは+Y方向
                        u_local = 0.5 * (-dir.z / absDir.x) + 0.5;
                        v_local = 0.5 * ( dir.y / absDir.x) + 0.5;
                        u_offset = 0.0;
                    } else { mask = 0.0; return; } // 左面は黒
                }
                else if (absDir.y >= absDir.x && absDir.y >= absDir.z)
                {
                    if (dir.y > 0) {
                        // 上面 (+Y) -> テクスチャの3番目 (Offset 0.5)
                        // 90度右回転: u_new = v_old, v_new = 1.0 - u_old
                        float u_orig = 0.5 * ( dir.x / absDir.y) + 0.5;
                        float v_orig = 0.5 * (-dir.z / absDir.y) + 0.5;
                        
                        u_local = v_orig;
                        v_local = 1.0 - u_orig;
                        u_offset = 0.50;
                    } else {
                        // 下面 (-Y) -> テクスチャの右端 (Offset 0.75)
                        // -90度(左)回転: u_new = 1.0 - v_old, v_new = u_old
                        float u_orig = 0.5 * ( dir.x / absDir.y) + 0.5;
                        float v_orig = 0.5 * ( dir.z / absDir.y) + 0.5;

                        u_local = 1.0 - v_orig;
                        v_local = u_orig;
                        u_offset = 0.75;
                    }
                }
                else
                {
                    // Z軸方向 (前 or 後)
                    if (dir.z > 0) {
                        // 前面 (+Z) -> テクスチャの2番目 (Offset 0.25)
                        // 投影面XY基準: Uは+X方向, Vは+Y方向
                        u_local = 0.5 * ( dir.x / absDir.z) + 0.5;
                        v_local = 0.5 * ( dir.y / absDir.z) + 0.5;
                        u_offset = 0.25;
                    } else { mask = 0.0; return; } // 後面は黒
                }

                // 4:1テクスチャ上の最終的なUVを計算
                // Uは全体を1/4に縮小し、計算したオフセットを加える
                uv.x = u_local * 0.25 + u_offset;
                uv.y = v_local;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float3 viewDir = normalize(i.worldViewDir);
                
                float2 textureUV;
                float mask;

                // UVとマスクを計算
                CalculateCubeUV(viewDir, textureUV, mask);

                // マスクが0なら黒を出力して終了
                // step関数を使って分岐を避ける書き方もできますが、分かりやすさ優先でifを使用
                if (mask < 0.5)
                {
                    return fixed4(0,0,0,1);
                }

                // 計算したUVで2Dテクスチャをサンプリング
                fixed4 col = tex2D(_MainTex, textureUV);
                col.rgb *= _Exposure;

                return col;
            }
            ENDCG
        }
    }
}