#include <metal_stdlib>
using namespace metal;

// -----------------------------------------------------------------------------
// OltraFlim film renderer
//
// Pipeline: scene-linear Rec.709 source (RAW decoded with headroom, or an
// sRGB photo converted to linear by Core Image) -> darkroom adjustments ->
// ACEScc -> 33^3 film LMT (already baked through the ACES 2.0 SDR Rec.709
// output transform) -> encoded Rec.709, with halation, grain and vignette.
//
// Imported ACEScc LMTs skip the ACES 2.0 bake and sample the neutral pack
// entry as the display transform instead (see processImage).
// -----------------------------------------------------------------------------

struct Uniforms {
    float exposure;        // EV
    float contrast;
    float highlights;
    float shadows;
    float whites;
    float blacks;
    float temperature;
    float tint;
    float vibrance;
    float saturation;
    float clarity;
    float sharpen;
    float grain;
    float grainSize;
    float grainSeed;
    float halation;
    float halationThreshold;
    float vignette;
    float strength;
    float showOriginal;
    float useFilm;
    float ditherSeed;
    float imageWidth;
    float imageHeight;
    float previewScale;
    float exposureBias;   // centre-weighted auto exposure baseline, in stops
    float destOffsetX;
    float destOffsetY;
    float useDisplayLUT;
    float displayLUTStrength;
    float tonalTransparency;
    float colorTransparency;
    float blackPoint;
    float whitePoint;
    float whiteDeltaR;
    float whiteDeltaG;
    float whiteDeltaB;
    float blackDeltaR;
    float blackDeltaG;
    float blackDeltaB;
    float halationWarmth;
    float halationRadius;
    float grainChroma;
    float grainShadow;
    float fade;
    float hueShift;
    float colorDensity;
    float skinSaturation;
    float greenSaturation;
    float blueSaturation;
    float highlightWarmth;
    float shadowCoolness;
    float midtones;
    float highlightRolloff;
    float bloom;
    float grainRoughness;
    float vignetteMidpoint;
    float vignetteRoundness;
    float vignetteFeather;
    float vignetteCenterX;
    float vignetteCenterY;
    float lutDomain;      // 0 = display-referred Rec.709 LUT, 1 = ACEScc LMT
    float lutExposureEV;  // LMT input exposure bake, in stops
};

struct DisplayUniforms {
    float viewWidth;
    float viewHeight;
    float imageWidth;
    float imageHeight;
    float fitScale;
    float zoom;
    float panX;
    float panY;
    float backingScale;
    float compareEnabled;
    float splitX;
    float pad0;
    float pad1;
};

constant float3 LUMA = float3(0.2126f, 0.7152f, 0.0722f);
constant float3 R709_TO_AP1_ROW0 = float3(0.61309743f, 0.33952314f, 0.04737945f);
constant float3 R709_TO_AP1_ROW1 = float3(0.07019372f, 0.91635388f, 0.01345240f);
constant float3 R709_TO_AP1_ROW2 = float3(0.02061559f, 0.10956977f, 0.86981463f);

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

inline float srgb_to_linear(float x) {
    return x <= 0.04045f ? x / 12.92f : pow((x + 0.055f) / 1.055f, 2.4f);
}

inline float3 srgb_to_linear3(float3 c) {
    return float3(srgb_to_linear(c.r), srgb_to_linear(c.g), srgb_to_linear(c.b));
}

inline float linear_to_srgb(float x) {
    x = max(x, 0.0f);
    return x <= 0.0031308f ? x * 12.92f : 1.055f * pow(x, 1.0f / 2.4f) - 0.055f;
}

inline float3 linear_to_srgb3(float3 c) {
    return float3(linear_to_srgb(c.r), linear_to_srgb(c.g), linear_to_srgb(c.b));
}

// ACEScc as published in S-2014-003: the linear toe is 2^-16 and the
// second branch adds half the value, not the value itself.
inline float acescc_channel(float x) {
    if (x <= 0.0f) {
        return (log2(1.0f / 65536.0f) + 9.72f) / 17.52f;
    } else if (x < 1.0f / 65536.0f) {
        return (log2(1.0f / 65536.0f + 0.5f * x) + 9.72f) / 17.52f;
    }
    return (log2(x) + 9.72f) / 17.52f;
}

inline float3 acescc_encode(float3 c) {
    return float3(acescc_channel(c.r), acescc_channel(c.g), acescc_channel(c.b));
}

