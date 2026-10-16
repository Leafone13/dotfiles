#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec4 low;
  vec4 high;
};
layout(binding = 1) uniform sampler2D source;
// Gradient map: icon luminance -> low..high, alpha kept.
void main() {
  vec4 p = texture(source, qt_TexCoord0);
  vec3 c = p.a > 0.0 ? p.rgb / p.a : vec3(0.0);
  float l = dot(c, vec3(0.299, 0.587, 0.114));
  fragColor = vec4(mix(low.rgb, high.rgb, l) * p.a, p.a) * qt_Opacity;
}
