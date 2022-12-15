#version 300 es

precision highp float;

uniform mat4 u_worldInverseTransposeMatrix;
uniform mat4 u_worldInverseMatrix;
uniform sampler2D u_iceTexture;
uniform sampler2D u_iceNormal;
uniform sampler2D u_dirtTexture;
uniform samplerCube u_envMapTexture;
uniform vec3 u_cameraPos;
uniform float u_time;
uniform float u_progress1;
uniform float u_progress2;
uniform float u_progress3;

out vec4 outColor;

in vec3 v_position;
in vec3 v_worldPosition;
in vec2 v_texcoord;
in vec3 v_normal;
in vec3 v_tangent;
in vec3 v_surfaceToView;

#define TWO_PI 6.2831853071795864769252867665590
#define PI 3.1415926535

const vec2 inv_atan = vec2(0.1591, 0.3183);

vec2 dir2equirect(highp vec3 dir) {
    highp vec2 uv = vec2(atan(dir.z, dir.x), asin(dir.y));
    uv *= inv_atan;
    uv += 0.5;
    return uv;
}

vec3 cart2equirect(vec2 uv) {
    float Phi = PI - uv.y * PI;
    float Theta = uv.x * TWO_PI;
    vec3 dir = vec3(cos(Theta), 0.0, sin(Theta));
    dir.y   = cos(Phi);//clamp(cos(Phi), MinCos, 1.0);
    dir.xz *= sqrt(1.0 - dir.y * dir.y);
    return dir;
}

float powFast(float a, float b) {
  return a / ((1. - b) * a + b);
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

float brightnessContrast( float value, float brightness, float contrast ) {
    return ( value - 0.5 ) * contrast + 0.5 + brightness;
}

vec3 brightnessContrast( vec3 color, float brightness, float contrast ) {
    return ( color - 0.5 ) * contrast + 0.5 + brightness;
}

vec4 brightnessContrast( vec4 color, float brightness, float contrast ) {
    return vec4(brightnessContrast(color.rgb, brightness, contrast), color.a);
}

vec2 parallaxOffset(float ratio, vec3 V) {
    vec3 pOff = V * ratio;
    vec3 pDir = (u_worldInverseMatrix * vec4(normalize(v_worldPosition + pOff), 0.)).xyz;
    return fract(dir2equirect(pDir));
}

// https://github.com/glslify/glsl-specular-blinn-phong
float specularBlinnPhong(vec3 L, vec3 N, vec3 V, float shininess) {
    // halfVector
    vec3 H = normalize(L + V);
    return powFast(max(0.0, dot(N, H)), shininess);
}

void main() {
    vec3 P = normalize(v_position);
    vec3 V = normalize(v_surfaceToView);

    // get equirect coords
    vec2 equirect = dir2equirect(P);

    // create the parallax texture
    vec4 iceLayer1 = texture(u_iceTexture, equirect);
    vec4 iceLayer2 = texture(u_iceTexture, parallaxOffset(-0.2, V));
    float parallax = 0.;
    for (int j = 0; j <15; j ++) {
        float ratio = float(j) / 15.;
        float value = texture(u_iceTexture, parallaxOffset(ratio * -0.2, V)).r * (1. - smoothstep(0.5, 1.0, ratio));
        parallax = blendScreen(parallax, value / 10.);
    }
    float iceValue = parallax * 2. + iceLayer1.r + iceLayer2.b * 0.5;
    vec3 gradColor1 = vec3(1.);
    vec3 gradColor2 = vec3(0.4, 0.8, 1.);
    vec3 gradColor3 = vec3(0.0, 0.05, .1);
    vec3 iceColor = mix(gradColor2, gradColor1, iceValue);
    iceColor = mix(gradColor3, iceColor, iceValue * 0.3 + 0.1);
    iceColor = mix(iceColor, water(iceValue), min(iceValue, 0.3));
    iceColor += vec3(smoothstep(0.1, 1., iceLayer1.r) * 0.9);
    iceColor = mix(water(length(vec3(0., 0., 1.) - v_normal) * 0.01) * 0.4, iceColor, u_progress3);
    iceColor += vec3(smoothstep(0.1, 1., iceLayer1.g) * 0.3) * u_progress2;

    // get the normal offsets
    vec3 normalOffset = texture(u_iceNormal, equirect).xyz * 2. - 1.;
    vec3 dirt = texture(u_dirtTexture, equirect).xyz;
    vec3 dirt2 = texture(u_dirtTexture, vec2(equirect.x, 1. - equirect.y)).xyz;

    vec3 N = normalize(v_normal);
    vec3 T = normalize(v_tangent);
    vec3 L = normalize(vec3(1., 2., 2.));
    vec3 B = normalize(cross(N, T));
    vec3 R = reflect(N, -L);
    mat3 tangentSpace = mat3(T, B, N);
    N = normalize(mix(N, tangentSpace * normalOffset, .8 * u_progress3));

    // basic lighting
    float specularValue = specularBlinnPhong(L, N, V, mix(400., 300., u_progress2));
    vec3 specular = specularValue * vec3(1., .9, .8) * (.7 - u_progress2 * 0.2);
    float diffuse = max(0., dot(N, L)) * 0.1;
    float fresnelValue = 1. - dot(N, V);
    fresnelValue = fresnelValue * fresnelValue * fresnelValue;
    float fresnel = fresnelValue * .2;

    // env reflection
    vec4 env = texture(u_envMapTexture, N) * fresnelValue * ((1. - u_progress2) * 0.8 + 0.2);


    outColor = vec4(iceColor + specular + diffuse + fresnel + env.rgb, 0.);
    outColor = brightnessContrast(outColor, .1, 2.);

}