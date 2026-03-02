#version 460

const uint CT_ONE_CYCLE = 0;
const uint CT_TWO_CYCLE = 1;
const uint CT_COPY = 2;
const uint CT_FILL = 3;

layout (std140, set = 3, binding = 0) uniform UniformBlock {
    vec4 fill_color;
    uint cycle_type;
};

layout (location = 0) in vec4 v_color;
layout (location = 0) out vec4 f_color;

void main() {
    if (cycle_type == CT_FILL) {
        f_color = fill_color;
        return;
    }

    f_color = v_color;
}