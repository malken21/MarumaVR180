Shader "Marumasa/VR180-Preview"
{
    Properties
    {
        // 右、前、上、下 の順に並んだ 4:1 のテクスチャ
        [NoScaleOffset][SingleLineTexture] _LeftEyeTex( "LeftEye-Atlas", 2D ) = "black" {}
        [NoScaleOffset][SingleLineTexture] _RightEyeTex( "RightEye-Atlas", 2D ) = "black" {}

    }
    SubShader
    {
	Tags
		{
			"RenderType" = "Overlay"
			"Queue" = "Overlay+1000"
			"DisableBatching" = "True"
			"IsEmissive" = "true"
		}
		
		Cull Front
		ZWrite On
		ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float3 viewDir : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _LeftEyeTex;
            sampler2D _RightEyeTex;


            // 頂点シェーダーは視線ベクトルを計算
            v2f vert (appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                
                o.vertex = UnityObjectToClipPos(v.vertex);
                // ビルボード的な挙動にするため、ビュースペース（カメラ空間）での位置を使用
                // Unityのビュースペースはカメラが原点で、前方(-Z)を向いている
                // そのため、頂点位置そのものがカメラからのベクトルになる
                float3 viewPos = UnityObjectToViewPos(v.vertex);
                
                // Zを反転して、カメラの前方(+Z)を向くように調整
                o.viewDir = float3(viewPos.x, viewPos.y, -viewPos.z);
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
                    // 上下面のマスク処理: 水平方向のブラックアウト領域に合わせる
                    // X軸方向が支配的かZ軸方向が支配的かで判定
                    if (absDir.x >= absDir.z)
                    {
                        // X軸方向 (右 or 左)
                        // 水平方向と同様に左側は黒
                        if (dir.x < 0) { mask = 0.0; return; }
                    }
                    else
                    {
                        // Z軸方向 (前 or 後)
                        // 水平方向と同様に後ろ側は黒
                        if (dir.z < 0) { mask = 0.0; return; }
                    }


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

                // テクスチャ境界の滲みを防ぐため、0.0-1.0の範囲をわずかに内側にクランプ
                float margin = 0.001;
                u_local = clamp(u_local, margin, 1.0 - margin);
                v_local = clamp(v_local, margin, 1.0 - margin);

                // 4:1テクスチャ上の最終的なUVを計算
                // Uは全体を1/4に縮小し、計算したオフセットを加える
                uv.x = u_local * 0.25 + u_offset;
                uv.y = v_local;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                // 正方形のカメラ（アスペクト比1:1）の場合は描画しない
                float squareScreenMask = abs(sign(_ScreenParams.x - _ScreenParams.y));
                clip(squareScreenMask - 0.5);

                float3 viewDir = normalize(i.viewDir);
                
                float2 textureUV;
                float mask;

                // 45度反時計回りに回転
                float s = 0.70710678;
                float c = 0.70710678;
                float3 rotDir = viewDir;
                rotDir.x = viewDir.x * c + viewDir.z * s;
                rotDir.z = -viewDir.x * s + viewDir.z * c;

                // UVとマスクを計算
                CalculateCubeUV(rotDir, textureUV, mask);

                // マスクが0なら黒を出力して終了
                // step関数を使って分岐を避ける書き方もできますが、分かりやすさ優先でifを使用
                if (mask < 0.5)
                {
                    return fixed4(0,0,0,1);
                }

                // 計算したUVで2Dテクスチャをサンプリング
                // ステレオレンダリング対応: 右目は _RightTex を使用
                fixed4 col;
                if (unity_StereoEyeIndex == 0)
                {
                     col = tex2D(_LeftEyeTex, textureUV);
                }
                else
                {
                     col = tex2D(_RightEyeTex, textureUV);
                }
                


                return col;
            }
            ENDCG
        }
    }
}