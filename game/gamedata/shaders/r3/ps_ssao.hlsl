#include "common.h"
uniform float4 m_v2w;
#ifndef	SSAO_QUALITY
#ifdef USE_MSAA
float	calc_ssao( float3 P, float3 N, float2 tc, float2 tcJ, float4 pos2d, uint iSample )
#else
float	calc_ssao( float3 P, float3 N, float2 tc, float2 tcJ, float4 pos2d )
#endif
{
	return 1.0;
}
#else	//	SSAO_QUALITY
#if SSAO_QUALITY >= 3
#define RINGS 3
#define DIRS 8
static const float rads[4] =
{ //I know it will be more focused in the cener, but that's OK
    0.20000f,
	0.57735f,
	0.81650f,
	1.00000f
};
static const float angles[9] =
{
	0.0000f,
	0.7854f,
	1.5708f,
	2.3562f,
	3.1416f,
	3.9267f,
	4.7124f,
	5.4978f,
	6.2832f
};
#elif SSAO_QUALITY == 2
#define RINGS  3
#define DIRS 4
static const float rads[4] =
{ //I know it will be more focused in the cener, but that's OK
    0.20000f,
	0.57735f,
	0.81650f,
	1.00000f
};
static const float angles[5] =
{
	0.0000f,
	1.5708f,
	3.1416f,
	4.7124f,
	6.2832f
};
#elif SSAO_QUALITY == 1
#define RINGS 2
#define DIRS 4
static const float rads[3] =
{ //I know it will be more focused in the cener, but that's OK
    0.2000f,
    0.7071f,
	1.0000f,
};
static const float angles[5] =
{
	0.0000f,
	1.5708f,
	3.1416f,
	4.7124f,
	6.2832f
};
#endif

Texture2D	jitter0;
sampler		smp_jitter;
Texture2D	jitterMipped;

float3 uv_to_eye(float2 uv, float eye_z)
{
    uv = (uv * float2(2.0, 2.0) - float2(1.0, 1.0));
    return float3(uv * pos_decompression_params.xy * eye_z, eye_z);
}

//	Screen space ambient occlusion
//	P	screen space position of the original point
//	N	screen space normal of the original point
//	tc	G-buffer coordinates of the original point
#ifndef USE_MSAA
float calc_ssao( float3 P, float3 N, float2 tc, float2 tcJ, float4 pos2d )
#else
float calc_ssao( float3 P, float3 N, float2 tc, float2 tcJ, float4 pos2d, uint iSample )
#endif
{
	const float ssao_noise_tile_factor = ssao_params.x;
	const float ssao_kernel_size = ssao_params.y;

	float point_depth = P.z;
	if (point_depth<0.01) point_depth = 100000.0h;	//	filter for the sky
	float2 scale = float2(.5f / 1024.h, .5f / 768.h)*ssao_kernel_size/max(point_depth,1.3);

	// sample 
	float occ	= 0.0h;	
	float num_dir	= 0.0h;

	// jittering
	float3 tc1	= mul(m_v2w, float4(P,1));
	tc1 *= ssao_noise_tile_factor;
	tc1.xz += tc1.y;
	float2	SmallTap = jitter0.Sample( smp_jitter, tc1.xz );

[unroll] for (int rad=0; rad < RINGS; rad++)
{
	[unroll] for (int dir=0; dir < DIRS; dir++)
	{
		SmallTap.x *= 31337.0f;
		SmallTap.y *= 73313.0f;
		SmallTap = frac(SmallTap);
		float	r		= lerp(rads[rad]*1.3, rads[rad+1]*1.3, SmallTap.x);
		float   a		= lerp(angles[dir], angles[dir+1], SmallTap.y);
		float s, c;
		sincos( a, s, c );
		float2	tap = float2( r * c, r * s );
				tap		*= scale;
				tap		+= tc;
#ifndef SSAO_OPT_DATA
#	ifdef USE_MSAA
	// this is wrong - need to correct this
	gbuffer_data gbd = gbuffer_load_data_offset( tc, tap, pos2d, iSample ); 
#	else
	// this is wrong - need to correct this
	gbuffer_data gbd = gbuffer_load_data_offset( tc, tap, pos2d ); 
#	endif
		float3	tap_pos	= gbd.P;
#else // SSAO_OPT_DATA
		float	z	= s_half_depth.SampleLevel(smp_nofilter,tap, 0);
		float3	tap_pos	= uv_to_eye(tap, z);
#endif // SSAO_OPT_DATA
		float3 	dir 	= tap_pos-P.xyz;
		float	dist	= length(dir);
				dir 	= normalize(dir);


		float 	infl 	= saturate(dot( dir, N.xyz));
		float 	occ_factor = saturate(dist);
		float	range_att = saturate(1-dist*0.5);
		
		occ += (infl+0.01)*lerp( 1, occ_factor, infl)*range_att;
		num_dir += (infl+0.01)*range_att;
	}
}
	occ /= num_dir;
	occ = saturate(occ);
#if SSAO_QUALITY==1
	occ = (occ+0.3)/(1+0.3);
#else
	occ = (occ+0.2)/(1+0.2);
#endif

	float WeaponAttenuation = smoothstep( 0.8, 0.9, length( P.xyz ));
	occ = lerp( 1, occ, WeaponAttenuation );

	return occ;
}
#endif	//	SSAO_QUALITY