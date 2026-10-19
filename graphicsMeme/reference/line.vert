// Copyright (C) 2026 Vadim Nikolaev (https://github.com/vadniks)
// SPDX-License-Identifier: GPL-3.0-only
// GM/gm/gm.s/gm.S - Graphics meme challenge

#version 460 core

layout(std140, binding = 0) uniform Common {
    mat4 projection;
};

layout(location = 0) uniform vec4 uCoords;
layout(location = 1) uniform float uThickness;

void main() {
    const vec3 p0 = vec3(uCoords.xy, 0);
    const vec3 p1 = vec3(uCoords.zw, 0);

    vec3 perpendicular = cross(normalize(p1 - p0), vec3(0, 0, 1));
    perpendicular = normalize(perpendicular) * uThickness / 2;

    const vec3 points[] = vec3[](
        p0 + perpendicular,
        p0 - perpendicular,
        p1 + perpendicular,
        p1 - perpendicular
    );

    const int index = gl_VertexID - ((gl_VertexID < 4) ? 0 : 3);
    gl_Position = projection * vec4(points[index].xy, 0, 1);
}