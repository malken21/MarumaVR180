Shader "Marumasa/VR180-Camera"
{
	Properties
	{
		[NoScaleOffset][SingleLineTexture] _LeftEyeTex( "LeftEye-Atlas", 2D ) = "black" {}
		[NoScaleOffset][SingleLineTexture] _RightEyeTex( "RightEye-Atlas", 2D ) = "black" {}

		_ScreenWidth( "Screen Width", Float ) = 16
		_ScreenHeight( "Screen Height", Float ) = 9

		[Toggle] _DebugMode( "DebugMode", Float ) = 0
		[HideInInspector] __dirty( "", Int ) = 1
	}

	SubShader
	{
		Tags
		{
			"RenderType" = "Overlay"
			"Queue" = "Overlay+1001"
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
		uniform float4 _LeftEyeTex_TexelSize;
		uniform float4 _RightEyeTex_TexelSize;

		uniform float _DebugMode;
		uniform float _ScreenWidth;
		uniform float _ScreenHeight;
		uniform int _VRChatCameraMode;


		void vertexDataFunc( inout appdata_full v, out Input o )
		{
			UNITY_INITIALIZE_OUTPUT( Input, o );
			v.vertex.w = 1;
		}

		inline half4 LightingUnlit( SurfaceOutput s, half3 lightDir, half atten )
		{
			return half4( 0, 0, 0, s.Alpha );
		}

		float2 RemapUV( float2 value, float2 fromMin, float2 fromMax, float2 toMin, float2 toMax )
		{
			return toMin + ( value - fromMin ) * ( toMax - toMin ) / ( fromMax - fromMin );
		}

		float ComputeFaceMask( float2 uv )
		{
			float2 floorUV = 1.0 - floor( uv );
			float2 ceilUV = ceil( uv );
			return floorUV.x * floorUV.y * ceilUV.x * ceilUV.y;
		}

		void surf( Input i, inout SurfaceOutput o )
		{
			// VRChatのカメラモードが2（三人称視点など）の場合は描画しない
			if ( _VRChatCameraMode == 2 ) discard;

			// アスペクト比の計算
			float screenAspect = _ScreenParams.x / _ScreenParams.y;
			float targetAspect = _ScreenWidth / _ScreenHeight;
			float aspectDiff = abs( screenAspect - targetAspect );
			
			// デバッグモードが無効で、アスペクト比が一致しない場合は描画しない
			if ( _DebugMode < 0.5 && aspectDiff >= 0.01 ) discard;

			// 投影行列の非対称性からVRモードかどうかを判定
			float asymmetric = abs( unity_CameraProjection[0][2] );
			bool isVR = asymmetric > 0.001;

			// VRChatカメラモードが0（First Person）かつVRモードの場合は描画しない
			if ( _VRChatCameraMode == 0 && isVR ) discard;

			float4 screenPos = float4( i.screenPos.xyz, i.screenPos.w + 1e-7 );
			float4 screenPosNorm = screenPos / screenPos.w;
			screenPosNorm.z = ( UNITY_NEAR_CLIP_VALUE >= 0 ) ? screenPosNorm.z : screenPosNorm.z * 0.5 + 0.5;

			// スクリーン座標を極座標（方位角・仰角）に変換
			float2 polarCoords = RemapUV(
				screenPosNorm.xy,
				float2( 0, 0 ), float2( 1, 1 ),
				float2( -UNITY_PI, -UNITY_PI ), float2( UNITY_PI, UNITY_PI )
			);
			float azimuth = polarCoords.x + radians( 45.0 );
			float elevation = polarCoords.y / 2.0;

			float cosElevation = cos( elevation );
			// 球面上のベクトルを計算
			float3 sphereVector = float3(
				cosElevation * sin( azimuth ),
				sin( elevation ),
				cosElevation * cos( azimuth )
			);

			// 右目かどうかを判定
			half isRightEye = saturate( ceil( -0.5 + screenPosNorm.x ) );
			
			float2 finalUV = 0;
			half finalMask = 0;
			float4 finalColor = 0;

			const float atlasR_offsetX    = 0.00;
			const float atlasL_offsetX    = 0.25;
			const float atlasUP_offsetX   = 0.50;
			const float atlasDOWN_offsetX = 0.75;
			
			float2 uvPaddingPtrn1, uvPaddingPtrn2;
			float4 texelSize;

			if( isRightEye > 0.5 ) texelSize = _RightEyeTex_TexelSize;
			else texelSize = _LeftEyeTex_TexelSize;

			uvPaddingPtrn1 = float2( texelSize.x * 2.0, texelSize.y * 0.5 );
			uvPaddingPtrn2 = float2( uvPaddingPtrn1.y, uvPaddingPtrn1.x );

			float3 absVec = abs( sphereVector );
			float maxComp = max( absVec.x, max( absVec.y, absVec.z ) );
			
			bool isValidFace = false;
			float2 rawUV = 0;
			float2 padding = uvPaddingPtrn1;
			float offset = 0;
			bool swap = false;
			float faceMask = 0;

			if ( isRightEye > 0.5 )
			{
				// 右目の処理
				if ( maxComp == absVec.y ) // 上面または下面
				{
					float2 proj = sphereVector.xz / absVec.y;
					if ( sphereVector.y > 0 ) // 上面
					{
						rawUV = RemapUV( proj, float2( 1, -1 ), float2( -1, 1 ), float2( 0, 0 ), float2( 1, 1 ) );
						offset = atlasUP_offsetX;
					}
					else // 下面
					{
						rawUV = RemapUV( proj, float2( 1, 1 ), float2( -1, -1 ), float2( 0, 0 ), float2( 1, 1 ) );
						offset = atlasDOWN_offsetX;
					}
					isValidFace = true;
				}
				else if ( maxComp == absVec.x ) // 右目 左側面 (+X)
				{
					if ( sphereVector.x > 0 )
					{
						float2 proj = sphereVector.yz / absVec.x;
						rawUV = RemapUV( proj, float2( -1, 1 ), float2( 1, -1 ), float2( 0, 0 ), float2( 1, 1 ) );
						offset = atlasL_offsetX;
						padding = uvPaddingPtrn2;
						swap = true;
						isValidFace = true;
					}
				}
				else // 右目 右側面 (-Z)
				{
					if ( sphereVector.z < 0 )
					{
						float2 proj = sphereVector.xy / absVec.z;
						rawUV = RemapUV( proj, float2( 1, -1 ), float2( -1, 1 ), float2( 0, 0 ), float2( 1, 1 ) );
						offset = atlasR_offsetX;
						isValidFace = true;
					}
				}
			}
			else
			{
				// 左目の処理
				if ( maxComp == absVec.y ) // 上面または下面
				{
					float2 proj = sphereVector.xz / absVec.y;
					if ( sphereVector.y > 0 ) // 上面
					{
						rawUV = RemapUV( proj, float2( -1, 1 ), float2( 1, -1 ), float2( 0, 0 ), float2( 1, 1 ) );
						offset = atlasUP_offsetX;
					}
					else // 下面
					{
						rawUV = RemapUV( proj, float2( -1, -1 ), float2( 1, 1 ), float2( 0, 0 ), float2( 1, 1 ) );
						offset = atlasDOWN_offsetX;
					}
					isValidFace = true;
				}
				else if ( maxComp == absVec.x ) // 左目 左側面 (-X)
				{
					if ( sphereVector.x < 0 )
					{
						float2 proj = sphereVector.yz / absVec.x;
						rawUV = RemapUV( proj, float2( -1, -1 ), float2( 1, 1 ), float2( 0, 0 ), float2( 1, 1 ) );
						offset = atlasL_offsetX;
						padding = uvPaddingPtrn2;
						swap = true;
						isValidFace = true;
					}
				}
				else // 左目 右側面 (+Z)
				{
					if ( sphereVector.z > 0 )
					{
						float2 proj = sphereVector.xy / absVec.z;
						rawUV = RemapUV( proj, float2( -1, -1 ), float2( 1, 1 ), float2( 0, 0 ), float2( 1, 1 ) );
						offset = atlasR_offsetX;
						isValidFace = true;
					}
				}
			}

			if ( isValidFace )
			{
				float2 clampedUV = clamp( rawUV, padding, 1.0 - padding );
				
				// 元のロジック（ピラミッド投影の有効性）に合わせてマスクを再計算
				// ComputeFaceMask は元の (saturateされた) UV が 0-1 の範囲内にあるかを確認する。
				// ドミナント軸で選択しているため、rawUV は自然に 0-1 の範囲内になるはずだが、
				// ComputeFaceMask は念のためピラミッドの境界での滲みを防ぐ。
				finalMask = ComputeFaceMask( saturate( rawUV ) );

				if ( swap )
				{
					clampedUV = float2( clampedUV.y, clampedUV.x );
				}

				finalUV = float2( clampedUV.x * 0.25 + offset, clampedUV.y );
				
				if( isRightEye > 0.5 )
					finalColor = tex2D( _RightEyeTex, finalUV );
				else
					finalColor = tex2D( _LeftEyeTex, finalUV );

				finalColor *= finalMask;
			}

			o.Emission = finalColor.rgb;
			o.Alpha = 1;

			float squareScreenMask = abs( sign( _ScreenParams.x - _ScreenParams.y ) );
			
			clip( finalColor.a * squareScreenMask - 0.5 );
		}

		ENDCG
	}
	Fallback "Diffuse"
}