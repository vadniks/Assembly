// Copyright (C) 2026 Vadim Nikolaev (https://github.com/vadniks)
// SPDX-License-Identifier: GPL-3.0-only
// GM/gm/gm.s/gm.S - Graphics meme challenge

#version 460 core

layout(location = 0) in vec2 iTexCoord;

layout(location = 0) out vec4 oColor;

layout(location = 1) uniform sampler2D uTexture;
layout(location = 2) uniform bool uPostprocessing;
layout(location = 3) uniform vec4 uClip;

vec4 postprocessing() {
    const float offset = 1.0 / 300.0;

    const float kernel[9] = float[](
        0, 1, 0,
        1, -4, 1,
        0, 1, 0
    );

    float sign[3] = float[](-offset, 0, offset);
    vec3 tex[9];
    for (int i = 0, j = 0, k = 0; i < 9; i++) {
        tex[i] = vec3(texture(uTexture, iTexCoord + vec2(sign[j], sign[k])));
        if (++j == 3 && ++k == 3) k = 0;
        if (j == 3) j = 0;
    }

    vec3 color = vec3(0);
    for (int i = 0; i < 9; i++)
        color += tex[i] * kernel[i];

    return vec4(color, 1);
}

void main() {
    const vec4 texColor = uPostprocessing ? postprocessing() : texture(uTexture, iTexCoord);
    float alpha;

    if (uClip == vec4(0)) {
        alpha = smoothstep(0.2, 0.8, texColor.a);
        if (alpha < 0.02) discard;
    } else {
        const vec2 center = uClip.xy;
        const vec2 radii = uClip.zw;
        const vec2 diff = gl_FragCoord.xy - center;

        const float dist = (diff.x * diff.x) / (radii.x * radii.x) +
            (diff.y * diff.y) / (radii.y * radii.y);

        alpha = 1 - smoothstep(0.95, 1, dist);
        if (alpha <= 0) discard;
        alpha *= texColor.a;
    }

    oColor = vec4(texColor.rgb, alpha);
}