inline float3 rgb_to_hsv(float3 c) {
    float maxC = max(max(c.r, c.g), c.b);
    float minC = min(min(c.r, c.g), c.b);
    float delta = maxC - minC;
    float h = 0.0f;
    if (delta > 1e-5f) {
        if (maxC == c.r) {
            h = fmod((c.g - c.b) / delta + 6.0f, 6.0f);
        } else if (maxC == c.g) {
            h = (c.b - c.r) / delta + 2.0f;
        } else {
            h = (c.r - c.g) / delta + 4.0f;
        }
        h /= 6.0f;
    }
    float s = maxC > 1e-5f ? delta / maxC : 0.0f;
    return float3(h, s, maxC);
}

inline float3 hsv_to_rgb(float3 hsv) {
    float h = fract(hsv.x) * 6.0f;
    float s = clamp(hsv.y, 0.0f, 1.0f);
    float v = clamp(hsv.z, 0.0f, 1.0f);
    float c = v * s;
    float x = c * (1.0f - fabs(fmod(h, 2.0f) - 1.0f));
    float3 rgb = float3(0.0f);
    if (h < 1.0f) rgb = float3(c, x, 0.0f);
    else if (h < 2.0f) rgb = float3(x, c, 0.0f);
    else if (h < 3.0f) rgb = float3(0.0f, c, x);
    else if (h < 4.0f) rgb = float3(0.0f, x, c);
    else if (h < 5.0f) rgb = float3(x, 0.0f, c);
    else rgb = float3(c, 0.0f, x);
    return rgb + float3(v - c);
}

inline float hueWeight(float hue, float center, float width) {
    float d = fabs(hue - center);
    d = min(d, 360.0f - d);
    return max(0.0f, 1.0f - d / width);
}

inline float hash21(float2 p) {
    p = fract(p * float2(123.34f, 456.21f));
    p += dot(p, p + 45.32f);
    return fract(p.x * p.y);
}

inline float soft_clip(float x) {
    return x < 0.0f ? 0.0f : x;
}

// -----------------------------------------------------------------------------
// Bloom (halation)
// -----------------------------------------------------------------------------

