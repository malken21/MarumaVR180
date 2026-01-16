Shader "Marumasa/VR180-Display"
{
	Properties
	{
		[NoScaleOffset][SingleLineTexture] _LeftEyeTex( "LeftEye-Atlas", 2D ) = "black" {}
		[NoScaleOffset][SingleLineTexture] _RightEyeTex( "RightEye-Atlas", 2D ) = "black" {}
		_ScreenWidth( "Screen Width", Float ) = 16
		_ScreenHeight( "Screen Height", Float ) = 9
		[Toggle] _DebugMode( "DebugMode", Float ) = 0
		_Cutoff( "Mask Clip Value", Float ) = 0.5
		[HideInInspector] _texcoord( "", 2D ) = "white" {}
		[HideInInspector] __dirty( "", Int ) = 1
	}

	SubShader
	{
		Tags{ "RenderType" = "Overlay"  "Queue" = "Overlay+0" "IsEmissive" = "true"  }
		Cull Back
		ZTest Always
		Stencil
		{
			Ref 55
			WriteMask 0
			Comp Equal
			Pass DecrWrap
		}
		CGPROGRAM
		#include "UnityShaderVariables.cginc"
		#pragma target 3.5
		#define ASE_VERSION 19900
		#pragma surface surf Unlit keepalpha noshadow noambient novertexlights nolightmap  nodynlightmap nodirlightmap nofog nometa noforwardadd vertex:vertexDataFunc 
		struct Input
		{
			float2 uv_texcoord;
		};

		uniform sampler2D _LeftEyeTex;
		uniform sampler2D _RightEyeTex;
		uniform float _DebugMode;
		uniform float _ScreenWidth;
		uniform float _ScreenHeight;
		uniform float _Cutoff = 0.5;


		float unity_StereoEyeIndex892(  )
		{
			return unity_StereoEyeIndex;
		}


		void vertexDataFunc( inout appdata_full v, out Input o )
		{
			UNITY_INITIALIZE_OUTPUT( Input, o );
			float3 ase_positionOS = v.vertex.xyz;
			v.vertex.xyz += ( ase_positionOS * 50 );
			v.vertex.w = 1;
		}

		inline half4 LightingUnlit( SurfaceOutput s, half3 lightDir, half atten )
		{
			return half4 ( 0, 0, 0, s.Alpha );
		}

		void surf( Input i , inout SurfaceOutput o )
		{
			float2 temp_output_858_0 = ( i.uv_texcoord * float2( 2,2 ) );
			float2 temp_output_866_0 = floor( temp_output_858_0 );
			float2 CubeUV881 = ( temp_output_858_0 - temp_output_866_0 );
			float2 break683 = temp_output_866_0;
			float temp_output_874_0 = ( 1.0 - break683.x );
			float temp_output_860_0 = ( temp_output_874_0 * break683.y );
			float localunity_StereoEyeIndex892 = unity_StereoEyeIndex892();
			float EyeIndex853 = localunity_StereoEyeIndex892;
			float temp_output_895_0 = ( break683.x * break683.y );
			float temp_output_894_0 = ( 1.0 - break683.y );
			float temp_output_896_0 = ( temp_output_874_0 * temp_output_894_0 );
			float temp_output_897_0 = ( break683.x * temp_output_894_0 );
			// TL (Top-Left) -> Atlas Offset 0.25 (Left Face)
			// TR (Top-Right) -> Atlas Offset 0.00 (Right Face)
			// BL (Bottom-Left) -> Atlas Offset 0.50 (Up Face)
			// BR (Bottom-Right) -> Atlas Offset 0.75 (Down Face)
			float offset = ( temp_output_860_0 * 0.25 ) + ( temp_output_896_0 * 0.50 ) + ( temp_output_897_0 * 0.75 );
			
			float2 atlasUV = float2( CubeUV881.x * 0.25 + offset, CubeUV881.y );
			
			float4 leftCol = tex2D( _LeftEyeTex, atlasUV );
			float4 rightCol = tex2D( _RightEyeTex, atlasUV );
			
			o.Emission = lerp( leftCol, rightCol, EyeIndex853 ).rgb;
			o.Alpha = 1;
			clip( (( _DebugMode )?( 0.0 ):( abs( sign( ( ( _ScreenParams.x / _ScreenParams.y ) - ( _ScreenWidth / _ScreenHeight ) ) ) ) )) - _Cutoff );
		}

		ENDCG
	}
}