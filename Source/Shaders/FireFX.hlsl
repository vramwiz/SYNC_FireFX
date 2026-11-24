// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// The constant buffer and pixel fields match FireFX_Field.pas.

struct Field
{
    float4 bounds;
    float4 axis;
    float4 shape;
    float4 detail;
    float4 core;
    float4 middle;
    float4 outer;
    float4 clip;
};

cbuffer FireScene : register(b0)
{
    float4 info;
    float4 bounds;
    float4 haze;
    float4 hazeParams;
    float4 backgroundX;
    float4 backgroundY;
    Field fields[480];
};

Texture2D<float4> background : register(t0);

float randomAt(int2 p, int seed)
{
    uint h = asuint(p.x)*0x9e3779b1u ^ asuint(p.y)*0x85ebca77u ^ asuint(seed)*0xc2b2ae3du;
    h = (h ^ (h >> 16))*0x7feb352du;
    h = (h ^ (h >> 15))*0x846ca68bu;
    return ((h ^ (h >> 16)) >> 8)*(1.0/16777216.0);
}

float noiseAt(float2 p, int seed)
{
    int2 cell = (int2)floor(p);
    float2 t = frac(p);
    t = t*t*(3-2*t);
    return lerp(lerp(randomAt(cell, seed), randomAt(cell+int2(1,0), seed), t.x),
                lerp(randomAt(cell+int2(0,1), seed), randomAt(cell+int2(1,1), seed), t.x), t.y);
}

float4 flameAt(Field f, float u, float v, int seed)
{
    if (v < -0.13 || v > 1.12) return 0;
    float amplitude = f.detail.x;
    u -= f.shape.y*4*v*(1-v);
    float radius = (0.20+0.83*smoothstep(-0.06,0.22,v))*(1-smoothstep(0.25,1.10,v));
    if (abs(u) > radius+0.6+amplitude*0.55) return 0;
    float edge = noiseAt(float2(v*4.3-f.shape.w*0.37,f.middle.w),seed)-0.5;
    u -= edge*amplitude*smoothstep(0.04,0.92,v)*0.97;
    if (abs(u) > radius+0.52) return 0;
    float grain = noiseAt(float2(u*2.6,v*(4+f.detail.y*8)-f.shape.w),seed+17)-0.5;
    float layer = noiseAt(float2(u*6.5+grain,v*12.5-f.shape.w*1.61),seed+29)-0.5;
    radius += (grain*0.21+layer*0.09)*amplitude;
    float rim = abs(u);
    rim += f.detail.z*smoothstep(0.34,0.76,v)*(1-smoothstep(0.06,0.53,rim))*
        smoothstep(0.10,0.49,grain+0.35)*0.43;
    float body = 1-smoothstep(radius-(0.11+f.detail.w*0.16),radius+0.10+f.detail.w*0.19,rim);
    float core = 1-smoothstep(0.03,max(0.13,radius*0.82),rim);
    float fade = smoothstep(-0.10,0.025,v)*(1-smoothstep(0.81+grain*0.16,1.10+grain*0.18,v));
    float heat = saturate(core*0.68+f.core.w*0.36-v*0.36+
        (grain+layer*0.43)*(0.33+f.detail.y*0.44));
    float3 color = lerp(f.outer.rgb,f.middle.rgb,saturate(body*0.78+heat*0.45));
    color = lerp(color,f.core.rgb,smoothstep(0.29,0.82,heat));
    if (f.outer.r > f.outer.b)
        color = lerp(color,float3(0.32,0.26,0.94),
            f.outer.w*(1-smoothstep(-0.04,0.24,v))*(1-core*0.42));
    return float4(color,saturate(body*fade*f.shape.z*(0.67+heat*0.41+grain*0.21)));
}

float4 smokeAt(Field f, float u, float v, int seed)
{
    if (v < -0.05 || v > 1.02) return 0;
    float width = 0.20+v*f.detail.y;
    u -= f.shape.y*4*v*(1-v);
    if (abs(u) > width+0.65) return 0;
    float edge = noiseAt(float2(v*4.6-f.shape.w*0.52,13.3),seed)-0.5;
    u -= edge*f.detail.x*smoothstep(0.0,0.7,v);
    float grain = noiseAt(float2(u*3.2+7.0,v*6.6-f.shape.w),seed+13);
    float layer = noiseAt(float2(u*7.3-grain,v*13-f.shape.w*1.4),seed+27);
    width *= 0.72+grain*0.48+layer*0.18;
    float alpha = (1-smoothstep(0.01,max(0.12,width),abs(u)))*
        smoothstep(-0.04,0.13,v)*(1-smoothstep(0.36,1.02,v))*
        f.shape.z*(0.20+0.60*grain+0.20*layer);
    return float4(lerp(f.middle.rgb,f.core.rgb,grain),alpha);
}

