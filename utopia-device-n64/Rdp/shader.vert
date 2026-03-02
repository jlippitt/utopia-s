#version 460

// layout (location = 0) in vec3 a_pos;
// layout (location = 1) in vec4 a_color;
// layout (location = 0) out vec4 v_color;

vec2 positions[3] = vec2[](
    vec2(0.0, 0.5),
    vec2(0.5, -0.5),
    vec2(-0.5, -0.5)
);

void main() {
    gl_Position = vec4(positions[gl_VertexIndex], 0.0, 1.0);
    // v_color = a_color;
}