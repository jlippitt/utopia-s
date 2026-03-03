#version 460

const uint CI_COMBINED_RGB = 0;
const uint CI_TEXEL0_RGB = 1;
const uint CI_TEXEL1_RGB = 2;
const uint CI_PRIM_RGB = 3;
const uint CI_SHADE_RGB = 4;
const uint CI_ENV_RGB = 5;
const uint CI_KEY_CENTER = 6;
const uint CI_KEY_SCALE = 7;
const uint CI_COMBINED_ALPHA = 8;
const uint CI_TEXEL0_ALPHA = 9;
const uint CI_TEXEL1_ALPHA = 10;
const uint CI_PRIM_ALPHA = 11;
const uint CI_SHADE_ALPHA = 12;
const uint CI_ENV_ALPHA = 13;
const uint CI_LOD_FRACTION = 14;
const uint CI_PRIM_LOD_FRACTION = 15;
const uint CI_NOISE = 16;
const uint CI_CONVERT_K4 = 17;
const uint CI_CONVERT_K5 = 18;
const uint CI_CONSTANT_1 = 19;
const uint CI_CONSTANT_0 = 20;

const uint BI_PIXEL_RGB = 0;
const uint BI_MEMORY_RGB = 1;
const uint BI_BLEND_RGB = 2;
const uint BI_FOG_RGB = 3;

const uint BFA_COMBINED_ALPHA = 0;
const uint BFA_FOG_ALPHA = 1;
const uint BFA_SHADE_ALPHA = 2;
const uint BFA_CONSTANT_0 = 3;

const uint BFB_ONE_MINUS_A = 0;
const uint BFB_MEMORY_ALPHA = 1;
const uint BFB_CONSTANT_1 = 2;
const uint BFB_CONSTANT_0 = 3;

const uint CT_ONE_CYCLE = 0;
const uint CT_TWO_CYCLE = 1;
const uint CT_COPY = 2;
const uint CT_FILL = 3;

struct CombineEquation {
    uint sub_a;
    uint sub_b;
    uint mul;
    uint add;
};

struct CombineMode {
    CombineEquation rgb;
    CombineEquation a;
};

struct BlendMode {
    uint p;
    uint a;
    uint m;
    uint b;
};

layout (std140, set = 3, binding = 0) uniform UniformBlock {
    CombineMode combine_0;
    CombineMode combine_1;
    BlendMode blend_0;
    BlendMode blend_1;
    vec4 fill_color;
    vec4 fog_color;
    vec4 blend_color;
    vec4 prim_color;
    vec4 env_color;
    uint cycle_type;
};

layout (location = 0) in vec4 v_color;
layout (location = 0) out vec4 f_color;

vec3 blendInput(uint input_type, vec3 pixel_rgb) {
    switch (input_type) {
        case BI_PIXEL_RGB: return pixel_rgb;
        case BI_MEMORY_RGB: return vec3(0.0); // TODO
        case BI_BLEND_RGB: return blend_color.rgb;
        case BI_FOG_RGB: return fog_color.rgb;
        default: return vec3(0.0);
    }
}

float blendFactorA(uint input_type, float combined_a) {
    switch (input_type) {
        case BFA_COMBINED_ALPHA: return combined_a;
        case BFA_FOG_ALPHA: return fog_color.a;
        case BFA_SHADE_ALPHA: return v_color.a;
        case BFA_CONSTANT_0: return 0.0;
        default: return 0.0;
    }
}

float blendFactorB(uint input_type, float factor_a) {
    switch (input_type) {
        case BFB_ONE_MINUS_A: return 1.0 - factor_a;
        case BFB_MEMORY_ALPHA: return 0.0; // TODO
        case BFB_CONSTANT_1: return 1.0;
        case BFB_CONSTANT_0: return 0.0;
        default: return 0.0;
    }
}

vec4 blend(BlendMode blend, float combined_a, vec3 pixel_rgb) {
    vec3 p = blendInput(blend.p, pixel_rgb);
    float a = blendFactorA(blend.a, combined_a);

    // TODO: Non-standard memory blending modes
    if (blend.p != BI_MEMORY_RGB && blend.m == BI_MEMORY_RGB) {
        return vec4(p, a);
    }

    vec3 m = blendInput(blend.m, pixel_rgb);
    float b = blendFactorB(blend.b, a);

    return vec4(p * a + m * b, 1.0);
}

