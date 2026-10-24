// Copyright (C) 2026 Vadim Nikolaev (https://github.com/vadniks)
// SPDX-License-Identifier: GPL-3.0-only
// GM/gm/gm.s/gm.S - Graphics meme challenge

#version 460 core

layout(location = 0) in vec4 iVertex;
layout(location = 0) out vec2 oTexCoord;

layout(std140, binding = 0) uniform Common {
    mat4 projection;
};

layout(location = 0) uniform mat4 uModel;

void main() {
    gl_Position = projection * uModel * vec4(iVertex.xy, 0, 1);
    oTexCoord = iVertex.zw;
}