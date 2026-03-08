#version 460

layout (location = 0) in vec3 a_pos;
layout (location = 1) in vec4 a_color;
layout (location = 2) in vec3 a_tex_coords;
layout (location = 0) out vec4 v_color;
layout (location = 1) out vec3 v_tex_coords;
layout (location = 2) out float v_pos_x;

void main() {
    float x = (a_pos.x / 320.0) * 2.0 - 1.0;
    float y = (a_pos.y / 240.0) * -2.0 + 1.0;
    float z = a_pos.z / 65536.0;

    gl_Position = vec4(x, y, z, 1.0);

    v_color = a_color;
    v_tex_coords = a_tex_coords;
    v_pos_x = a_pos.x;
}