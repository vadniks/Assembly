// Copyright (C) 2026 Vadim Nikolaev (https://github.com/vadniks)
// SPDX-License-Identifier: GPL-3.0-only
// GM/gm/gm.s/gm.S - Graphics meme challenge

#version 460 core

layout(location = 0) out vec4 oColor;

layout(location = 2) uniform vec4 uColor;

void main() {
    oColor = uColor;
}