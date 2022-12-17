#version 300 es

precision highp float;

uniform float u_time;

out vec4 outColor;

in vec3 v_position;

float rand(vec2 n) { 
	return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}

float noise(vec2 p){
	vec2 ip = floor(p);
	vec2 u = fract(p);
	u = u*u*(3.0-2.0*u);
	
	float res = mix(
		mix(rand(ip),rand(ip+vec2(1.0,0.0)),u.x),
		mix(rand(ip+vec2(0.0,1.0)),rand(ip+vec2(1.0,1.0)),u.x),u.y);
	return res*res;
}

void main() {
    vec2 uv = vec2(gl_PointCoord.x, 1. - gl_PointCoord.y);
    vec2 st = uv * 2. - 1.;
    float mask = 1. - smoothstep(0.9, 1., length(st));
    outColor = vec4(1., 1., 1., 0.);
    outColor.a = mask * max(0., v_position.z) * (1. - u_time) * noise(v_position.xy * 50.);
}