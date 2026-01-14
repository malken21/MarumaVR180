Shader "Marumasa/VR180-Camera"
{
	Properties
	{
		[NoScaleOffset][SingleLineTexture] _LeftEyeTex( "LeftEye-Atlas", 2D ) = "black" {}
		[NoScaleOffset][SingleLineTexture] _RightEyeTex( "RightEye-Atlas", 2D ) = "black" {}
		_Cutoff( "Mask Clip Value", Float ) = 0.5
		[HideInInspector] __dirty( "", Int ) = 1
	}

	SubShader
	{
		Tags{ "RenderType" = "Overlay"  "Queue" = "Overlay+1000" "DisableBatching" = "True" "IsEmissive" = "true"  }
		Cull Front
		ZWrite On
		ZTest Always
		CGPROGRAM
		#include "UnityShaderVariables.cginc"
		#pragma target 3.5
		#define ASE_VERSION 19900
		#pragma surface surf Unlit keepalpha addshadow fullforwardshadows noambient novertexlights nolightmap  nodynlightmap nodirlightmap nofog nometa noforwardadd vertex:vertexDataFunc 
		struct Input
		{
			float4 screenPos;
		};

		uniform sampler2D _LeftEyeTex;
		uniform sampler2D _RightEyeTex;
		uniform float _Cutoff = 0.5;

		void vertexDataFunc( inout appdata_full v, out Input o )
		{
			UNITY_INITIALIZE_OUTPUT( Input, o );
			float3 ase_positionOS = v.vertex.xyz;
			v.vertex.xyz += ( ase_positionOS * 10 );
			v.vertex.w = 1;
		}

		inline half4 LightingUnlit( SurfaceOutput s, half3 lightDir, half atten )
		{
			return half4 ( 0, 0, 0, s.Alpha );
		}


		void surf( Input i , inout SurfaceOutput o )
		{
			float4 ase_positionSS = float4( i.screenPos.xyz , i.screenPos.w + 1e-7 );
			float4 ase_positionSSNorm = ase_positionSS / ase_positionSS.w;
			ase_positionSSNorm.z = lerp(ase_positionSSNorm.z * 0.5 + 0.5, ase_positionSSNorm.z, step(0, UNITY_NEAR_CLIP_VALUE));

			float2 temp_cast_0 = (-UNITY_PI).xx;
			float2 temp_cast_1 = (UNITY_PI).xx;
			float2 break6 =  (temp_cast_0 + ( (ase_positionSSNorm).xy - float2( 0,0 ) ) * ( temp_cast_1 - temp_cast_0 ) / ( float2( 1,1 ) - float2( 0,0 ) ) );
			float temp_output_7_0 = ( break6.y / 2.0 );
			float temp_output_13_0 = cos( temp_output_7_0 );
			float temp_output_8_0 = break6.x;
			float3 SphereVector18 = float3(( temp_output_13_0 * sin( temp_output_8_0 ) ) , sin( temp_output_7_0 ) , ( temp_output_13_0 * cos( temp_output_8_0 ) ));
			
			float isRightEye = step(0.5, ase_positionSSNorm.x);
			
			float3 absV = abs(SphereVector18);
			float zDom = step(absV.x, absV.z) * step(absV.y, absV.z);
			float xDom = step(absV.y, absV.x) * (1.0 - zDom);
			float yDom = 1.0 - zDom - xDom;

			float isFront = zDom * step(0, SphereVector18.z);
			float isLeft  = xDom * (1.0 - step(0, SphereVector18.x));
			float isRight = xDom * step(0, SphereVector18.x);
			float isUp    = yDom * step(0, SphereVector18.y);
			float isDown  = yDom * (1.0 - step(0, SphereVector18.y));

			float2 rawUV = isFront * SphereVector18.xy + 
			               (isLeft + isRight) * SphereVector18.zy + 
			               (isUp + isDown) * SphereVector18.xz;
			
			float denom = isFront * absV.z + 
			              (isLeft + isRight) * absV.x + 
			              (isUp + isDown) * absV.y;
			
			float2 uv = rawUV / max(denom, 1e-5);
			
			float xScale = 0.5 - isLeft;
			float yScale = 0.5 - isDown;
			uv = uv * float2(xScale, yScale) + 0.5;

			float faceIndex = isLeft + isRight * 2.0 + isUp * 3.0 + isDown * 4.0;
			
			float2 atlasUV = uv;
			atlasUV.x = atlasUV.x * 0.2 + faceIndex * 0.2;

			float4 colL = tex2D(_LeftEyeTex, atlasUV);
			float4 colR = tex2D(_RightEyeTex, atlasUV);
			float4 finalColor = lerp(colL, colR, isRightEye);

			o.Emission = finalColor.rgb;
			o.Alpha = 1;
			clip( ( finalColor.a * abs( sign( ( _ScreenParams.x - _ScreenParams.y ) ) ) ) - _Cutoff );
		}

		ENDCG
	}
	Fallback "Diffuse"
}