#version 460

layout (location = 0) in vec3 a_pos;
layout (location = 1) in vec4 a_color;
layout (location = 0) out vec4 v_color;

void main() {
    float x = (a_pos.x / 320.0) * 2.0 - 1.0;
    float y = (a_pos.y / 240.0) * -2.0 + 1.0;
    gl_Position = vec4(x, y, a_pos.z, 1.0);
    v_color = a_color;
}