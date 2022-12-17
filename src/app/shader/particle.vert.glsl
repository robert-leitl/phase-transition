#version 300 es

uniform mat4 u_worldMatrix;
uniform mat4 u_viewMatrix;
uniform mat4 u_projectionMatrix;
uniform float u_time;

in vec3 a_position;

out vec3 v_position;

float rand(vec2 n) { 
	return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}

void main() {
  float t = u_time * rand(vec2(float(gl_VertexID)) * 100.);
  vec3 pos = a_position * (1. + t * 0.2);
  vec4 worldPosition = u_worldMatrix * vec4(pos, 1.);
  gl_Position = u_projectionMatrix * u_viewMatrix * worldPosition;
  gl_PointSize = 3.;
  v_position = worldPosition.xyz;
}