float4 fieldAt(Field f, float2 pixelPosition)
{
    float2 delta = pixelPosition-f.axis.xy;
    int kind = (int)f.clip.x;
    int seed = (int)f.clip.y;
    if (kind == 2 || kind == 4)
    {
        float2 uv = delta/f.axis.zw;
        float radius = dot(uv,uv);
        if (radius >= 1) return 0;
        float falloff = 1-radius;
        if (kind == 4)
        {
            float flecks = noiseAt(uv*float2(3.1,3.5)-float2(0,f.shape.w),seed);
            return float4(lerp(f.outer.rgb,f.core.rgb,smoothstep(0.37,0.83,flecks)),
                f.shape.z*falloff*falloff*smoothstep(0.28,0.86,flecks));
        }
        return float4(lerp(f.outer.rgb,f.core.rgb,falloff*falloff),
            f.shape.z*falloff*falloff*falloff);
    }
    float invLength = rsqrt(dot(f.axis.zw,f.axis.zw));
    float u = dot(delta,float2(-f.axis.w,f.axis.z))*invLength/f.shape.x;
    float v = dot(delta,f.axis.zw)*invLength*invLength;
    float4 value;
    if (kind == 0)
        value = flameAt(f,u,v,seed);
    else if (kind == 1)
        value = smokeAt(f,u,v,seed);
    else
    {
        float d = u*u+4*(v-0.5)*(v-0.5);
        float core = 1-smoothstep(0.01,0.23,d);
        float halo = (1-smoothstep(0.04,1.0,d))*f.detail.x*0.58;
        value = float4(lerp(f.outer.rgb,f.core.rgb,core),f.shape.z*saturate(core+halo));
    }
    if (f.clip.z > -1e8)
        value.a *= smoothstep(f.clip.z,f.clip.z+f.clip.w,pixelPosition.y);
    return value;
}

float4 heatHaze(float2 pixelPosition)
{
    if (hazeParams.x == 0) return 0;
    float2 relative = (pixelPosition-haze.xy)/haze.zw;
    float radius = dot(relative,relative);
    if (radius >= 1) return 0;
    float strength = (1-smoothstep(0.02,1,radius))*hazeParams.y;
    float phase = hazeParams.z;
    float2 flow = float2(
        noiseAt(pixelPosition*float2(0.05,0.027)-float2(0,phase*1.85),738)-0.5,
        noiseAt(pixelPosition*float2(0.044,0.034)-float2(0,phase*1.41),910)-0.5);
    float3 p = float3(pixelPosition+flow*strength,1);
    float2 source = float2(dot(backgroundX.xyz,p),dot(backgroundY.xyz,p))-0.5;
    float2 size = float2(backgroundX.w,backgroundY.w);
    if (any(source < 0) || any(source >= size-1)) return 0;
    int2 origin = (int2)floor(source);
    float2 t = frac(source);
    float4 pixel = lerp(
        lerp(background.Load(int3(origin,0)), background.Load(int3(origin+int2(1,0),0)),t.x),
        lerp(background.Load(int3(origin+int2(0,1),0)), background.Load(int3(origin+int2(1,1),0)),t.x),t.y);
    return pixel*saturate(strength*0.24);
}

float4 psmain(float4 position : SV_Position) : SV_Target
{
    float2 pixelPosition = position.xy;
    float4 result = heatHaze(pixelPosition);
    if (all(pixelPosition >= bounds.xy) && all(pixelPosition <= bounds.zw))
    {
        [loop] for (int i = 0; i < (int)info.x; ++i)
        {
            float4 box = fields[i].bounds;
            if (all(pixelPosition >= box.xy) && all(pixelPosition <= box.zw))
            {
                float4 source = fieldAt(fields[i],pixelPosition);
                result = float4(source.rgb*source.a,source.a)+result*(1-source.a);
            }
        }
    }
    return result;
}
