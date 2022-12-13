#version 300 es

precision highp float;

uniform mat4 u_worldInverseTransposeMatrix;
uniform sampler2D u_iceTexture;
uniform sampler2D u_iceNormal;
uniform sampler2D u_dirtTexture;
uniform vec3 u_cameraPos;
uniform float u_time;

out vec4 outColor;

in vec3 v_position;
in vec3 v_worldPosition;
in vec2 v_texcoord;
in vec3 v_normal;
in vec3 v_tangent;
in vec3 v_surfaceToView;

#define PI 3.1415926535

const vec2 inv_atan = vec2(0.1591, 0.3183);

vec2 dir2equirect(highp vec3 dir) {
    highp vec2 uv = vec2(atan(dir.z, dir.x), asin(dir.y));
    uv *= inv_atan;
    uv += 0.5;
    return uv;
}

float powFast(float a, float b) {
  return a / ((1. - b) * a + b);
}

vec2 parallaxOffset(float ratio, vec3 tangentSpaceViewDir) {
  float h = ratio - ratio * 0.5;
  return h * (tangentSpaceViewDir.xy / max(0.2, tangentSpaceViewDir.z));
}

float blendMultiply(float src, float dest, float opacity) {
    float blend = src * dest;
    float ret = mix(src, blend, opacity);
    return ret;
}

float blendScreen(in float base, in float blend) {
    return 1. - ((1. - base) * (1. - blend));
}

float blendOverlay(in float base, in float blend) {
    return (base < .5)? (2.*base*blend): (1. - 2. * (1. - base) * (1. - blend));
}

float blendLighten(in float base, in float blend) {
    return max(blend, base);
}

float saturate( float x){ return clamp(x, 0.0, 1.0); }

vec3 water(float x) {
    return pow(vec3(.1, .7, .8), vec3(4.* saturate(1.0-x) ));
}

vec3 tonemapUncharted2(vec3 color) {
    float A = 0.15; // 0.22
    float B = 0.50; // 0.30
    float C = 0.10;
    float D = 0.20;
    float E = 0.02; // 0.01
    float F = 0.30;
    float W = 11.2;
    
    vec4 x = vec4(color, W);
    x = ((x*(A*x+C*B)+D*E)/(x*(A*x+B)+D*F))-E/F;
    return x.xyz / x.w;
}

vec4 tonemapUncharted2(const vec4 x) { return vec4( tonemapUncharted2(x.rgb), x.a); }

vec3 tonemapUnreal(const vec3 x) { return x / (x + 0.155) * 1.019; }
vec4 tonemapUnreal(const vec4 x) { return vec4(tonemapUnreal(x.rgb), x.a); }

vec3 tonemapFilmic(vec3 color) {
    color = max(vec3(0.0), color - 0.004);
    color = (color * (6.2 * color + 0.5)) / (color * (6.2 * color + 1.7) + 0.06);
    return color;
}

vec4 tonemapFilmic(const vec4 x) { return vec4( tonemapFilmic(x.rgb), x.a ); }

float brightnessContrast( float value, float brightness, float contrast ) {
    return ( value - 0.5 ) * contrast + 0.5 + brightness;
}

vec3 brightnessContrast( vec3 color, float brightness, float contrast ) {
    return ( color - 0.5 ) * contrast + 0.5 + brightness;
}

vec4 brightnessContrast( vec4 color, float brightness, float contrast ) {
    return vec4(brightnessContrast(color.rgb, brightness, contrast), color.a);
}

void main() {
    vec3 P = normalize(v_position);
    vec3 V = normalize(v_surfaceToView);

    // get equirect coords
    vec2 equirect = dir2equirect(P);

    // get the normal offsets
    vec3 normalOffset = texture(u_iceNormal, equirect).xyz * 2. - 1.;
    vec3 dirt = texture(u_dirtTexture, equirect).xyz;
    vec3 dirt2 = texture(u_dirtTexture, vec2(equirect.x, 1. - equirect.y)).xyz;

    vec3 N = normalize(v_normal);
    vec3 T = normalize(v_tangent);
    vec3 L = normalize(-vec3(-150., -150., 10.));

    // perturb normal
    vec3 B = normalize(cross(N, T));
    mat3 tangentSpace = mat3(T, B, N);
    N = normalize(mix(N, tangentSpace * normalOffset, .5));
    tangentSpace = mat3(T, B, N);

    // parallax
    vec3 tV = vec3(
        dot(V, -T),
        dot(V, B),
        dot(V, N)
    );
    vec4 iceLayer1 = texture(u_iceTexture, equirect);
    float parallax = 0.;
    vec2 puv;
    for (int j = 0; j < 15; j ++) {
        float ratio = float(j) / 15.;
        puv = fract(equirect + parallaxOffset(-0.25 * ratio, tV) * (1. - smoothstep(0.9, 1., ratio)));
        float value = texture(u_iceTexture, puv).r;
        parallax = blendScreen(parallax, value / 15.);
    }

    float iceLayer2 = texture(u_iceTexture, fract(equirect + parallaxOffset(-0.05, tV))).g;
    float iceLayer3 = texture(u_iceTexture, fract(equirect + parallaxOffset(-0.08, tV))).b;
    float iceValue = blendLighten(iceLayer3 * 0.3 + iceLayer2 * 0.3 + iceLayer1.r * .8, parallax * 1.7);
    vec3 gradColor1 = vec3(1.);
    vec3 gradColor2 = vec3(0.4, 0.8, 1.);
    vec3 gradColor3 = vec3(0.0, 0.05, .1);
    float t = smoothstep(0., 1., iceValue);
    vec3 iceColor = mix(gradColor2, gradColor1, iceValue);
    iceColor = mix(gradColor3, iceColor, iceValue * 0.3 + 0.1);
    iceColor = mix(iceColor, water(iceValue), min(iceValue, 0.3));
    iceColor += vec3(smoothstep(0.2, 1., iceLayer1.r) * 0.1);
    iceColor += dirt * 0.3 + dirt2 * 0.1;

    // basic lighting
    vec3 R = reflect(N, L);
    float specularValue = powFast(max(0.0, dot(R, V)), 180.);
    vec3 specular = specularValue * vec3(1., .9, .8) * 0.5 * dirt.r;
    float diffuse = max(0., dot(N, L)) * 0.1;
    float fresnel = 1. - dot(N, V);
    fresnel *= fresnel * fresnel;
    fresnel *= .2;


    normalOffset = texture(u_iceNormal, fract(equirect + parallaxOffset(-0.08, tV))).xyz * 2. - 1.;
    N = normalize(mix(normalize(v_normal), tangentSpace * normalOffset, 0.3));
    R = reflect(N, L);
    specularValue = powFast(max(0.0, dot(R, V)), 100.);
    vec3 specularInner = specularValue * vec3(1., .9, .8) * 0.2 + dirt2 * 0.1;

    outColor = vec4(iceColor + specularInner + specular + diffuse + fresnel, 0.);
    outColor = brightnessContrast(outColor, .1, 2.);
}