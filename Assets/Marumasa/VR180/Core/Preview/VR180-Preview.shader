Shader "Marumasa/VR180-Preview"
{
    Properties
    {
        _LeftEyeTexture ("Left Eye Texture (R, L, U, D)", 2D) = "black" {}
        _RightEyeTexture ("Right Eye Texture (R, L, U, D)", 2D) = "black" {}
        
        [HideInInspector] _MainTex ("Do not use", 2D) = "black" {}

        _FOV ("Field of View", Range(10, 170)) = 60
        _Aspect ("Aspect Ratio (Width/Height)", Float) = 1
        _PanX ("Pan X (Degrees)", Range(-180, 180)) = 0
        _PanY ("Pan Y (Degrees)", Range(-90, 90)) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _LeftEyeTexture;
            sampler2D _RightEyeTexture;
            // Retain _MainTex decl to avoid errors if referenced strictly, but we won't sample it for logic
            sampler2D _MainTex; 

            float _FOV;
            float _Aspect;
            float _PanX;
            float _PanY;

            // --- Helper Math ---

            float3x3 RotationMatrix(float3 euler)
            {
                // Euler to Matrix (Y, X, Z ordering usually in Unity for cameras, or ZXY? 
				// Unity Transform.eulerAngles is usually applied Z, then X, then Y (roll, pitch, yaw) for Order
				// But we need the rotation of the Camera Transform to World.
				// Quaternion.Euler(x, y, z)
				// Let's assume standard rotation matrix construction from Euler angles (degrees)
				
				// However, efficient way: 
				// We need Inverse rotation (World->Camera) to project Ray into Camera space?
				// Actually Ray is in "World" (relative to the Rig center), we want Ray in "Camera Local"
				// M_cam_local = Transpose(M_cam_world) (if pure rotation)
				
				float radX = radians(euler.x);
				float radY = radians(euler.y);
				float radZ = radians(euler.z);

				float sX, cX; sincos(radX, sX, cX);
				float sY, cY; sincos(radY, sY, cY);
				float sZ, cZ; sincos(radZ, sZ, cZ);

				// R_z * R_x * R_y is typical Unity? Or Y * X * Z?
				// Unity doc says: "ZXY" order for Euler. (Roll, Pitch, Yaw)
				// Let's build individual matrices and mul: R = Ry * Rx * Rz
				
				float3x3 Ry = float3x3(
					cY, 0, sY,
					0, 1, 0,
					-sY, 0, cY
				);
				float3x3 Rx = float3x3(
					1, 0, 0,
					0, cX, -sX,
					0, sX, cX
				);
				float3x3 Rz = float3x3(
					cZ, -sZ, 0,
					sZ, cZ, 0,
					0, 0, 1
				);
				
				return mul(Ry, mul(Rx, Rz));
            }

            v2f vert (appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.vertex = UnityObjectToClipPos(v.vertex);
                // Standard UV pass-through
                o.uv = v.uv; 
                return o;
            }

            // --- Camera Definitions (Based on inspection) ---
            // R: (0, 45, 0)
            // L: (0, 315, 0) => (0, -45, 0)
            // U: (270, 45, 0) => (-90, 45, 0)  [Unity Inspector shows 270 for -90 sometimes]
            // D: (90, 45, 0)
            
            static const float3 ROT_R = float3(0, 45, 0);
            static const float3 ROT_L = float3(0, -45, 0); // 315 is -45
            static const float3 ROT_U = float3(-90, 45, 0); // 270 is -90
            static const float3 ROT_D = float3(90, 45, 0);

            // Project ray into a camera's clip UVs. Returns true if inside FOV.
            bool GetCameraUV(float3 rayDir, float3 camEuler, out float2 uv)
            {
                // 1. Transform Ray to Camera Local Space
                // Ray is World. Cam is World. 
                // Local = Inverse(CamRot) * Ray
                // Inverse of Rotation is Transpose
                float3x3 rot = RotationMatrix(camEuler);
                float3 localDir = mul(transpose(rot), rayDir);

                // 2. Check if in front
                if (localDir.z <= 0) 
                {
                    uv = 0;
                    return false;
                }

                // 3. Project to Plane (z=1)
                // pos = (x/z, y/z)
                float2 proj = localDir.xy / localDir.z;

                // 4. Normalize to UV [0..1]
                // FOV is 90 degrees.
                // Half FOV = 45. tan(45) = 1.
                // Range on plane is [-1, 1].
                
                // If abs(proj) > 1, it's outside FOV
                if (abs(proj.x) > 1.001 || abs(proj.y) > 1.001) // Small tolerance
                {
                    uv = 0;
                    return false;
                }

                // [-1, 1] -> [0, 1]
                uv = proj * 0.5 + 0.5;
                return true;
            }

            // View Ray Generation Helper
            float3x3 AngleAxis3x3(float angle, float3 axis)
            {
                float c, s;
                sincos(radians(angle), s, c);

                float t = 1 - c;
                float x = axis.x;
                float y = axis.y;
                float z = axis.z;

                return float3x3(
                    t * x * x + c,      t * x * y - s * z,  t * x * z + s * y,
                    t * x * y + s * z,  t * y * y + c,      t * y * z - s * x,
                    t * x * z - s * y,  t * y * z + s * x,  t * z * z + c
                );
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // --- 1. Generate View Ray from Frame UVs ---
                
                // UV to NDC (-1 to 1)
                float2 uvNDC = i.uv * 2.0 - 1.0;
                
                // Aspect Ratio Calc
                uvNDC.x *= _Aspect;

                // Focal length
                float fovRad = radians(_FOV);
                float focalLength = 1.0 / tan(fovRad * 0.5);

                // Ray Direction (Camera Geometry: +Z forward, +X right, +Y up)
                float3 rayDir = normalize(float3(uvNDC.x, uvNDC.y, focalLength));

                // --- 2. Apply Pan/View Rotation ---
                // Pan X (Yaw), Pan Y (Pitch)
                float3x3 rotPanX = AngleAxis3x3(_PanX, float3(0,1,0));
                float3x3 rotPanY = AngleAxis3x3(-_PanY, float3(1,0,0)); // Invert Y natural feel

                rayDir = mul(rotPanY, rayDir); // Apply pitch independent of yaw? or yaw then pitch?
                // Usually Yaw then Pitch for FPS look, but 'Pan' might be orbit. 
                // Let's do Yaw (Global Y) then Pitch (Local X) -> standard.
                rayDir = mul(rotPanX, rayDir);


                // --- 3. Determine Eye ---
                sampler2D texToUse = _LeftEyeTexture;
                bool isRightEye = false;

                // Simple check for Stereo
                #if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
                    if (unity_StereoEyeIndex == 1) { isRightEye = true; texToUse = _RightEyeTexture; }
                #else
                    // Fallback for non-stereo testing? Or maybe single pass double wide?
                    // We'll stick to Unity standard variables.
                    // If running in game view without VR, eye index might be 0.
                #endif

                // --- 4. Find Best Camera View (R, L, U, D) ---
                
                float2 camUV;
                float2 finalTileUV = float2(0,0);
                float tileOffset = 0;
                bool found = false;

                // Order of check defines layering if overlaps logic is boolean. 
                // Or we can check which is closest to center (z value closest to 1).
                
                float bestZ = 0;
                int bestCam = -1; // 0=R, 1=L, 2=U, 3=D

                // Check Right (0)
                {
                    float3 local = mul(transpose(RotationMatrix(ROT_R)), rayDir);
                    if (local.z > 0)
                    {
                         float2 p = local.xy / local.z;
                         if (abs(p.x) <= 1.0 && abs(p.y) <= 1.0)
                         {
                             // We have a candidate.
                             if (local.z > bestZ) { bestZ = local.z; bestCam = 0; }
                         }
                    }
                }
                // Check Left (1)
                {
                    float3 local = mul(transpose(RotationMatrix(ROT_L)), rayDir);
                    if (local.z > 0)
                    {
                         float2 p = local.xy / local.z;
                         if (abs(p.x) <= 1.0 && abs(p.y) <= 1.0)
                         {
                             if (local.z > bestZ) { bestZ = local.z; bestCam = 1; }
                         }
                    }
                }
                // Check Up (2)
                {
                    float3 local = mul(transpose(RotationMatrix(ROT_U)), rayDir);
                    if (local.z > 0)
                    {
                         float2 p = local.xy / local.z;
                         if (abs(p.x) <= 1.0 && abs(p.y) <= 1.0)
                         {
                             if (local.z > bestZ) { bestZ = local.z; bestCam = 2; }
                         }
                    }
                }
                // Check Down (3)
                {
                    float3 local = mul(transpose(RotationMatrix(ROT_D)), rayDir);
                    if (local.z > 0)
                    {
                         float2 p = local.xy / local.z;
                         if (abs(p.x) <= 1.0 && abs(p.y) <= 1.0)
                         {
                             if (local.z > bestZ) { bestZ = local.z; bestCam = 3; }
                         }
                    }
                }

                // If no camera sees this ray
                if (bestCam == -1)
                {
                    return fixed4(0,0,0,1);
                }

                // Calculate final UV for best cam
                float3 targetRot;
                float uOffset = 0;

                if (bestCam == 0) { targetRot = ROT_R; uOffset = 0.0; }
                else if (bestCam == 1) { targetRot = ROT_L; uOffset = 0.25; }
                else if (bestCam == 2) { targetRot = ROT_U; uOffset = 0.50; }
                else { targetRot = ROT_D; uOffset = 0.75; }

                float3 finalLocal = mul(transpose(RotationMatrix(targetRot)), rayDir);
                float2 finalProj = finalLocal.xy / finalLocal.z;
                float2 uvs01 = finalProj * 0.5 + 0.5;

                // Scale for Tile
                // Input texture is 4 horizontal tiles (R, L, U, D)
                // Width = 1.0. Each tile = 0.25 width.
                
                finalTileUV.x = uvs01.x * 0.25 + uOffset;
                finalTileUV.y = uvs01.y;

                return tex2D(texToUse, finalTileUV);
            }
            ENDCG
        }
    }
}
