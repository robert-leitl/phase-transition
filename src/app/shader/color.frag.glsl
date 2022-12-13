#version 300 es

precision highp float;

uniform mat4 u_worldInverseTransposeMatrix;
uniform sampler2D u_iceTexture;
uniform sampler2D u_iceNormal;
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

void main() {
    vec3 P = normalize(v_position);
    vec3 V = normalize(v_surfaceToView);

    // get equirect coords
    vec2 equirect = dir2equirect(P);

    // get the normal offsets
    vec3 normalOffset = texture(u_iceNormal, equirect).xyz * 2. - 1.;
    normalOffset = (vec4(normalOffset, 0.)).xyz;

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
    iceColor = mix(gradColor3, iceColor, iceValue * 0.8 + 0.1);
    iceColor = mix(iceColor, water(iceValue), 0.25);
    iceColor += vec3(smoothstep(0.2, 1., iceLayer1.r) * 0.1);

    // basic lighting
    vec3 R = reflect(N, L);
    float specularValue = powFast(max(0.0, dot(R, V)), 180.);
    vec3 specular = specularValue * vec3(1., .9, .8) * 0.5;
    float diffuse = max(0., dot(N, L)) * 0.2;
    float fresnel = 1. - dot(N, V);
    fresnel *= fresnel * fresnel;
    fresnel *= .4;

    outColor = vec4(iceColor + specular + diffuse + fresnel, 0.);
}