kernel void bloomExtract(texture2d<float, access::sample> src [[texture(0)]],
                         texture2d<float, access::write> dst [[texture(1)]],
                         constant Uniforms &u [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = (float2(gid) + 0.5f) / float2(dst.get_width(), dst.get_height());
    // The source texture already holds scene-linear Rec.709 values.
    float3 c = max(src.sample(s, uv).rgb, 0.0f);
    float luma = dot(c, LUMA);
    float threshold = 0.35f + (u.halationThreshold / 100.0f) * 0.55f;
    float over = max(luma - threshold, 0.0f);
    over = over / (1.0f + over);
    // Halation is warm: the red layer of the negative scatters furthest.
    float warm = clamp(u.halationWarmth / 100.0f, 0.0f, 1.0f);
    float3 tint = mix(float3(1.0f, 1.0f, 1.0f), float3(1.0f, 0.30f, 0.16f), warm);
    // Alpha carries the untinted intensity so bloom can reuse the same pass.
    dst.write(float4(over * tint, over), gid);
}

kernel void blurHorizontal(texture2d<float, access::sample> src [[texture(0)]],
                           texture2d<float, access::write> dst [[texture(1)]],
                           constant Uniforms &u [[buffer(0)]],
                           uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = (float2(gid) + 0.5f) / float2(dst.get_width(), dst.get_height());
    float radius = (2.0f + u.halationRadius * 0.22f) / float(dst.get_width());
    float4 acc = float4(0.0f);
    float weights[5] = {0.227f, 0.194f, 0.121f, 0.054f, 0.016f};
    for (int i = 1; i <= 4; i++) {
        float o = radius * float(i);
        acc += src.sample(s, uv - float2(o, 0.0f)) * weights[i];
        acc += src.sample(s, uv + float2(o, 0.0f)) * weights[i];
    }
    acc += src.sample(s, uv) * 0.227f;
    dst.write(acc, gid);
}

kernel void blurVertical(texture2d<float, access::sample> src [[texture(0)]],
                         texture2d<float, access::write> dst [[texture(1)]],
                         constant Uniforms &u [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = (float2(gid) + 0.5f) / float2(dst.get_width(), dst.get_height());
    float radius = (2.0f + u.halationRadius * 0.22f) / float(dst.get_height());
    float4 acc = float4(0.0f);
    float weights[5] = {0.227f, 0.194f, 0.121f, 0.054f, 0.016f};
    for (int i = 1; i <= 4; i++) {
        float o = radius * float(i);
        acc += src.sample(s, uv - float2(0.0f, o)) * weights[i];
        acc += src.sample(s, uv + float2(0.0f, o)) * weights[i];
    }
    acc += src.sample(s, uv) * 0.227f;
    dst.write(acc, gid);
}

// -----------------------------------------------------------------------------
// Film grain (Boolean particle model)
// -----------------------------------------------------------------------------
//
// Reference implementations: the IPOL 2017 real-film grain renderer and
// AlcedoStudio's separable Bernoulli grain (drt_neighbor.metal, GPLv3).
// Only the algorithm was studied; this is an independent Metal implementation.
//
// A developed grain is a binary sample whose probability is the local density.
// Every output pixel reads the same lattice, so neighbouring pixels see the
// same particles and the field stays coherent. Two separable Gaussian passes
// turn that lattice into clumps: `grainHorizontal` filters each row into a
// coverage texture, `grainVertical` filters the columns and compares the
// coverage with the clean image, which preserves the mean density (and tone).

// RMS granularity (diffuse, x1000) sampled at density 0.0 ... 1.0, approximated
// from published granularity data for a typical ISO 400 colour negative. Each
// emulsion layer has its own curve; blue is the coarsest and red the finest.
constant float kGrainGranularityR[11] = {
    1.95f, 2.10f, 2.48f, 2.60f, 2.72f, 2.86f, 2.99f, 3.10f, 3.19f, 3.28f, 3.36f
};
constant float kGrainGranularityG[11] = {
    1.90f, 2.06f, 2.30f, 2.44f, 2.58f, 2.68f, 2.75f, 3.05f, 3.14f, 3.22f, 3.30f
};
constant float kGrainGranularityB[11] = {
    2.35f, 2.51f, 2.66f, 2.80f, 2.91f, 2.99f, 3.00f, 3.15f, 3.24f, 3.32f, 3.40f
};

inline float grainRandom(int2 p, uint seed) {
    uint h = uint(p.x) * 0x8da6b343u ^ uint(p.y) * 0xd8163841u ^ seed * 0xcb1ab31fu;
    h ^= h >> 16;
    h *= 0x7feb352du;
    h ^= h >> 15;
    h *= 0x846ca68bu;
    h ^= h >> 16;
    return float(h & 0x00ffffffu) * (1.0f / 16777216.0f);
}

inline float grainGranularity(int channel, float density) {
    float x = clamp(density, 0.0f, 1.0f) * 10.0f;
    int i = int(floor(x));
    int j = min(i + 1, 10);
    float t = x - float(i);
    if (channel == 0) return mix(kGrainGranularityR[i], kGrainGranularityR[j], t);
    if (channel == 1) return mix(kGrainGranularityG[i], kGrainGranularityG[j], t);
    return mix(kGrainGranularityB[i], kGrainGranularityB[j], t);
}

// Clump size in pixels. Grain is sized in image units, not pixels, so the same
// photo keeps its grain when previewed small and exported at full resolution.
inline float grainSigma(float grainSize, float roughness, uint width, uint height) {
    float minDim = max(min(float(width), float(height)), 1.0f);
    float rough = clamp(roughness / 100.0f, 0.0f, 1.0f);
    float sigma = (1.2f + clamp(grainSize, 0.0f, 100.0f) / 100.0f * 3.3f)
                * (0.85f + 0.3f * rough) * (minDim / 1600.0f);
    return max(sigma, 1.0f);
}

// Gaussian taps sit on every pixel row/column so neighbouring pixels share the
// particle lattice. The radius is capped to keep the cost bounded on the
// largest exports; up to 18 px still covers two sigma for a 45 MP frame.
inline int grainRadius(float sigma) {
    return min(18, max(1, int(ceil(2.0f * sigma))));
}

kernel void grainHorizontal(texture2d<float, access::sample> src [[texture(0)]],
                            texture2d<float, access::write> dst [[texture(1)]],
                            constant Uniforms &u [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float sigma = grainSigma(u.grainSize, u.grainRoughness, dst.get_width(), dst.get_height());
    int radius = grainRadius(sigma);

    float chroma = clamp(u.grainChroma / 100.0f, 0.0f, 1.0f);
    uint seed = uint(clamp(u.grainSeed, 0.0f, 4096.0f) * 100.0f) + 1u;
    float2 texSize = float2(src.get_width(), src.get_height());
    int2 origin = int2(gid);

    float3 coverage = float3(0.0f);
    float total = 0.0f;
    for (int i = -radius; i <= radius; i++) {
        // Taps are one pixel apart; a larger stride would put adjacent pixels
        // on different particle sublattices and turn the grain into static.
        int2 p = int2(origin.x + i, origin.y);
        float d = float(i);
        float w = exp(-0.5f * d * d / (sigma * sigma));
        float2 uv = (float2(p) + 0.5f) / texSize;
        float3 density = clamp(src.sample(s, uv).rgb, 0.0f, 1.0f);
        float densityLuma = dot(density, LUMA);
        float shared = grainRandom(p, seed) < densityLuma ? 1.0f : 0.0f;
        float3 particles = float3(shared);
        if (chroma > 0.001f) {
            float pr = grainRandom(p, seed + 101u) < density.r ? 1.0f : 0.0f;
            float pg = grainRandom(p, seed + 211u) < density.g ? 1.0f : 0.0f;
            float pb = grainRandom(p, seed + 307u) < density.b ? 1.0f : 0.0f;
            particles = mix(particles, float3(pr, pg, pb), chroma);
        }
        coverage += w * particles;
        total += w;
    }
    dst.write(float4(coverage / total, 1.0f), gid);
}

kernel void grainVertical(texture2d<float, access::sample> src [[texture(0)]],
                          texture2d<float, access::sample> coverage [[texture(1)]],
                          texture2d<float, access::write> dst [[texture(2)]],
                          constant Uniforms &u [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;

    float4 center = src.read(gid);
    float3 base = clamp(center.rgb, 0.0f, 1.0f);
    float luma = dot(base, LUMA);

    // The slider is the fraction of the datasheet amplitude: full strength
    // stays just below the granularity of a pushed ISO 400 negative.
    float strength = clamp(u.grain / 100.0f, 0.0f, 1.0f) * 0.15f;

    float sigma = grainSigma(u.grainSize, u.grainRoughness, dst.get_width(), dst.get_height());
    int radius = grainRadius(sigma);
    int maxY = int(dst.get_height()) - 1;

    float3 cov = float3(0.0f);
    float total = 0.0f;
    float sumSquares = 0.0f;
    for (int j = -radius; j <= radius; j++) {
        int py = clamp(int(gid.y) + j, 0, maxY);
        float d = float(j);
        float w = exp(-0.5f * d * d / (sigma * sigma));
        cov += w * coverage.read(uint2(gid.x, uint(py))).rgb;
        total += w;
        sumSquares += w * w;
    }
    cov /= total;

    // Normalise the variance so clump size does not change the grain strength:
    // a dense lattice averages more particles, and without this correction a
    // large grain size would simply look weaker.
    float varianceFactor = sumSquares / (total * total);
    float varianceScale = 0.287f / max(varianceFactor, 1e-4f);

    // Preserve the mean density: only the filtered particle field minus the
    // clean value is added back.
    float3 error = (cov - base) * varianceScale;

    float shadowLift = clamp(u.grainShadow / 100.0f, 0.0f, 1.0f);
    float shadowMask = 1.0f - smoothstep(0.04f, 0.55f, luma);
    float hiMask = smoothstep(0.62f, 1.0f, luma);
    float headroom = (1.0f + 1.15f * shadowLift * shadowMask) * (1.0f - 0.62f * hiMask);

    float3 granularity = float3(
        grainGranularity(0, base.r),
        grainGranularity(1, base.g),
        grainGranularity(2, base.b)
    );
    granularity = clamp(granularity / 2.7f, 0.6f, 1.6f);

    float3 out = base + error * (strength * headroom) * granularity;
    dst.write(float4(clamp(out, 0.0f, 1.0f), 1.0f), gid);
}

// -----------------------------------------------------------------------------
// Main film pass
// -----------------------------------------------------------------------------

kernel void processImage(texture2d<float, access::sample> src [[texture(0)]],
                         texture2d<float, access::write> dst [[texture(1)]],
                         texture3d<float, access::sample> film [[texture(2)]],
                         texture3d<float, access::sample> neutral [[texture(3)]],
                         texture2d<float, access::sample> bloom [[texture(4)]],
                         texture3d<float, access::sample> userLUT [[texture(5)]],
                         texture2d<float, access::sample> curves [[texture(6)]],
                         constant Uniforms &u [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    constexpr sampler lutSampler(filter::linear, address::clamp_to_edge);
    constexpr sampler curveSampler(filter::linear, address::clamp_to_edge);

    uint2 outPos = gid + uint2(uint(u.destOffsetX), uint(u.destOffsetY));
    if (outPos.x >= dst.get_width() || outPos.y >= dst.get_height()) return;
    float2 uv = (float2(gid) + 0.5f) / float2(src.get_width(), src.get_height());
    float3 source = src.sample(s, uv).rgb;

    if (u.showOriginal > 0.5f) {
        // The source is scene-linear now, so the untouched original has to be
        // encoded for the display.
        dst.write(float4(linear_to_srgb3(source), 1.0f), outPos);
        return;
    }

    // Scene-linear Rec.709, possibly above 1.0 for RAW highlights.
    float3 linear = max(source, 0.0f);

    // ---- White balance -----------------------------------------------------
    float t = u.temperature / 100.0f;
    float ti = u.tint / 100.0f;
    float3 wb = float3(1.0f + 0.30f * t + 0.18f * ti,
                       1.0f - 0.14f * ti - 0.015f * t,
                       1.0f - 0.30f * t + 0.18f * ti);
    float wl = dot(wb, LUMA);
    wb = wb / max(wl, 1e-4f);
    linear *= wb;

    // ---- Exposure ----------------------------------------------------------
    // exposureBias carries the upstream-style center-weighted auto exposure:
    // the scene is normalised so its weighted mean lands on 18% grey before
    // the film LUT sees it.
    linear *= exp2(u.exposure + u.exposureBias);

    // ---- Tone shaping, luminance preserving --------------------------------
    float luma = dot(linear, LUMA);
    float logL = log2(max(luma, 1e-5f));
    float pivot = -2.4739f; // 18% grey
    float slope = exp2(u.contrast / 100.0f * 0.85f);
    float toneLog = pivot + (logL - pivot) * slope;

    float shMask = 1.0f - smoothstep(0.006f, 0.30f, luma);
    float bMask = 1.0f - smoothstep(0.008f, 0.09f, luma);
    toneLog += u.shadows / 100.0f * 2.0f * shMask;
    toneLog += u.blacks / 100.0f * 1.7f * bMask;

    // Midtones ride on a soft band around 18% grey so the extremes stay put.
    float midX = (toneLog - pivot) / 1.25f;
    toneLog += u.midtones / 100.0f * 0.85f * exp(-midX * midX);

    float scale = exp2(toneLog - logL);
    linear *= scale;
    // ACEScc 1.0 is linear 222, so keep the full scene range representable.
    linear = clamp(linear, 0.0f, 256.0f);

    // ---- Saturation / vibrance ---------------------------------------------
    float toneLuma = dot(linear, LUMA);
    float mx = max(max(linear.r, linear.g), linear.b);
    float mn = min(min(linear.r, linear.g), linear.b);
    float chroma = (mx - mn) / max(mx, 1e-4f);
    float sat = 1.0f + u.saturation / 100.0f;
    float vib = 1.0f + u.vibrance / 100.0f * pow(max(0.0f, 1.0f - chroma), 1.35f) * 1.25f;
    linear = max(float3(toneLuma) + (linear - float3(toneLuma)) * sat * vib, 0.0f);

    // ---- Local contrast -----------------------------------------------------
    float clarityRadius = max(1.0f, u.imageWidth * 0.006f) / max(u.previewScale, 0.01f);
    float sharpenRadius = 1.25f;
    float2 texel = 1.0f / float2(src.get_width(), src.get_height());
    float2 px = texel * max(u.previewScale, 1.0f);

    if (u.clarity > 0.001f) {
        float3 blur = float3(0.0f);
        float2 dirs[4] = {float2(1, 0), float2(0.7071f, 0.7071f), float2(0, 1), float2(-0.7071f, 0.7071f)};
        for (int i = 0; i < 4; i++) {
            float2 o = dirs[i] * texel * clarityRadius;
            blur += max(src.sample(s, uv + o).rgb, 0.0f);
            blur += max(src.sample(s, uv - o).rgb, 0.0f);
        }
        blur *= 0.125f;
        float detail = toneLuma - dot(blur, LUMA);
        linear += detail * (u.clarity / 100.0f) * 0.85f;
    }
    if (u.sharpen > 0.001f) {
        float3 blur = float3(0.0f);
        blur += max(src.sample(s, uv + float2(texel.x, 0)).rgb, 0.0f);
        blur += max(src.sample(s, uv - float2(texel.x, 0)).rgb, 0.0f);
        blur += max(src.sample(s, uv + float2(0, texel.y)).rgb, 0.0f);
        blur += max(src.sample(s, uv - float2(0, texel.y)).rgb, 0.0f);
        blur *= 0.25f;
        float detail = toneLuma - dot(blur, LUMA);
        linear += detail * (u.sharpen / 100.0f) * 1.6f;
    }
    linear = max(linear, 0.0f);

    // ---- Halation / bloom ---------------------------------------------------
    float4 glow = bloom.sample(s, uv);
    if (u.halation > 0.001f) {
        linear += glow.rgb * (u.halation / 100.0f) * 1.35f;
    }
    if (u.bloom > 0.001f) {
        // Alpha is the untinted highlight energy: neutral optical diffusion.
        linear += float3(glow.a) * (u.bloom / 100.0f) * 0.42f;
    }

    // ---- Film LUT or imported LUT ----------------------------------------
    float3 ap1 = float3(dot(linear, R709_TO_AP1_ROW0),
                        dot(linear, R709_TO_AP1_ROW1),
                        dot(linear, R709_TO_AP1_ROW2));
    float3 ccInput = clamp(acescc_encode(ap1) + u.lutExposureEV / 17.52f, 0.0f, 1.0f);

    float3 enc;
    if (u.useDisplayLUT > 0.5f) {
        if (u.lutDomain > 0.5f) {
            // ACEScc (AP1) -> ACEScc (AP1) LMT, the Alcedo export format.
            // `neutral` doubles as the ACES 2.0 SDR output transform: it is
            // the same ACEScc grid pushed through the display transform, so
            // sampling it after the LMT lands the film on screen.
            float3 ccOut = clamp(userLUT.sample(lutSampler, ccInput).rgb, 0.0f, 1.0f);
            float3 baseEnc = clamp(neutral.sample(lutSampler, ccInput).rgb, 0.0f, 1.0f);
            float3 filmEnc = clamp(neutral.sample(lutSampler, ccOut).rgb, 0.0f, 1.0f);
            enc = mix(baseEnc, filmEnc, clamp(u.displayLUTStrength, 0.0f, 1.0f));
        } else {
            // Display-referred Rec.709 -> Rec.709 creative LUT.
            float3 base = clamp(linear_to_srgb3(linear), 0.0f, 1.0f);
            float3 lutted = clamp(userLUT.sample(lutSampler, base).rgb, 0.0f, 1.0f);
            enc = mix(base, lutted, clamp(u.displayLUTStrength, 0.0f, 1.0f));
        }
    } else {
        float3 neutralEnc = neutral.sample(lutSampler, ccInput).rgb;
        float3 filmEnc = film.sample(lutSampler, ccInput).rgb;
        enc = u.useFilm > 0.5f ? mix(neutralEnc, filmEnc, clamp(u.strength, 0.0f, 1.0f))
                                  : neutralEnc;
    }

    // ---- Whites: display-referred white point -----------------------------
    // Applied after the film LUT because the print curve compresses scene-
    // linear highlights; a pre-LUT lift of half a stop barely moved the
    // displayed white and made the slider feel inert.
    if (u.whites != 0.0f) {
        float l = dot(enc, LUMA);
        float mask = smoothstep(0.45f, 0.95f, l);
        enc = clamp(enc + float3(u.whites / 100.0f * 0.20f * mask), 0.0f, 1.0f);
    }

    // ---- Highlights: display-referred recovery -----------------------------
    // Scene-linear lifting is crushed by the print shoulder in the film LUT
    // (measured: ±100 moved the image by ~4/255). Work on the printed
    // luminance instead, where the slider has the range photographers expect.
    if (u.highlights != 0.0f) {
        float l = dot(enc, LUMA);
        float mask = smoothstep(0.22f, 0.92f, l);
        float gamma = clamp(1.0f - u.highlights / 100.0f * mask * 0.85f, 0.25f, 3.0f);
        float shaped = pow(max(l, 1e-4f), gamma);
        enc = clamp(enc * (shaped / max(l, 1e-4f)), 0.0f, 1.0f);
    }

    // ---- Highlight rolloff: film shoulder in the print ---------------------
    // Compresses the top end toward white: highlights lift and flatten instead
    // of clipping, which is what a print shoulder does to a negative.
    if (u.highlightRolloff > 0.001f) {
        float l = dot(enc, LUMA);
        if (l > 0.52f) {
            float x = clamp((l - 0.52f) / 0.48f, 0.0f, 1.0f);
            float k = 1.0f + u.highlightRolloff / 100.0f * 1.8f;
            float rolled = 0.52f + 0.48f * (1.0f - pow(1.0f - x, k));
            enc = clamp(enc * (rolled / max(l, 1e-4f)), 0.0f, 1.0f);
        }
    }

    // ---- Tone curves -------------------------------------------------------
    float3 curved = float3(
        curves.sample(curveSampler, float2(clamp(enc.r, 0.0f, 1.0f), 0.5f)).r,
        curves.sample(curveSampler, float2(clamp(enc.g, 0.0f, 1.0f), 0.5f)).g,
        curves.sample(curveSampler, float2(clamp(enc.b, 0.0f, 1.0f), 0.5f)).b
    );
    float curveLumaIn = dot(curved, LUMA);
    float curveLumaOut = curves.sample(curveSampler, float2(clamp(curveLumaIn, 0.0f, 1.0f), 0.5f)).a;
    curved *= curveLumaOut / max(curveLumaIn, 1e-4f);
    enc = clamp(curved, 0.0f, 1.0f);

    // ---- Colour grading ----------------------------------------------------
    if (u.hueShift != 0.0f || u.colorDensity != 0.0f ||
        u.skinSaturation != 0.0f || u.greenSaturation != 0.0f ||
        u.blueSaturation != 0.0f || u.highlightWarmth != 0.0f ||
        u.shadowCoolness != 0.0f) {
        float3 hsv = rgb_to_hsv(enc);
        hsv.x = fract(hsv.x + u.hueShift * 0.0015f);
        float hueDeg = hsv.x * 360.0f;
        float satMul = 1.0f
            + (u.skinSaturation / 100.0f) * 0.55f * hueWeight(hueDeg, 32.0f, 55.0f)
            + (u.greenSaturation / 100.0f) * 0.75f * hueWeight(hueDeg, 105.0f, 85.0f)
            + (u.blueSaturation / 100.0f) * 0.55f * hueWeight(hueDeg, 225.0f, 60.0f)
            + (u.colorDensity / 100.0f) * 0.35f;
        hsv.y = clamp(hsv.y * satMul, 0.0f, 1.0f);
        enc = hsv_to_rgb(hsv);

        float l = dot(enc, LUMA);
        float hi = smoothstep(0.55f, 0.98f, l);
        float sh = 1.0f - smoothstep(0.06f, 0.40f, l);
        float warm = u.highlightWarmth / 100.0f;
        float cool = u.shadowCoolness / 100.0f;
        enc += float3(0.055f, 0.018f, -0.060f) * warm * hi;
        enc += float3(-0.045f, 0.012f, 0.070f) * cool * sh;
        enc = clamp(enc, 0.0f, 1.0f);
    }

    // ---- Tonal transparency: levels from the histogram edges --------------
    if (u.tonalTransparency > 0.001f) {
        float span = max(u.whitePoint - u.blackPoint, 0.06f);
        float3 leveled = clamp((enc - u.blackPoint) / span, 0.0f, 1.0f);
        enc = mix(enc, leveled, clamp(u.tonalTransparency, 0.0f, 1.0f));
    }

    // ---- Colour transparency: complementary neutralisation ----------------
    if (u.colorTransparency > 0.001f) {
        float l = dot(enc, LUMA);
        float whiteMask = smoothstep(0.52f, 0.96f, l);
        float blackMask = 1.0f - smoothstep(0.06f, 0.34f, l);
        float3 whiteDelta = float3(u.whiteDeltaR, u.whiteDeltaG, u.whiteDeltaB);
        float3 blackDelta = float3(u.blackDeltaR, u.blackDeltaG, u.blackDeltaB);
        enc += whiteDelta * whiteMask * u.colorTransparency;
        enc += blackDelta * blackMask * u.colorTransparency;
        enc = clamp(enc, 0.0f, 1.0f);
    }

    // ---- Print fade -------------------------------------------------------
    if (u.fade > 0.001f) {
        float amount = clamp(u.fade / 100.0f, 0.0f, 1.0f);
        enc = mix(enc, enc * 0.87f + 0.055f, amount);
    }

    // ---- Vignette -----------------------------------------------------------
    // Lightroom-style shaping: amount, midpoint, roundness, feather and a
    // movable optical centre.
    float2 vc = float2(0.5f + u.vignetteCenterX / 100.0f * 0.25f,
                       0.5f + u.vignetteCenterY / 100.0f * 0.25f);
    float2 vp = uv - vc;
    float aspect = u.imageWidth / max(u.imageHeight, 1.0f);
    float roundness = clamp(u.vignetteRoundness / 100.0f, -1.0f, 1.0f);
    float wx = 1.0f + max(roundness, 0.0f) * (aspect - 1.0f);
    float wy = 1.0f + max(-roundness, 0.0f) * 0.6f;
    float r = length(float2(vp.x * wx, vp.y * wy)) / 0.7071f;
    float midpoint = clamp(u.vignetteMidpoint / 100.0f, 0.0f, 1.0f);
    float feather = clamp(u.vignetteFeather / 100.0f, 0.0f, 1.0f);
    float outer = 0.62f + midpoint * 0.63f;
    float inner = max(0.0f, outer - (0.06f + feather * 0.94f));
    float vig = 1.0f + u.vignette / 100.0f * 0.58f * smoothstep(inner, outer, r);
    enc = max(enc * vig, 0.0f);

    // Grain runs as a separate pass (grainHorizontal/grainVertical) so this
    // pass stays free of neighbourhood sampling.

    // ---- Dither -------------------------------------------------------------
    float d = (hash21(float2(gid) + u.ditherSeed) - 0.5f) / 255.0f;
    enc = clamp(enc + d, 0.0f, 1.0f);
    dst.write(float4(enc, 1.0f), outPos);
}

// -----------------------------------------------------------------------------
// Histogram
// -----------------------------------------------------------------------------

kernel void histogram(texture2d<float, access::read> img [[texture(0)]],
                      device atomic_uint *bins [[buffer(0)]],
                      uint2 gid [[thread_position_in_grid]])
{
    uint w = img.get_width();
    uint h = img.get_height();
    if (gid.x >= 256 || gid.y >= 256) return;
    uint sx = min(w - 1, gid.x * w / 256);
    uint sy = min(h - 1, gid.y * h / 256);
    float3 c = img.read(uint2(sx, sy)).rgb;
    uint l = min(255u, uint(round(dot(c, LUMA) * 255.0f)));
    uint r = min(255u, uint(round(c.r * 255.0f)));
    uint g = min(255u, uint(round(c.g * 255.0f)));
    uint b = min(255u, uint(round(c.b * 255.0f)));
    atomic_fetch_add_explicit(&bins[l], 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[256 + r], 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[512 + g], 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[768 + b], 1, memory_order_relaxed);

    const float luma = dot(c, LUMA);
    if (luma > 0.88f) {
        atomic_fetch_add_explicit(&bins[1024], 1, memory_order_relaxed);
        atomic_fetch_add_explicit(&bins[1025], uint(round(c.r * 32767.0f)), memory_order_relaxed);
        atomic_fetch_add_explicit(&bins[1026], uint(round(c.g * 32767.0f)), memory_order_relaxed);
        atomic_fetch_add_explicit(&bins[1027], uint(round(c.b * 32767.0f)), memory_order_relaxed);
    } else if (luma < 0.12f) {
        atomic_fetch_add_explicit(&bins[1028], 1, memory_order_relaxed);
        atomic_fetch_add_explicit(&bins[1029], uint(round(c.r * 32767.0f)), memory_order_relaxed);
        atomic_fetch_add_explicit(&bins[1030], uint(round(c.g * 32767.0f)), memory_order_relaxed);
        atomic_fetch_add_explicit(&bins[1031], uint(round(c.b * 32767.0f)), memory_order_relaxed);
    }
}

// -----------------------------------------------------------------------------
// Display pass
// -----------------------------------------------------------------------------

struct DisplayOut {
    float4 position [[position]];
    float2 uv;
};

vertex DisplayOut displayVertex(uint vid [[vertex_id]])
{
    float2 positions[3] = {float2(-1.0f, -1.0f), float2(3.0f, -1.0f), float2(-1.0f, 3.0f)};
    DisplayOut out;
    out.position = float4(positions[vid], 0.0f, 1.0f);
    out.uv = positions[vid] * 0.5f + 0.5f;
    return out;
}

fragment float4 displayFragment(DisplayOut in [[stage_in]],
                                texture2d<float, access::sample> img [[texture(0)]],
                                texture2d<float, access::sample> original [[texture(1)]],
                                constant DisplayUniforms &d [[buffer(0)]])
{
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 pixel = in.position.xy;
    float2 center = float2(d.viewWidth, d.viewHeight) * 0.5f;
    float2 p = pixel - center - float2(d.panX, d.panY) * d.backingScale;
    float scale = d.fitScale * d.zoom;
    float2 uv = p / (scale * float2(d.imageWidth, d.imageHeight)) + 0.5f;

    if (uv.x < 0.0f || uv.y < 0.0f || uv.x > 1.0f || uv.y > 1.0f) {
        return float4(0.043f, 0.043f, 0.043f, 1.0f);
    }

    // Compare slider: original on the left of the split, developed on the right.
    // The original texture is scene-linear, the developed one is display
    // encoded, so only the original needs the encode.
    float3 developed = img.sample(s, uv).rgb;
    float3 color = developed;
    if (d.compareEnabled > 0.5f && uv.x < d.splitX) {
        color = linear_to_srgb3(original.sample(s, uv).rgb);
    }
    float edge = min(min(uv.x, 1.0f - uv.x), min(uv.y, 1.0f - uv.y));
    float edgePx = max(1.0f, d.backingScale) * 0.5f * scale / max(d.viewWidth, d.viewHeight);
    if (edge < edgePx) {
        color += 0.045f;
    }
    return float4(color, 1.0f);
}
