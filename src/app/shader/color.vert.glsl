#version 300 es

uniform mat4 u_worldMatrix;
uniform mat4 u_worldInverseTransposeMatrix;
uniform mat4 u_viewMatrix;
uniform mat4 u_projectionMatrix;
uniform float u_time;
uniform sampler2D u_iceTexture;
uniform sampler2D u_iceNormal;
uniform vec3 u_cameraPos;

in vec3 a_position;
in vec3 a_normal;
in vec2 a_texcoord;
in vec3 a_tangent;

out vec3 v_position;
out vec3 v_worldPosition;
out vec2 v_texcoord;
out vec3 v_normal;
out vec3 v_tangent;
out vec3 v_surfaceToView;

const vec2 inv_atan = vec2(0.1591, 0.3183);

vec2 dir2equirect(highp vec3 dir) {
  highp vec2 uv = vec2(atan(dir.z, dir.x), asin(dir.y));
  uv *= inv_atan;
  uv += 0.5;
  return uv;
}

vec3 distort(vec3 pos) {
  vec2 st = dir2equirect(pos);
  vec4 map = texture(u_iceTexture, st);

  float h = map.a;
  float offset = 1. + (h * 0.05 - 0.025);

  return pos * offset;
}

void main() {
  vec3 pos = distort(a_position);
  vec2 equirect = dir2equirect(a_position);
  
  vec4 worldPosition = u_worldMatrix * vec4(pos, 1.);
  gl_Position = u_projectionMatrix * u_viewMatrix * worldPosition;

  v_position = a_position;
  v_texcoord = a_texcoord;
  v_worldPosition = worldPosition.xyz;
  v_surfaceToView = u_cameraPos - worldPosition.xyz;
  vec4 tangent = u_worldInverseTransposeMatrix * vec4(a_tangent, 0.);
  v_tangent = tangent.xyz;
  v_normal = (u_worldInverseTransposeMatrix * vec4(a_normal, 0.)).xyz;
}