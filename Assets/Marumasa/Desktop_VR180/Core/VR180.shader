Shader "Marumasa/VR180-Camera"
{
	Properties
	{
		// 左目用のパノラマテクスチャ（スケール・オフセットなし、単一行）
		[NoScaleOffset][SingleLineTexture] _LeftEyeTex( "LeftEye-Atlas", 2D ) = "black" {}
		// 右目用のパノラマテクスチャ（スケール・オフセットなし、単一行）
		[NoScaleOffset][SingleLineTexture] _RightEyeTex( "RightEye-Atlas", 2D ) = "black" {}
		
		// 画面サイズ設定
		_ScreenWidth( "Screen Width", Float ) = 16
		_ScreenHeight( "Screen Height", Float ) = 9
		
		// デバッグ・マスク設定
		[Toggle] _DebugMode( "DebugMode", Float ) = 0
		_Cutoff( "Mask Clip Value", Float ) = 0.5
		[HideInInspector] __dirty( "", Int ) = 1
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
		
		CGPROGRAM
		#include "UnityShaderVariables.cginc"
		#pragma target 3.5
		#define ASE_VERSION 19900
		#pragma surface surf Unlit keepalpha addshadow fullforwardshadows noambient novertexlights nolightmap nodynlightmap nodirlightmap nofog nometa noforwardadd vertex:vertexDataFunc

		// ========================================
		// 入力構造体
		// ========================================
		struct Input
		{
			float4 screenPos;
		};

		// ========================================
		// テクスチャサンプラー
		// ========================================
		uniform sampler2D _LeftEyeTex;
		uniform sampler2D _RightEyeTex;

		// ========================================
		// ユニフォーム変数
		// ========================================
		uniform float _DebugMode;
		uniform float _ScreenWidth;
		uniform float _ScreenHeight;
		uniform float _Cutoff = 0.5;

		// ========================================
		// 頂点シェーダー: メッシュを拡大してオーバーレイ表示
		// ========================================
		void vertexDataFunc( inout appdata_full v, out Input o )
		{
			UNITY_INITIALIZE_OUTPUT( Input, o );
			float3 positionOS = v.vertex.xyz;
			v.vertex.xyz += ( positionOS * 10 );
			v.vertex.w = 1;
		}

		// ========================================
		// ライティング関数: Unlit (照明無効)
		// ========================================
		inline half4 LightingUnlit( SurfaceOutput s, half3 lightDir, half atten )
		{
			return half4( 0, 0, 0, s.Alpha );
		}

		// ========================================
		// UV座標を範囲変換するヘルパー関数
		// ========================================
		float2 RemapUV( float2 value, float2 fromMin, float2 fromMax, float2 toMin, float2 toMax )
		{
			return toMin + ( value - fromMin ) * ( toMax - toMin ) / ( fromMax - fromMin );
		}

		// ========================================
		// 面の有効マスクを計算するヘルパー関数
		// ========================================
		float ComputeFaceMask( float2 uv )
		{
			float2 floorUV = 1.0 - floor( uv );
			float2 ceilUV = ceil( uv );
			return floorUV.x * floorUV.y * ceilUV.x * ceilUV.y;
		}

		// ========================================
		// サーフェスシェーダー: VR180投影処理
		// ========================================
		void surf( Input i, inout SurfaceOutput o )
		{
			// --------------------------------------------
			// スクリーン座標の正規化
			// --------------------------------------------
			float4 screenPos = float4( i.screenPos.xyz, i.screenPos.w + 1e-7 );
			float4 screenPosNorm = screenPos / screenPos.w;
			screenPosNorm.z = ( UNITY_NEAR_CLIP_VALUE >= 0 ) ? screenPosNorm.z : screenPosNorm.z * 0.5 + 0.5;

			// --------------------------------------------
			// 正規化座標を極座標(-π ~ π)に変換
			// --------------------------------------------
			float2 polarCoords = RemapUV(
				screenPosNorm.xy,
				float2( 0, 0 ), float2( 1, 1 ),
				float2( -UNITY_PI, -UNITY_PI ), float2( UNITY_PI, UNITY_PI )
			);
			float azimuth = polarCoords.x + radians( 45.0 );  // 水平角 (45度オフセット)
			float elevation = polarCoords.y / 2.0;            // 垂直角 (半分にスケール)

			// --------------------------------------------
			// 球面座標から3Dベクトルを生成
			// --------------------------------------------
			float cosElevation = cos( elevation );
			float3 sphereVector = float3(
				cosElevation * sin( azimuth ),
				sin( elevation ),
				cosElevation * cos( azimuth )
			);

			// --------------------------------------------
			// 各軸平面への投影による角度計算
			// --------------------------------------------
			float3 vecYZ = normalize( float3( 0.0, sphereVector.y, sphereVector.z ) );
			float3 vecXY = normalize( float3( sphereVector.x, sphereVector.y, 0.0 ) );
			float3 vecXZ = normalize( float3( sphereVector.x, 0.0, sphereVector.z ) );

			float dotYZ = dot( vecYZ, sphereVector );
			float dotXY = dot( vecXY, sphereVector );
			float dotXZ = dot( vecXZ, sphereVector );

			float3 projectionAngles = float3( dotYZ, dotXY, dotXZ );
			float3 sinAngles = sqrt( 1.0 - ( projectionAngles * projectionAngles ) );

			// --------------------------------------------
			// 各面への投影UV座標を計算
			// --------------------------------------------
			float2 projectedYZ = ( 1.0 / sinAngles.x ) * sphereVector.yz;
			float2 projectedXY = ( 1.0 / sinAngles.y ) * sphereVector.xy;
			float2 projectedXZ = ( 1.0 / sinAngles.z ) * sphereVector.xz;

			// --------------------------------------------
			// 左側面 (LeftEye-L): X負方向を向く面
			// --------------------------------------------
			float2 uvLeftL = saturate( RemapUV( projectedYZ, float2( -1, -1 ), float2( 1, 1 ), float2( 0, 0 ), float2( 1, 1 ) ) );
			float2 uvLeftL_swapped = float2( uvLeftL.y, uvLeftL.x );
			float maskLeftL = ComputeFaceMask( uvLeftL );
			float visLeftL = saturate( ceil( dot( sphereVector, float3( -1, 0, 0 ) ) ) );

			// --------------------------------------------
			// 右側面 (RightEye-L): X正方向を向く面
			// --------------------------------------------
			float2 uvRightL = saturate( RemapUV( projectedYZ, float2( -1, 1 ), float2( 1, -1 ), float2( 0, 0 ), float2( 1, 1 ) ) );
			float2 uvRightL_swapped = float2( uvRightL.y, uvRightL.x );
			float maskRightL = ComputeFaceMask( uvRightL );
			float visRightL = saturate( ceil( dot( sphereVector, float3( 1, 0, 0 ) ) ) );

			// --------------------------------------------
			// 後面 (RightEye-R): Z負方向を向く面
			// --------------------------------------------
			float2 uvRightR = saturate( RemapUV( projectedXY, float2( 1, -1 ), float2( -1, 1 ), float2( 0, 0 ), float2( 1, 1 ) ) );
			float maskRightR = ComputeFaceMask( uvRightR );
			float visRightR = saturate( ceil( dot( sphereVector, float3( 0, 0, -1 ) ) ) );

			// --------------------------------------------
			// 前面 (LeftEye-R): Z正方向を向く面
			// --------------------------------------------
			float2 uvLeftR = saturate( RemapUV( projectedXY, float2( -1, -1 ), float2( 1, 1 ), float2( 0, 0 ), float2( 1, 1 ) ) );
			float maskLeftR = ComputeFaceMask( uvLeftR );
			float visLeftR = saturate( ceil( dot( sphereVector, float3( 0, 0, 1 ) ) ) );

			// --------------------------------------------
			// 下面 (DOWN): Y負方向を向く面
			// --------------------------------------------
			float2 uvDown = saturate( RemapUV( projectedXZ, float2( -1, -1 ), float2( 1, 1 ), float2( 0, 0 ), float2( 1, 1 ) ) );
			float maskDown = ComputeFaceMask( uvDown );
			float visDown = saturate( ceil( dot( sphereVector, float3( 0, -1, 0 ) ) ) );

			// --------------------------------------------
			// 上面 (UP): Y正方向を向く面
			// --------------------------------------------
			float2 uvUp = saturate( RemapUV( projectedXZ, float2( -1, 1 ), float2( 1, -1 ), float2( 0, 0 ), float2( 1, 1 ) ) );
			float maskUp = ComputeFaceMask( uvUp );
			float visUp = saturate( ceil( dot( sphereVector, float3( 0, 1, 0 ) ) ) );

			// --------------------------------------------
			// 左右の目の判定 (画面中央で分割)
			// --------------------------------------------
			float isRightEye = saturate( ceil( -0.5 + screenPosNorm.x ) );
			float isLeftEye = 1.0 - isRightEye;

			// --------------------------------------------
			// 各面のテクスチャをサンプリングして合成
			// アトラスレイアウト (4x1横並び, 5760x1440):
			//   X=0.00-0.25: R面
			//   X=0.25-0.50: L面
			//   X=0.50-0.75: UP面
			//   X=0.75-1.00: DOWN面
			// --------------------------------------------
			
			// アトラスUV変換: 各面UV(0-1)を対応する領域(0.25スケール+オフセット)に変換
			float atlasR_offsetX    = 0.00;  // R面
			float atlasL_offsetX    = 0.25;  // L面
			float atlasUP_offsetX   = 0.50;  // UP面
			float atlasDOWN_offsetX = 0.75;  // DOWN面
			
			// 左目テクスチャからサンプリング用UV計算
			float2 uvAtlasLeftL   = float2( uvLeftL_swapped.x * 0.25 + atlasL_offsetX, uvLeftL_swapped.y );
			float2 uvAtlasLeftR   = float2( uvLeftR.x * 0.25 + atlasR_offsetX, uvLeftR.y );
			float2 uvAtlasLeftUP  = float2( uvUp.x * 0.25 + atlasUP_offsetX, uvUp.y );
			float2 uvAtlasLeftDOWN = float2( uvDown.x * 0.25 + atlasDOWN_offsetX, uvDown.y );
			
			// 右目テクスチャからサンプリング用UV計算
			float2 uvAtlasRightL   = float2( uvRightL_swapped.x * 0.25 + atlasL_offsetX, uvRightL_swapped.y );
			float2 uvAtlasRightR   = float2( uvRightR.x * 0.25 + atlasR_offsetX, uvRightR.y );
			float2 uvAtlasRightUP  = float2( uvUp.x * 0.25 + atlasUP_offsetX, uvUp.y );
			float2 uvAtlasRightDOWN = float2( uvDown.x * 0.25 + atlasDOWN_offsetX, uvDown.y );
			
			// 左目アトラスからサンプリング
			float4 colorLeftL = tex2D( _LeftEyeTex, uvAtlasLeftL ) * maskLeftL * visLeftL;
			float4 colorLeftR = tex2D( _LeftEyeTex, uvAtlasLeftR ) * maskLeftR * visLeftR;
			float4 colorLeftUp = tex2D( _LeftEyeTex, uvAtlasLeftUP ) * maskUp * visUp * isLeftEye;
			float4 colorLeftDown = tex2D( _LeftEyeTex, uvAtlasLeftDOWN ) * maskDown * visDown * isLeftEye;
			
			// 右目アトラスからサンプリング
			float4 colorRightL = tex2D( _RightEyeTex, uvAtlasRightL ) * maskRightL * visRightL;
			float4 colorRightR = tex2D( _RightEyeTex, uvAtlasRightR ) * maskRightR * visRightR;
			float4 colorRightUp = tex2D( _RightEyeTex, uvAtlasRightUP ) * maskUp * visUp * isRightEye;
			float4 colorRightDown = tex2D( _RightEyeTex, uvAtlasRightDOWN ) * maskDown * visDown * isRightEye;

			float4 finalColor = colorLeftL + colorLeftR + colorLeftUp + colorLeftDown
			                  + colorRightL + colorRightR + colorRightUp + colorRightDown;

			// --------------------------------------------
			// 出力設定
			// --------------------------------------------
			o.Emission = finalColor.rgb;
			o.Alpha = 1;

			// --------------------------------------------
			// アスペクト比に基づくマスク処理
			// --------------------------------------------
			float screenAspect = _ScreenParams.x / _ScreenParams.y;
			float targetAspect = _ScreenWidth / _ScreenHeight;
			float aspectDiff = abs( sign( screenAspect - targetAspect ) );
			float aspectMask = _DebugMode ? 1.0 : ( 1.0 - aspectDiff );
			float squareScreenMask = abs( sign( _ScreenParams.x - _ScreenParams.y ) );
			
			clip( finalColor.a * squareScreenMask * aspectMask - _Cutoff );
		}

		ENDCG
	}
	Fallback "Diffuse"
}