#version 300 es

uniform mat4 u_worldMatrix;
uniform mat4 u_worldInverseTransposeMatrix;
uniform mat4 u_viewMatrix;
uniform mat4 u_projectionMatrix;
uniform float u_time;
uniform sampler2D u_iceTexture;
uniform sampler2D u_iceNormal;
uniform vec3 u_cameraPos;
uniform float u_wobbleStrength;
uniform float u_scale;
uniform float u_progress1;
uniform float u_progress2;
uniform float u_progress3;

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

void main() {
  vec3 pos = a_position;
  vec2 st = dir2equirect(pos);
  vec4 map = texture(u_iceTexture, st);
  float h = (map.a - 0.2) * .1;
  float displacement = u_scale + h  * u_progress3;
  float wobble = cos(u_time * 0.0015 + pos.y * 4.) * 0.04 + sin(u_time * 0.0025 + pos.x * 4.) * 0.04 + 1.;
  float dX = cos(4. * pos.x + u_time * 0.0025) * 0.08;
  float dY = -sin(4. * pos.y + u_time * 0.0015) * 0.08;
  float dZ = 0.;
  vec3 wN = normalize(vec3(dX, dY, dZ) + normalize(pos));

  pos *= mix(displacement, wobble, u_wobbleStrength);
  vec3 N = mix(a_normal, wN, u_wobbleStrength);
  
  vec4 worldPosition = u_worldMatrix * vec4(pos, 1.);
  gl_Position = u_projectionMatrix * u_viewMatrix * worldPosition;

  v_position = a_position;
  v_texcoord = a_texcoord;
  v_worldPosition = worldPosition.xyz;
  v_surfaceToView = u_cameraPos - worldPosition.xyz;
  v_tangent = (u_worldInverseTransposeMatrix * vec4(a_tangent, 0.)).xyz;
  v_normal = (u_worldInverseTransposeMatrix * vec4(N, 0.)).xyz;
}