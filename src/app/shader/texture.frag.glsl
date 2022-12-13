#version 300 es

precision highp float;

layout(location = 0) out vec4 outTexture;
layout(location = 1) out vec4 outNormal;

in vec2 v_texcoord;

#define PI 3.1415926535897932384626433832795
#define TWO_PI 6.2831853071795864769252867665590

#include 'voronoi-3d.glsl'

vec3 cart2equirect(vec2 uv) {
    float Phi = PI - uv.y * PI;
    float Theta = uv.x * TWO_PI;
    vec3 dir = vec3(cos(Theta), 0.0, sin(Theta));
    dir.y   = cos(Phi);//clamp(cos(Phi), MinCos, 1.0);
    dir.xz *= sqrt(1.0 - dir.y * dir.y);
    return dir;
}

const vec2 inv_atan = vec2(0.1591, 0.3183);

vec2 dir2equirect(highp vec3 dir) {
  highp vec2 uv = vec2(atan(dir.z, dir.x), asin(dir.y));
  uv *= inv_atan;
  uv += 0.5;
  return uv;
}

float random(in float x) {
  return fract(sin(x) * 43758.5453);
}

mat2 rotate2d(in float radians){
    float c = cos(radians);
    float s = sin(radians);
    return mat2(c, -s, s, c);
}

vec2 rotate(in vec2 st, in float radians, in vec2 center) {
    return rotate2d(radians) * (st - center) + center;
}

float sphericalDistance(vec3 pi, vec3 pj) {
    return (acos(dot(pj, pi)));
}

vec4 mod289(in vec4 x) {
  return x - floor(x * (1. / 289.)) * 289.;
}

vec3 mod289(in vec3 x) {
  return x - floor(x * (1. / 289.)) * 289.;
}

vec4 permute(in vec4 x) {
     return mod289(((x * 34.) + 1.)*x);
}

vec4 taylorInvSqrt(in vec4 r) {
  return 1.79284291400159 - 0.85373472095314 * r;
}

float snoise(in vec3 v) {
    const vec2  C = vec2(1.0/6.0, 1.0/3.0) ;
    const vec4  D = vec4(0.0, 0.5, 1.0, 2.0);

    // First corner
    vec3 i  = floor(v + dot(v, C.yyy) );
    vec3 x0 =   v - i + dot(i, C.xxx) ;

    // Other corners
    vec3 g = step(x0.yzx, x0.xyz);
    vec3 l = 1.0 - g;
    vec3 i1 = min( g.xyz, l.zxy );
    vec3 i2 = max( g.xyz, l.zxy );

    //   x0 = x0 - 0.0 + 0.0 * C.xxx;
    //   x1 = x0 - i1  + 1.0 * C.xxx;
    //   x2 = x0 - i2  + 2.0 * C.xxx;
    //   x3 = x0 - 1.0 + 3.0 * C.xxx;
    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + C.yyy; // 2.0*C.x = 1/3 = C.y
    vec3 x3 = x0 - D.yyy;      // -1.0+3.0*C.x = -0.5 = -D.y

    // Permutations
    i = mod289(i);
    vec4 p = permute( permute( permute(
                i.z + vec4(0.0, i1.z, i2.z, 1.0 ))
            + i.y + vec4(0.0, i1.y, i2.y, 1.0 ))
            + i.x + vec4(0.0, i1.x, i2.x, 1.0 ));

    // Gradients: 7x7 points over a square, mapped onto an octahedron.
    // The ring size 17*17 = 289 is close to a multiple of 49 (49*6 = 294)
    float n_ = 0.142857142857; // 1.0/7.0
    vec3  ns = n_ * D.wyz - D.xzx;

    vec4 j = p - 49.0 * floor(p * ns.z * ns.z);  //  mod(p,7*7)

    vec4 x_ = floor(j * ns.z);
    vec4 y_ = floor(j - 7.0 * x_ );    // mod(j,N)

    vec4 x = x_ *ns.x + ns.yyyy;
    vec4 y = y_ *ns.x + ns.yyyy;
    vec4 h = 1.0 - abs(x) - abs(y);

    vec4 b0 = vec4( x.xy, y.xy );
    vec4 b1 = vec4( x.zw, y.zw );

    //vec4 s0 = vec4(lessThan(b0,0.0))*2.0 - 1.0;
    //vec4 s1 = vec4(lessThan(b1,0.0))*2.0 - 1.0;
    vec4 s0 = floor(b0)*2.0 + 1.0;
    vec4 s1 = floor(b1)*2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));

    vec4 a0 = b0.xzyw + s0.xzyw*sh.xxyy ;
    vec4 a1 = b1.xzyw + s1.xzyw*sh.zzww ;

    vec3 p0 = vec3(a0.xy,h.x);
    vec3 p1 = vec3(a0.zw,h.y);
    vec3 p2 = vec3(a1.xy,h.z);
    vec3 p3 = vec3(a1.zw,h.w);

    //Normalise gradients
    vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2, p2), dot(p3,p3)));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;

    // Mix final noise value
    vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
    m = m * m;
    return 42.0 * dot( m*m, vec4( dot(p0,x0), dot(p1,x1),
                                dot(p2,x2), dot(p3,x3) ) );
}

float fbm(in vec3 pos) {
    // Initial values
    float value = 0.0;
    float amplitud = 0.5;

    // Loop of octaves
    for (int i = 0; i < 5; i++) {
        value += amplitud * snoise(pos);
        pos *= 2.;
        amplitud *= .5;
    }
    return value;
}

// creates a vector which is orthogonal to the given vector
vec3 orthogonal(vec3 v) {
    return normalize(abs(v.x) > abs(v.z) ? 
    vec3(-v.y, v.x, 0.0) : 
    vec3(0.0, -v.z, v.y));
}

void main() {
    vec2 st = v_texcoord;
    vec3 dir = normalize(cart2equirect(st));

    float n1 = fbm(dir);

    vec3[2] voronoi1 = voronoi3d(dir * 2.6 * (1. - n1 * 0.12));
    vec3[2] voronoi2 = voronoi3d(dir * 1.5 * (1. - n1 * 0.3));
    vec3[2] voronoi3 = voronoi3d(dir * 3.0 * (1. - n1 * 0.4));
    vec3 v1 = voronoi1[0];
    vec3 v2 = voronoi2[0];
    vec3 v3 = voronoi3[0];
    vec3 c = normalize(voronoi1[1]);

    // generate the displacement value
    float sp = sphericalDistance(dir, c);
    float disp = v1.r * 0.5 + sp * sp;
    disp = v1.r + (disp * 2. - 1.) * 0.5;

    // generate the ice textures
    float ice1 = pow(v1.r, 3.);
    float ice2 = pow(v2.r, 4.);
    float ice3 = pow(v3.r, 5.);
    float dirt = fbm(dir * 1000.);
    ice1 -= dirt * 0.05;
    ice2 -= dirt * 0.075;
    ice3 -= dirt * 0.1;

    // generate normal map from the center point normal
    vec3 N = dir;
    vec3 T = normalize(cart2equirect(st + vec2(0.01, 0.)) - N);
    vec3 B = (cross(T, N));
    T = normalize(cross(N, B));
    mat3 inversTangentSpace = inverse(mat3(T, B, N));
    vec3 normal = normalize(c + dir * smoothstep(0.3, 0.8, sp + dirt * 0.1 + n1 ));
    vec3 normalOffset = inversTangentSpace * normal;

    outTexture = vec4(ice1, ice2, ice3, disp);
    outNormal = vec4(normalOffset * 0.5 + 0.5, 0);
}