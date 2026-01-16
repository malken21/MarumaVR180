Shader "Marumasa/VR180/Mask"
{
    Properties
    {
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