vec3 combineRgbInput(uint input_type, vec4 tex0, vec4 combined) {
    switch (input_type) {
        case CI_COMBINED_RGB: return combined.rgb;
        case CI_TEXEL0_RGB: return tex0.rgb;
        case CI_TEXEL1_RGB: return vec3(1.0); // TODO
        case CI_PRIM_RGB: return prim_color.rgb;
        case CI_SHADE_RGB: return v_color.rgb;
        case CI_ENV_RGB: return env_color.rgb;
        case CI_KEY_CENTER: return vec3(1.0); // TODO
        case CI_KEY_SCALE: return vec3(1.0); // TODO
        case CI_COMBINED_ALPHA: return vec3(combined.a);
        case CI_TEXEL0_ALPHA: return vec3(tex0.a);
        case CI_TEXEL1_ALPHA: return vec3(1.0); // TODO
        case CI_PRIM_ALPHA: return vec3(prim_color.a);
        case CI_SHADE_ALPHA: return vec3(v_color.a);
        case CI_ENV_ALPHA: return vec3(env_color.a);
        case CI_LOD_FRACTION: return vec3(1.0); // TODO
        case CI_PRIM_LOD_FRACTION: return vec3(1.0); // TODO
        case CI_NOISE: return vec3(1.0); // TODO
        case CI_CONVERT_K4: return vec3(1.0); // TODO
        case CI_CONVERT_K5: return vec3(1.0); // TODO
        case CI_CONSTANT_1: return vec3(1.0);
        case CI_CONSTANT_0: return vec3(0.0);
        default: return vec3(0.0);
    }
}

float combineAlphaInput(uint input_type, float tex0_a, float combined_a) {
    switch (input_type) {
        case CI_COMBINED_ALPHA: return combined_a;
        case CI_TEXEL0_ALPHA: return tex0_a;
        case CI_TEXEL1_ALPHA: return 1.0; // TODO
        case CI_PRIM_ALPHA: return prim_color.a;
        case CI_SHADE_ALPHA: return v_color.a;
        case CI_ENV_ALPHA: return env_color.a;
        case CI_LOD_FRACTION: return 1.0; // TODO
        case CI_PRIM_LOD_FRACTION: return 1.0; // TODO
        case CI_CONSTANT_1: return 1.0;
        case CI_CONSTANT_0: return 0.0;
        default: return 0.0;
    }
}

vec3 combineRgb(CombineEquation combine, vec4 tex0, vec4 combined) {
    vec3 sub_a = combineRgbInput(combine.sub_a, tex0, combined);
    vec3 sub_b = combineRgbInput(combine.sub_b, tex0, combined);
    vec3 mul = combineRgbInput(combine.mul, tex0, combined);
    vec3 add = combineRgbInput(combine.add, tex0, combined);
    return (sub_a - sub_b) * mul + add;
}

float combineAlpha(CombineEquation combine, float tex0_a, float combined_a) {
    float sub_a = combineAlphaInput(combine.sub_a, tex0_a, combined_a);
    float sub_b = combineAlphaInput(combine.sub_b, tex0_a, combined_a);
    float mul = combineAlphaInput(combine.mul, tex0_a, combined_a);
    float add = combineAlphaInput(combine.add, tex0_a, combined_a);
    return (sub_a - sub_b) * mul + add;
}

vec4 combine(CombineMode combine, vec4 tex0, vec4 combined) {
    return vec4(
        combineRgb(combine.rgb, tex0, combined),
        combineAlpha(combine.a, tex0.a, combined.a)
    );
}

void main() {
    if (cycle_type == CT_FILL) {
        f_color = fill_color;
        return;
    }

    vec4 tex0 = vec4(0.0, 0.0, 0.0, 1.0);

    if (cycle_type == CT_COPY) {
        f_color = tex0;
        return;
    }

    f_color = vec4(0.0);

    if (cycle_type == CT_TWO_CYCLE) {
        f_color = combine(combine_0, tex0, f_color);
    }

    f_color = combine(combine_1, tex0, f_color);

    float combined_a = f_color.a;

    f_color = blend(blend_0, combined_a, f_color.rgb);

    if (cycle_type == CT_TWO_CYCLE) {
        f_color = blend(blend_1, combined_a, f_color.rgb);
    }
}
