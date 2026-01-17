Shader "Marumasa/VR180-Camera"
{
	Properties
	{
		// 左目用テクスチャ
		[NoScaleOffset][SingleLineTexture] _LeftEyeTex( "LeftEye-Atlas", 2D ) = "black" {}
		// 右目用テクスチャ
		[NoScaleOffset][SingleLineTexture] _RightEyeTex( "RightEye-Atlas", 2D ) = "black" {}
		
		// 画面サイズ
		_ScreenWidth( "Screen Width", Float ) = 16
		_ScreenHeight( "Screen Height", Float ) = 9
		
		// デバッグ設定
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

		struct Input
		{
			float4 screenPos;
		};

		uniform sampler2D _LeftEyeTex;
		uniform sampler2D _RightEyeTex;

		uniform float _DebugMode;
		uniform float _ScreenWidth;
		uniform float _ScreenHeight;
		uniform float _Cutoff = 0.5;
		uniform int _VRChatCameraMode;

		// 頂点シェーダー
		void vertexDataFunc( inout appdata_full v, out Input o )
		{
			UNITY_INITIALIZE_OUTPUT( Input, o );
			float3 positionOS = v.vertex.xyz;
			v.vertex.xyz += ( positionOS * 10 );
			v.vertex.w = 1;
		}

		// ライティング無効化
		inline half4 LightingUnlit( SurfaceOutput s, half3 lightDir, half atten )
		{
			return half4( 0, 0, 0, s.Alpha );
		}

		// UVリマップ
		float2 RemapUV( float2 value, float2 fromMin, float2 fromMax, float2 toMin, float2 toMax )
		{
			return toMin + ( value - fromMin ) * ( toMax - toMin ) / ( fromMax - fromMin );
		}

		// マスク計算
		float ComputeFaceMask( float2 uv )
		{
			float2 floorUV = 1.0 - floor( uv );
			float2 ceilUV = ceil( uv );
			return floorUV.x * floorUV.y * ceilUV.x * ceilUV.y;
		}

		// サーフェスシェーダー
		void surf( Input i, inout SurfaceOutput o )
		{
			if ( _VRChatCameraMode == 2 ) discard;
			float asymmetric = abs( unity_CameraProjection[0][2] );
			bool isVR = asymmetric > 0.001;

			if ( _VRChatCameraMode == 0 && isVR ) discard;

			// スクリーン座標の正規化
			float4 screenPos = float4( i.screenPos.xyz, i.screenPos.w + 1e-7 );
			float4 screenPosNorm = screenPos / screenPos.w;
			screenPosNorm.z = ( UNITY_NEAR_CLIP_VALUE >= 0 ) ? screenPosNorm.z : screenPosNorm.z * 0.5 + 0.5;

			// 極座標変換
			float2 polarCoords = RemapUV(
				screenPosNorm.xy,
				float2( 0, 0 ), float2( 1, 1 ),
				float2( -UNITY_PI, -UNITY_PI ), float2( UNITY_PI, UNITY_PI )
			);
			float azimuth = polarCoords.x + radians( 45.0 );
			float elevation = polarCoords.y / 2.0;

			// 球面ベクトル
			float cosElevation = cos( elevation );
			float3 sphereVector = float3(
				cosElevation * sin( azimuth ),
				sin( elevation ),
				cosElevation * cos( azimuth )
			);

			// 投影角度の計算
			float3 vecYZ = normalize( float3( 0.0, sphereVector.y, sphereVector.z ) );
			float3 vecXY = normalize( float3( sphereVector.x, sphereVector.y, 0.0 ) );
			float3 vecXZ = normalize( float3( sphereVector.x, 0.0, sphereVector.z ) );

			float dotYZ = dot( vecYZ, sphereVector );
			float dotXY = dot( vecXY, sphereVector );
			float dotXZ = dot( vecXZ, sphereVector );

			float3 projectionAngles = float3( dotYZ, dotXY, dotXZ );
			float3 sinAngles = sqrt( 1.0 - ( projectionAngles * projectionAngles ) );

			// 投影UVの計算
			float2 projectedYZ = ( 1.0 / sinAngles.x ) * sphereVector.yz;
			float2 projectedXY = ( 1.0 / sinAngles.y ) * sphereVector.xy;
			float2 projectedXZ = ( 1.0 / sinAngles.z ) * sphereVector.xz;

			// 左右判定
			half isRightEye = saturate( ceil( -0.5 + screenPosNorm.x ) );
			
			float2 finalUV = 0;
			half finalMask = 0;
			float4 finalColor = 0;

			// アトラスオフセット
			const float atlasR_offsetX    = 0.00;
			const float atlasL_offsetX    = 0.25;
			const float atlasUP_offsetX   = 0.50;
			const float atlasDOWN_offsetX = 0.75;
			
			// 片目のみ計算・サンプリング
			if( isRightEye > 0.5 )
			{
				// === 右目 ===

				// 右面 (+X)
				float2 uvRightL = saturate( RemapUV( projectedYZ, float2( -1, 1 ), float2( 1, -1 ), float2( 0, 0 ), float2( 1, 1 ) ) );
				float2 uvRightL_swapped = float2( uvRightL.y, uvRightL.x );
				half maskRightL = ComputeFaceMask( uvRightL ) * saturate( ceil( sphereVector.x ) );
				
				// 背面 (-Z)
				float2 uvRightR = saturate( RemapUV( projectedXY, float2( 1, -1 ), float2( -1, 1 ), float2( 0, 0 ), float2( 1, 1 ) ) );
				half maskRightR = ComputeFaceMask( uvRightR ) * saturate( ceil( -sphereVector.z ) );
				
				// 上面 (+Y)
				float2 uvRightUpRaw = saturate( RemapUV( projectedXZ, float2( 1, -1 ), float2( -1, 1 ), float2( 0, 0 ), float2( 1, 1 ) ) );
				half maskUp = ComputeFaceMask( uvRightUpRaw ) * saturate( ceil( sphereVector.y ) );
				
				// 下面 (-Y)
				float2 uvRightDownRaw = saturate( RemapUV( projectedXZ, float2( 1, 1 ), float2( -1, -1 ), float2( 0, 0 ), float2( 1, 1 ) ) );
				half maskDown = ComputeFaceMask( uvRightDownRaw ) * saturate( ceil( -sphereVector.y ) );

				// UV合成
				finalUV += float2( uvRightL_swapped.x * 0.25 + atlasL_offsetX, uvRightL_swapped.y ) * maskRightL;
				finalUV += float2( uvRightR.x * 0.25 + atlasR_offsetX, uvRightR.y ) * maskRightR;
				finalUV += float2( uvRightUpRaw.x * 0.25 + atlasUP_offsetX, uvRightUpRaw.y ) * maskUp;
				finalUV += float2( uvRightDownRaw.x * 0.25 + atlasDOWN_offsetX, uvRightDownRaw.y ) * maskDown;
				
				finalMask = maskRightL + maskRightR + maskUp + maskDown;
				
				finalColor = tex2D( _RightEyeTex, finalUV ) * finalMask;
			}
			else
			{
				// === 左目 ===

				// 左面 (-X)
				float2 uvLeftL = saturate( RemapUV( projectedYZ, float2( -1, -1 ), float2( 1, 1 ), float2( 0, 0 ), float2( 1, 1 ) ) );
				float2 uvLeftL_swapped = float2( uvLeftL.y, uvLeftL.x );
				half maskLeftL = ComputeFaceMask( uvLeftL ) * saturate( ceil( -sphereVector.x ) );

				// 正面 (+Z)
				float2 uvLeftR = saturate( RemapUV( projectedXY, float2( -1, -1 ), float2( 1, 1 ), float2( 0, 0 ), float2( 1, 1 ) ) );
				half maskLeftR = ComputeFaceMask( uvLeftR ) * saturate( ceil( sphereVector.z ) );

				// 上面 (+Y)
				float2 uvUp = saturate( RemapUV( projectedXZ, float2( -1, 1 ), float2( 1, -1 ), float2( 0, 0 ), float2( 1, 1 ) ) );
				half maskUp = ComputeFaceMask( uvUp ) * saturate( ceil( sphereVector.y ) );

				// 下面 (-Y)
				float2 uvDown = saturate( RemapUV( projectedXZ, float2( -1, -1 ), float2( 1, 1 ), float2( 0, 0 ), float2( 1, 1 ) ) );
				half maskDown = ComputeFaceMask( uvDown ) * saturate( ceil( -sphereVector.y ) );

				// UV合成
				finalUV += float2( uvLeftL_swapped.x * 0.25 + atlasL_offsetX, uvLeftL_swapped.y ) * maskLeftL;
				finalUV += float2( uvLeftR.x * 0.25 + atlasR_offsetX, uvLeftR.y ) * maskLeftR;
				finalUV += float2( uvUp.x * 0.25 + atlasUP_offsetX, uvUp.y ) * maskUp;
				finalUV += float2( uvDown.x * 0.25 + atlasDOWN_offsetX, uvDown.y ) * maskDown;

				finalMask = maskLeftL + maskLeftR + maskUp + maskDown;

				finalColor = tex2D( _LeftEyeTex, finalUV ) * finalMask;
			}

			// 出力
			o.Emission = finalColor.rgb;
			o.Alpha = 1;

			// アスペクト比マスククリップ
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