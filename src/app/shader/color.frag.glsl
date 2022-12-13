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

void main() {
    vec3 P = normalize(v_position);
    vec3 V = normalize(u_cameraPos - v_worldPosition);

    // get equirect coords
    vec2 equirect = dir2equirect(P);

    vec4 ice = texture(u_iceTexture, equirect);
    vec3 normalOffset = texture(u_iceNormal, equirect).xyz * 2. - 1.;
    normalOffset = (vec4(normalOffset, 0.)).xyz;

    vec3 N = normalize(v_normal);
    vec3 T = normalize(v_tangent);
    vec3 L = normalize(-vec3(-100., -100., 10.));

    // perturb normal
    vec3 B = normalize(cross(N, T));
    mat3 tangentSpace = mat3(T, B, N);
    N = normalize(mix(N, tangentSpace * normalOffset, 1.));

    vec3 R = reflect(N, L);
    float specularValue = powFast(max(0.0, dot(R, V)), 100.);
    vec3 specular = specularValue * vec3(1., 1., 1.);

    float diffuse = max(0., dot(N, L)) * 0.5;

    outColor = vec4(ice.rgb, 0.);
    outColor = vec4(specular * 0.8 + diffuse + vec3(0.05, 0.05, 0.07) + ice.r, 0.);
}