//
//  Flow.metal
//  VisualEngine
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

#include <metal_stdlib>
using namespace metal;

// Must exactly match `FlowUniforms` in FlowRenderer.swift.
struct FlowUniforms {
    float4 colors[5];   // OKLab in xyz, from dark to light.
    float2 resolution;
    float time;
    int style;
    float scale;
    float warp;
    float2 padding;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut fullscreenVertex(uint vertexID [[vertex_id]]) {
    float2 corner = float2((vertexID << 1) & 2, vertexID & 2);
    VertexOut out;
    out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(corner.x, 1.0 - corner.y);
    return out;
}

// MARK: - Noise

static uint3 pcg3d(uint3 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    v ^= v >> 16u;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    return v;
}

static float3 gradient(int3 cell) {
    float3 random = float3(pcg3d(as_type<uint3>(cell))) * (1.0 / 4294967295.0);
    return random * 2.0 - 1.0;
}

static float gradientNoise(float3 p) {
    float3 floored = floor(p);
    int3 cell = int3(floored);
    float3 f = p - floored;
    float3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    float n000 = dot(gradient(cell + int3(0, 0, 0)), f - float3(0, 0, 0));
    float n100 = dot(gradient(cell + int3(1, 0, 0)), f - float3(1, 0, 0));
    float n010 = dot(gradient(cell + int3(0, 1, 0)), f - float3(0, 1, 0));
    float n110 = dot(gradient(cell + int3(1, 1, 0)), f - float3(1, 1, 0));
    float n001 = dot(gradient(cell + int3(0, 0, 1)), f - float3(0, 0, 1));
    float n101 = dot(gradient(cell + int3(1, 0, 1)), f - float3(1, 0, 1));
    float n011 = dot(gradient(cell + int3(0, 1, 1)), f - float3(0, 1, 1));
    float n111 = dot(gradient(cell + int3(1, 1, 1)), f - float3(1, 1, 1));

    return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
               mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

static float fbm(float3 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < octaves; i++) {
        value += amplitude * gradientNoise(p);
        p = float3(p.x * 1.6 - p.y * 1.2, p.x * 1.2 + p.y * 1.6, p.z * 1.7) + 11.3;
        amplitude *= 0.5;
    }
    return value;
}

// MARK: - Color

static float3 ramp(float t, constant float4 *colors) {
    float x = saturate(t) * 3.9999;
    int index = int(x);
    float blend = smoothstep(0.0, 1.0, x - float(index));
    return mix(colors[index].xyz, colors[index + 1].xyz, blend);
}

static float3 oklabToLinear(float3 lab) {
    float l = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
    float m = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
    float s = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;
    l = l * l * l;
    m = m * m * m;
    s = s * s * s;
    return float3( 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                  -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                  -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
}

// MARK: - Styles

static float3 liquid(float2 p, float t, float warp, constant float4 *colors) {
    float2 q = float2(fbm(float3(p, t), 2),
                      fbm(float3(p + float2(5.2, 1.3), t), 2));
    float2 warped = p + warp * q;
    float2 r = float2(fbm(float3(warped + float2(1.7, 9.2), t * 0.8), 2),
                      fbm(float3(warped + float2(8.3, 2.8), t * 0.7), 2));
    float field = fbm(float3(p + warp * r, t * 0.6), 3);

    float position = 0.5 + 1.7 * field + 0.6 * r.x - 0.35 * q.y;
    float3 color = oklabToLinear(ramp(position, colors));
    return color * (0.85 + 0.6 * length(r));
}

// Waves seen in profile: layers from far to near, lit from the crest.
static float3 ocean(float2 uv, float2 p, float t, float warp, constant float4 *colors) {
    const int layers = 8;
    float3 color = oklabToLinear(ramp(0.95 - 0.5 * uv.y, colors));

    for (int i = 0; i < layers; i++) {
        float depth = float(i) / float(layers - 1);
        float x = p.x * mix(2.4, 0.8, depth) + depth * 17.0;
        float swell = 0.55 * sin(x * 1.4 + t * (1.0 + 1.6 * depth))
                    + (1.0 + 0.6 * warp) * fbm(float3(x * 0.6, t * 0.5, depth * 5.0), 3);
        float crest = mix(0.14, 0.88, depth) + swell * mix(0.06, 0.2, depth);
        float distance = uv.y - crest;

        float softness = mix(0.03, 0.012, depth);
        float mask = smoothstep(-softness, softness, distance);
        float shade = mix(0.72, 0.08, depth) + 0.3 * exp(-max(distance, 0.0) * 9.0);
        color = mix(color, oklabToLinear(ramp(shade, colors)), mask);
    }
    return color;
}

// Ribbons of light with vertical folds over a dark background.
static float3 aurora(float2 uv, float2 p, float t, float warp, constant float4 *colors) {
    float3 color = oklabToLinear(ramp(0.03 + 0.14 * uv.y, colors));
    for (int i = 0; i < 4; i++) {
        float layer = float(i);
        float x = p.x * (0.8 + 0.25 * layer) + layer * 3.1;
        x += warp * 0.3 * fbm(float3(p * 0.6, t * 0.4 + layer), 2);

        float center = 0.3 + 0.15 * layer + 0.4 * fbm(float3(x * 0.55, t * 0.45, layer * 3.0), 3);
        float distance = uv.y - center;
        float falloff = exp(-distance * distance * (distance > 0.0 ? 22.0 : 7.0));

        float folds = saturate(0.55 + 1.5 * fbm(float3(x * 5.0, t * 0.8, layer), 2));
        float tone = 0.62 + 0.13 * layer + 0.5 * distance;
        color += oklabToLinear(ramp(tone, colors)) * falloff * folds * 0.5;
    }
    return color;
}

// First pass: the fluid field, at low resolution and in linear color.
fragment float4 flowFragment(VertexOut in [[stage_in]], constant FlowUniforms &uniforms [[buffer(0)]]) {
    float aspect = uniforms.resolution.x / uniforms.resolution.y;
    float2 p = (in.uv - 0.5) * float2(aspect, 1.0) * uniforms.scale;

    float3 color;
    switch (uniforms.style) {
    case 1:
        color = ocean(in.uv, p, uniforms.time, uniforms.warp, uniforms.colors);
        break;
    case 2:
        color = aurora(in.uv, p, uniforms.time, uniforms.warp, uniforms.colors);
        break;
    default:
        color = liquid(p, uniforms.time, uniforms.warp, uniforms.colors);
        break;
    }
    return float4(max(color, 0.0), 1.0);
}

// MARK: - Presentation

static float3 linearToSRGB(float3 c) {
    c = saturate(c);
    return select(1.055 * pow(c, 1.0 / 2.4) - 0.055, 12.92 * c, c <= 0.0031308);
}

// Second pass: rescales to the real resolution and avoids color banding.
fragment float4 presentFragment(VertexOut in [[stage_in]], texture2d<float> flow [[texture(0)]]) {
    constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
    float3 color = flow.sample(bilinear, in.uv).rgb;

    float2 centered = in.uv - 0.5;
    color *= 1.0 - 0.55 * smoothstep(0.25, 0.85, length(centered));

    // Fixed triangular dithering: if it changed every frame, it would be harder to compress for AirPlay.
    uint3 hash = pcg3d(uint3(uint2(in.position.xy), 0u));
    float2 random = float2(hash.xy) * (1.0 / 4294967295.0);
    float dither = (random.x + random.y - 1.0) / 255.0;

    return float4(linearToSRGB(color) + dither, 1.0);
}
