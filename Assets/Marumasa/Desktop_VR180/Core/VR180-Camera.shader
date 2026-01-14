Shader "Marumasa/VR180-Camera"
{
	Properties
	{
		// 左目用のパノラマテクスチャ（スケール・オフセットなし、単一行）
		[NoScaleOffset][SingleLineTexture] _LeftEyeTex( "LeftEye-Atlas", 2D ) = "black" {}
		// 右目用のパノラマテクスチャ（スケール・オフセットなし、単一行）
		[NoScaleOffset][SingleLineTexture] _RightEyeTex( "RightEye-Atlas", 2D ) = "black" {}
		// アルファクリップ用の閾値（マスク用）
		_Cutoff( "Mask Clip Value", Float ) = 0.5
		// インスペクターでは非表示にする内部用フラグ（保存用）
		[HideInInspector] __dirty( "", Int ) = 1
	}

	SubShader
	{
		// レンダリング設定：オーバーレイとして描画、バッチ処理無効、自己発光あり
		Tags{ "RenderType" = "Overlay"  "Queue" = "Overlay+1000" "DisableBatching" = "True" "IsEmissive" = "true"  }
		// カリング設定：表面をカリング（裏面を描画、内側から見るため）
		Cull Front
		// Zバッファ書き込み有効
		ZWrite On
		// Zテスト：常に描画（深度に関わらず最前面に表示）
		ZTest Always
		
		CGPROGRAM
		// 一般的なUnityシェーダー変数を含むインクルードファイル
		#include "UnityShaderVariables.cginc"
		// コンパイルターゲットを3.5に設定
		#pragma target 3.5
		// サーフェスシェーダー設定：Unlit（ライティングなし）、アルファ維持、影追加、環境光なし、頂点ライトなし、ライトマップなし等、不要な機能を無効化
		#pragma surface surf Unlit keepalpha addshadow fullforwardshadows noambient novertexlights nolightmap  nodynlightmap nodirlightmap nofog nometa noforwardadd vertex:vertexDataFunc 
		
		// 入力構造体の定義
		struct Input
		{
			float4 screenPos; // スクリーン座標
		};

		// ユニフォーム変数の宣言（プロパティと対応）
		uniform sampler2D _LeftEyeTex;  // 左目テクスチャ
		uniform sampler2D _RightEyeTex; // 右目テクスチャ
		uniform float _Cutoff = 0.5;    // カットオフ値

		// 頂点シェーダー関数
		// 頂点位置を操作してデータをInput構造体に渡す
		void vertexDataFunc( inout appdata_full v, out Input o )
		{
			// Input構造体の初期化
			UNITY_INITIALIZE_OUTPUT( Input, o );
			// オブジェクト空間の頂点位置を取得
			float3 ase_positionOS = v.vertex.xyz;
			// 頂点座標を10倍に拡大（巨大な球体やドームとして扱うため）
			v.vertex.xyz += ( ase_positionOS * 10 );
			// 同次座標のw成分を1に設定
			v.vertex.w = 1;
		}

		// ライティング関数（Unlit）
		// ライティング計算を行わず、単に黒色とアルファ値を返す（Emissionで色を出すため）
		inline half4 LightingUnlit( SurfaceOutput s, half3 lightDir, half atten )
		{
			return half4 ( 0, 0, 0, s.Alpha );
		}


		// サーフェスシェーダー関数（ピクセルごとの処理）
		void surf( Input i , inout SurfaceOutput o )
		{
			// スクリーン座標の取得とw成分の微小値加算によるゼロ除算防止
			float4 ase_positionSS = float4( i.screenPos.xyz , i.screenPos.w + 1e-7 );
			// スクリーン座標の正規化（パースペクティブ除算）
			float4 ase_positionSSNorm = ase_positionSS / ase_positionSS.w;
			// ニアクリップ面に近い場合のZ値の補間処理（深度の調整）
			ase_positionSSNorm.z = lerp(ase_positionSSNorm.z * 0.5 + 0.5, ase_positionSSNorm.z, step(0, UNITY_NEAR_CLIP_VALUE));

			// 左右の目の判定（スクリーンX座標が0.5以上なら右目）
			float isRightEye = step(0.5, ase_positionSSNorm.x);

			// ViewportごとのローカルX座標（0～1）を算出
			// 左目(0.0-0.5) -> (0.0-1.0), 右目(0.5-1.0) -> (0.0-1.0)
			float xLocal = (ase_positionSSNorm.x - 0.5 * isRightEye) * 2.0;

			// 画面座標（0~1）をラジアン範囲（-PI/2 ~ PI/2 = 180度）にマッピング
			// Optimized: remove redundant temp variables and calculation
			// inputPos range [0, 1] -> [-PI/2, PI/2]
			float2 inputPos = float2(xLocal, ase_positionSSNorm.y);
			float2 break6 = inputPos * UNITY_PI - (UNITY_PI * 0.5).xx;
			
			// 球面座標系の計算
			float lat = break6.y / 2.0; // 緯度 (Y軸方向) 注意：元のロジックを維持して / 2.0
			float lon = break6.x;       // 経度 (X軸方向)

			float sinLat, cosLat;
			sincos(lat, sinLat, cosLat);

			float sinLon, cosLon;
			sincos(lon, sinLon, cosLon);
			
			// 緯度経度から3次元の方向ベクトル（球体上の位置）を算出
			float3 SphereVector18 = float3(cosLat * sinLon, sinLat, cosLat * cosLon);

			// Transform World Vector to Right Camera Local Frame (+45 deg Y-rotation)
			// effectively rotating the vector by -45 degrees around Y
			float k = 0.7071068;
			float3 rotV;
			rotV.x = k * (SphereVector18.x - SphereVector18.z);
			rotV.y = SphereVector18.y;
			rotV.z = k * (SphereVector18.x + SphereVector18.z);
			
			// キューブマップ展開のための面判定ロジック
			float3 absV = abs(rotV); // ベクトルの絶対値
			// 支配的な軸（絶対値が最大の軸）を判定
			float zDom = step(absV.x, absV.z) * step(absV.y, absV.z); // Z成分が最大か
			float xDom = step(absV.y, absV.x) * (1.0 - zDom);         // X成分が最大か（かつZではない）
			float yDom = 1.0 - zDom - xDom;                           // Y成分が最大か（残りの場合）

			// ベクトルの向きと支配的な軸から、どの面（Front, Left, Right, Up, Down）に対応するかを判定
			// In Right Camera Frame:
			// +Z (Front) -> Right Camera View (Slot 0)
			// -X (Left)  -> Left Camera View (which is at -90 deg relative to Right Cam) (Slot 1)
			// +Y (Up)    -> Up Camera View (Slot 2)
			// -Y (Down)  -> Down Camera View (Slot 3)
			
			float isFront = zDom * step(0, rotV.z);         
			float isLeft  = xDom * (1.0 - step(0, rotV.x)); 
			float isUp    = yDom * step(0, rotV.y);         
			float isDown  = yDom * (1.0 - step(0, rotV.y)); 

			// 各面のローカルUV座標を計算
			// isFront (+Z): u=x/z, v=y/z -> rotV.xy
			// isLeft (-X):  u=z/-x, v=y/-x -> rotV.zy
			// isUp/Down (Y): u=x/y, v=z/y -> rotV.xz
			float2 rawUV = isFront * rotV.xy + 
			               isLeft * rotV.zy + 
			               (isUp + isDown) * rotV.xz;
			
			// 射影のための除数（奥行き成分）
			// Note: for Left (-X), depth is -x = abs(x) since x is negative
			float denom = isFront * absV.z + 
			              isLeft * absV.x + 
			              (isUp + isDown) * absV.y;
			
			// 除算を行って正規化された平面座標を得る（0除算防止付き）
			float2 uv = rawUV / max(denom, 1e-5);
			
			// UVの向き補正（面によって反転が必要な場合がある）
			// Right/Left/Up/Downのローカル座標系定義に依存
			float xScale = 0.5;           
			float yScale = 0.5 - isUp;    // 通常0.5, 上面なら-0.5 (Top-down logic?)
			
			// UVを[0,1]の範囲にリマップ
			uv = uv * float2(xScale, yScale) + 0.5;

			// アトラス上の面インデックスを算出 (0:Right, 1:Left, 2:Up, 3:Down)
			// Slot 0: Right (+Z face in rot frame), Slot 1: Left (-X face in rot frame)
			float faceIndex = isFront * 0.0 + isLeft * 1.0 + isUp * 2.0 + isDown * 3.0;
			
			// アトラス全体のUV座標へ変換
			float2 atlasUV = uv;
			// 横一列（4面分）のアトラスレイアウトに合わせてX座標を縮小・シフト
			atlasUV.x = atlasUV.x * 0.25 + faceIndex * 0.25;

			// 有効な面（Front, Left, Up, Down）のいずれかが選択されているか判定
			float isValidFace = isFront + isLeft + isUp + isDown;

			// 左右それぞれのテクスチャからカラーをサンプリング
			// Optimized: Dynamic branching to avoid fetching both textures
			float4 finalColor;
			if (isRightEye > 0.5)
			{
				finalColor = tex2D(_RightEyeTex, atlasUV);
			}
			else
			{
				finalColor = tex2D(_LeftEyeTex, atlasUV);
			}
			
			// 無効な面なら黒にする
			finalColor *= isValidFace;

			// 最終出力を設定
			o.Emission = finalColor.rgb; // 発光色として設定
			o.Alpha = 1;                 // アルファは不透明
			
			// 画面アスペクト比に基づいた円形マスク等のクリッピング処理
			clip( ( finalColor.a * abs( sign( ( _ScreenParams.x - _ScreenParams.y ) ) ) ) - _Cutoff );
		}

		ENDCG
	}
	// フォールバックシェーダー設定
	Fallback "Diffuse"
}