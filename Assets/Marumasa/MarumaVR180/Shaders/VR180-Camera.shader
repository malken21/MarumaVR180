Shader "Marumasa/VR180-Camera"
{
	Properties
	{

		[NoScaleOffset][SingleLineTexture] _LeftEyeTex( "LeftEye-Atlas", 2D ) = "black" {}

		[NoScaleOffset][SingleLineTexture] _RightEyeTex( "RightEye-Atlas", 2D ) = "black" {}
		

		_ScreenWidth( "Screen Width", Float ) = 16
		_ScreenHeight( "Screen Height", Float ) = 9
		

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
		uniform float4 _LeftEyeTex_TexelSize;
		uniform float4 _RightEyeTex_TexelSize;

		uniform float _DebugMode;
		uniform float _ScreenWidth;
		uniform float _ScreenHeight;
		uniform float _Cutoff = 0.5;
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
			if ( _VRChatCameraMode == 2 ) discard;


			float screenAspect = _ScreenParams.x / _ScreenParams.y;
			float targetAspect = _ScreenWidth / _ScreenHeight;
			float aspectDiff = abs( screenAspect - targetAspect );
			
			if ( _DebugMode < 0.5 && aspectDiff >= 0.01 ) discard;

			float asymmetric = abs( unity_CameraProjection[0][2] );
			bool isVR = asymmetric > 0.001;

			if ( _VRChatCameraMode == 0 && isVR ) discard;


			float4 screenPos = float4( i.screenPos.xyz, i.screenPos.w + 1e-7 );
			float4 screenPosNorm = screenPos / screenPos.w;
			screenPosNorm.z = ( UNITY_NEAR_CLIP_VALUE >= 0 ) ? screenPosNorm.z : screenPosNorm.z * 0.5 + 0.5;


			float2 polarCoords = RemapUV(
				screenPosNorm.xy,
				float2( 0, 0 ), float2( 1, 1 ),
				float2( -UNITY_PI, -UNITY_PI ), float2( UNITY_PI, UNITY_PI )
			);
			float azimuth = polarCoords.x + radians( 45.0 );
			float elevation = polarCoords.y / 2.0;


			float cosElevation = cos( elevation );
			float3 sphereVector = float3(
				cosElevation * sin( azimuth ),
				sin( elevation ),
				cosElevation * cos( azimuth )
			);


			float3 vecYZ = normalize( float3( 0.0, sphereVector.y, sphereVector.z ) );
			float3 vecXY = normalize( float3( sphereVector.x, sphereVector.y, 0.0 ) );
			float3 vecXZ = normalize( float3( sphereVector.x, 0.0, sphereVector.z ) );

			float dotYZ = dot( vecYZ, sphereVector );
			float dotXY = dot( vecXY, sphereVector );
			float dotXZ = dot( vecXZ, sphereVector );

			float3 projectionAngles = float3( dotYZ, dotXY, dotXZ );
			float3 sinAngles = sqrt( 1.0 - ( projectionAngles * projectionAngles ) );


			float2 projectedYZ = ( 1.0 / sinAngles.x ) * sphereVector.yz;
			float2 projectedXY = ( 1.0 / sinAngles.y ) * sphereVector.xy;
			float2 projectedXZ = ( 1.0 / sinAngles.z ) * sphereVector.xz;


			half isRightEye = saturate( ceil( -0.5 + screenPosNorm.x ) );
			
			float2 finalUV = 0;
			half finalMask = 0;
			float4 finalColor = 0;


			const float atlasR_offsetX    = 0.00;
			const float atlasL_offsetX    = 0.25;
			const float atlasUP_offsetX   = 0.50;
			const float atlasDOWN_offsetX = 0.75;
			

			float2 uvPaddingPtrn1; 

			float2 uvPaddingPtrn2;

			if( isRightEye > 0.5 )
			{
				uvPaddingPtrn1 = float2( _RightEyeTex_TexelSize.x * 2.0, _RightEyeTex_TexelSize.y * 0.5 );
				uvPaddingPtrn2 = float2( uvPaddingPtrn1.y, uvPaddingPtrn1.x );




				float2 uvRightLRaw = RemapUV( projectedYZ, float2( -1, 1 ), float2( 1, -1 ), float2( 0, 0 ), float2( 1, 1 ) );
				float2 uvRightL = clamp( uvRightLRaw, uvPaddingPtrn2, 1.0 - uvPaddingPtrn2 );
				float2 uvRightL_swapped = float2( uvRightL.y, uvRightL.x );
				half maskRightL = ComputeFaceMask( saturate( uvRightLRaw ) ) * saturate( ceil( sphereVector.x ) );
				

				float2 uvRightRRaw = RemapUV( projectedXY, float2( 1, -1 ), float2( -1, 1 ), float2( 0, 0 ), float2( 1, 1 ) );
				float2 uvRightR = clamp( uvRightRRaw, uvPaddingPtrn1, 1.0 - uvPaddingPtrn1 );
				half maskRightR = ComputeFaceMask( saturate( uvRightRRaw ) ) * saturate( ceil( -sphereVector.z ) );
				

				float2 uvRightUpRawVal = RemapUV( projectedXZ, float2( 1, -1 ), float2( -1, 1 ), float2( 0, 0 ), float2( 1, 1 ) );
				float2 uvRightUpRaw = clamp( uvRightUpRawVal, uvPaddingPtrn1, 1.0 - uvPaddingPtrn1 );
				half maskUp = ComputeFaceMask( saturate( uvRightUpRawVal ) ) * saturate( ceil( sphereVector.y ) );
				

				float2 uvRightDownRawVal = RemapUV( projectedXZ, float2( 1, 1 ), float2( -1, -1 ), float2( 0, 0 ), float2( 1, 1 ) );
				float2 uvRightDownRaw = clamp( uvRightDownRawVal, uvPaddingPtrn1, 1.0 - uvPaddingPtrn1 );
				half maskDown = ComputeFaceMask( saturate( uvRightDownRawVal ) ) * saturate( ceil( -sphereVector.y ) );


				finalUV += float2( uvRightL_swapped.x * 0.25 + atlasL_offsetX, uvRightL_swapped.y ) * maskRightL;
				finalUV += float2( uvRightR.x * 0.25 + atlasR_offsetX, uvRightR.y ) * maskRightR;
				finalUV += float2( uvRightUpRaw.x * 0.25 + atlasUP_offsetX, uvRightUpRaw.y ) * maskUp;
				finalUV += float2( uvRightDownRaw.x * 0.25 + atlasDOWN_offsetX, uvRightDownRaw.y ) * maskDown;
				
				finalMask = maskRightL + maskRightR + maskUp + maskDown;
				
				finalColor = tex2D( _RightEyeTex, finalUV ) * finalMask;
			}
			else
			{
				uvPaddingPtrn1 = float2( _LeftEyeTex_TexelSize.x * 2.0, _LeftEyeTex_TexelSize.y * 0.5 );
				uvPaddingPtrn2 = float2( uvPaddingPtrn1.y, uvPaddingPtrn1.x );





				float2 uvLeftLRaw = RemapUV( projectedYZ, float2( -1, -1 ), float2( 1, 1 ), float2( 0, 0 ), float2( 1, 1 ) );
				float2 uvLeftL = clamp( uvLeftLRaw, uvPaddingPtrn2, 1.0 - uvPaddingPtrn2 );
				float2 uvLeftL_swapped = float2( uvLeftL.y, uvLeftL.x );
				half maskLeftL = ComputeFaceMask( saturate( uvLeftLRaw ) ) * saturate( ceil( -sphereVector.x ) );


				float2 uvLeftRRaw = RemapUV( projectedXY, float2( -1, -1 ), float2( 1, 1 ), float2( 0, 0 ), float2( 1, 1 ) );
				float2 uvLeftR = clamp( uvLeftRRaw, uvPaddingPtrn1, 1.0 - uvPaddingPtrn1 );
				half maskLeftR = ComputeFaceMask( saturate( uvLeftRRaw ) ) * saturate( ceil( sphereVector.z ) );

				// 上面 (+Y)
				float2 uvUpRawVal = RemapUV( projectedXZ, float2( -1, 1 ), float2( 1, -1 ), float2( 0, 0 ), float2( 1, 1 ) );
				float2 uvUp = clamp( uvUpRawVal, uvPaddingPtrn1, 1.0 - uvPaddingPtrn1 );
				half maskUp = ComputeFaceMask( saturate( uvUpRawVal ) ) * saturate( ceil( sphereVector.y ) );

				// 下面 (-Y)
				float2 uvDownRawVal = RemapUV( projectedXZ, float2( -1, -1 ), float2( 1, 1 ), float2( 0, 0 ), float2( 1, 1 ) );
				float2 uvDown = clamp( uvDownRawVal, uvPaddingPtrn1, 1.0 - uvPaddingPtrn1 );
				half maskDown = ComputeFaceMask( saturate( uvDownRawVal ) ) * saturate( ceil( -sphereVector.y ) );

				// UV合成
				finalUV += float2( uvLeftL_swapped.x * 0.25 + atlasL_offsetX, uvLeftL_swapped.y ) * maskLeftL;
				finalUV += float2( uvLeftR.x * 0.25 + atlasR_offsetX, uvLeftR.y ) * maskLeftR;
				finalUV += float2( uvUp.x * 0.25 + atlasUP_offsetX, uvUp.y ) * maskUp;
				finalUV += float2( uvDown.x * 0.25 + atlasDOWN_offsetX, uvDown.y ) * maskDown;

				finalMask = maskLeftL + maskLeftR + maskUp + maskDown;

				finalColor = tex2D( _LeftEyeTex, finalUV ) * finalMask;
			}


			o.Emission = finalColor.rgb;
			o.Alpha = 1;


			float squareScreenMask = abs( sign( _ScreenParams.x - _ScreenParams.y ) );
			
			clip( finalColor.a * squareScreenMask - _Cutoff );
		}

		ENDCG
	}
	Fallback "Diffuse"
}