#version 300 es

precision highp float;

uniform float u_time;

out vec4 outColor;

in vec3 v_position;
in vec3 v_normal;

float powFast(float a, float b) {
  return a / ((1. - b) * a + b);
}

void main() {
	vec3 L = vec3(0., 0., 1.);
	vec3 N = normalize(v_normal);
	float diffuse = max(0., dot(L, N));
	outColor = vec4(powFast(diffuse, 90.));
    outColor.a *= max(0., v_position.z) * (1. - u_time) * 0.5;
}