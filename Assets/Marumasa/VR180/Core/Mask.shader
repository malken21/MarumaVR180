Shader "Unlit/Mask"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Overlay" "Queue"="Geometry-1" }
        LOD 100

        ColorMask 0
        ZWrite Off
        Cull Front

        Stencil
        {
            Ref 1
            Comp Always
            Pass Replace
        }

        Pass
        {
        }
    }
}
