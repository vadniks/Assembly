// Copyright (C) 2026 Vadim Nikolaev (https://github.com/vadniks)
// SPDX-License-Identifier: GPL-3.0-only

// License: GNU GPLv3 only - this code is not intended for production - only for demonstration/learning purposes.
// GM/gm/gm.s/gm.S - Graphics meme challenge:
//     OpenGL (4.6 Core) 2D graphics prototype for demonstrating certain computer graphics concepts and their implementations,
//     mathematics, as well as dynamic libraries usage in position independent executables on GNU/Linux x86_64 platforms in
//     GNU Assembly(er), and x64 Linux assembly (low-level) development/programming techniques, manually rewritten from the C
//     source. This program is basically a tiny image manipulation program with all the necessary features to create meme-like
//     images via code - the lowest level possible! The features include: render of various sized textures of different images,
//     text render, arbitrary lines (size, color, position, width, slope, opacity), texture clipping, antializing, postprocessing
//     effects, result saving to file with image container encoding.
// Dependencies: GLibC, LibM, SDL3, SDL3_Image, SDL3_TTF, CGLM, GL
// Version: dated October 2026
// Inspired by the book "Learn OpenGL - Graphics Programming" by Joey de Vries, big thanks to him, it's a great book!

// mkdir build && (cd build; cmake -G Ninja .. && cd .. && cmake --build build -j 18)
// cmake --build build -j 18

// vulkan-tools glslang for glsl to spirv compilation
// glslangValidator -G texquad.vert -o texquad.vert.spv
// glslangValidator -G texquad.frag -o texquad.frag.spv
// glslangValidator -G line.vert -o line.vert.spv
// glslangValidator -G line.frag -o line.frag.spv

// Glew isn't needed in assembly and thus it's not used there at all

#include <SDL3/SDL.h>
#include <SDL3_image/SDL_image.h>
#include <SDL3_ttf/SDL_ttf.h>
#include <GL/glew.h>
#include <cglm/call.h>
#include <stdio.h>

#define nullable _Nullable

typedef unsigned char byte;

typedef enum : int {TYPE_TEXQUAD, TYPE_LINE} Type;

typedef struct {
    Type type;
    GLuint vao, program;
} Object;

typedef struct {
    Object;
    GLuint x, y;
    GLuint w, h, vbo, ebo, texture;
    bool clip;
} Texquad;

typedef struct {
    Object;
    GLuint x0, y0, x1, y1, width;
} Line;

typedef struct {
    GLuint id, texture;
} Fbo;

static constexpr unsigned WIDTH = 640, HEIGHT = 640, UPDATE_PERIOD = 16, OBJECTS = 3;

static const char* const FONT = "font.ttf", * const OUTPUT_IMAGE = "gmout.png";

/*
 * #version 460 core
 *
 * layout(location = 0) in vec4 iVertex;
 * layout(location = 0) out vec2 oTexCoord;
 *
 * layout(std140, binding = 0) uniform Common {
 *    mat4 projection;
 * };
 *
 * layout(location = 0) uniform mat4 uModel;
 *
 * void main() {
 *    gl_Position = projection * uModel * vec4(iVertex.xy, 0, 1);
 *    oTexCoord = iVertex.zw;
 * }
 */
static const byte TEXQUAD_VERTEX_SHADER[] = {
    #embed "texquad.vert.spv"
};
/*
 * #version 460 core
 *
 * layout(location = 0) in vec2 iTexCoord;
 *
 * layout(location = 0) out vec4 oColor;
 *
 * layout(location = 1) uniform sampler2D uTexture;
 * layout(location = 2) uniform bool uPostprocessing;
 * layout(location = 3) uniform vec4 uClip;
 *
 * vec4 postprocessing() {
 *    const float offset = 1.0 / 300.0;
 *
 *    const float kernel[9] = float[](
 *        0, 1, 0,
 *        1, -4, 1,
 *        0, 1, 0
 *    );
 *
 *    float sign[3] = float[](-offset, 0, offset);
 *    vec3 tex[9];
 *    for (int i = 0, j = 0, k = 0; i < 9; i++) {
 *        tex[i] = vec3(texture(uTexture, iTexCoord + vec2(sign[j], sign[k])));
 *        if (++j == 3 && ++k == 3) k = 0;
 *        if (j == 3) j = 0;
 *    }
 *
 *    vec3 color = vec3(0);
 *    for (int i = 0; i < 9; i++)
 *        color += tex[i] * kernel[i];
 *
 *    return vec4(color, 1);
 * }
 *
 * void main() {
 *    const vec4 texColor = uPostprocessing ? postprocessing() : texture(uTexture, iTexCoord);
 *    float alpha;
 *
 *    if (uClip == vec4(0)) {
 *        alpha = smoothstep(0.2, 0.8, texColor.a);
 *        if (alpha < 0.02) discard;
 *    } else {
 *        const vec2 center = uClip.xy;
 *        const vec2 radii = uClip.zw;
 *        const vec2 diff = gl_FragCoord.xy - center;
 *
 *        const float dist = (diff.x * diff.x) / (radii.x * radii.x) +
 *            (diff.y * diff.y) / (radii.y * radii.y);
 *
 *        alpha = 1 - smoothstep(0.95, 1, dist);
 *        if (alpha <= 0) discard;
 *        alpha *= texColor.a;
 *    }
 *
 *    oColor = vec4(texColor.rgb, alpha);
 * }
 */
static const byte TEXQUAD_FRAGMENT_SHADER[] = {
    #embed "texquad.frag.spv"
};

/*
 * #version 460 core
 *
 * layout(std140, binding = 0) uniform Common {
 *    mat4 projection;
 * };
 *
 * layout(location = 0) uniform vec4 uCoords;
 * layout(location = 1) uniform float uThickness;
 *
 * void main() {
 *    const vec3 p0 = vec3(uCoords.xy, 0);
 *    const vec3 p1 = vec3(uCoords.zw, 0);
 *
 *    vec3 perpendicular = cross(normalize(p1 - p0), vec3(0, 0, 1));
 *    perpendicular = normalize(perpendicular) * uThickness / 2;
 *
 *    const vec3 points[] = vec3[](
 *        p0 + perpendicular,
 *        p0 - perpendicular,
 *        p1 + perpendicular,
 *        p1 - perpendicular
 *    );
 *
 *    const int index = gl_VertexID - ((gl_VertexID < 4) ? 0 : 3);
 *    gl_Position = projection * vec4(points[index].xy, 0, 1);
 * }
 */
static const byte LINE_VERTEX_SHADER[] = {
    #embed "line.vert.spv"
};
/*
 * #version 460 core
 *
 * layout(location = 0) out vec4 oColor;
 *
 * layout(location = 2) uniform vec4 uColor;
 *
 * void main() {
 *    oColor = uColor;
 * }
 */
static const byte LINE_FRAGMENT_SHADER[] = {
    #embed "line.frag.spv"
};

static TTF_Font* gFont = nullptr;
static GLfloat gMaxAnisotropy = 0.f;
static GLuint gUbo = 0;
static Fbo gMsaaFbo = {0}, gPostprocessingFbo = {0};
static Texquad gPostprocessingTexquad = {0};
static Object* gObjects[OBJECTS] = {nullptr};

#undef assert
static inline void assert(const bool condition) {
    if (!condition) abort();
}

static void captureCanvas(void) {
    byte buffer[WIDTH * HEIGHT * 4] = {0};
    glReadPixels(0, 0, WIDTH, HEIGHT, GL_RGBA, GL_UNSIGNED_BYTE, buffer);

    SDL_Surface* const surface = SDL_CreateSurfaceFrom(WIDTH, HEIGHT, SDL_PIXELFORMAT_RGBA32, (void*) buffer, 4 * WIDTH);
    assert(surface);
    assert(SDL_FlipSurface(surface, SDL_FLIP_VERTICAL));

    assert(IMG_SavePNG(surface, OUTPUT_IMAGE));
    SDL_DestroySurface(surface);
}

static void bootstrapQuad(
    GLuint* const restrict vao,
    GLuint* const restrict vbo,
    GLuint* const restrict ebo,
    const unsigned verticesSize,
    const GLfloat vertices[const restrict verticesSize]
) {
    glCreateVertexArrays(1, vao);
    assert(*vao);

    glCreateBuffers(1, vbo);
    assert(*vbo);
    glNamedBufferStorage(*vbo, verticesSize, vertices, 0);

    const GLuint indices[] = {0, 1, 3, 1, 2, 3};
    glCreateBuffers(1, ebo);
    assert(*ebo);
    glNamedBufferStorage(*ebo, sizeof(indices), indices, 0);
    glVertexArrayElementBuffer(*vao, *ebo);
}

static GLuint makeShaders(
    const unsigned vertexSize,
    const byte vertex[const restrict vertexSize],
    const unsigned fragmentSize,
    const byte fragment[const restrict fragmentSize]
) {
    GLuint vertexShader = 0, fragmentShader = 0, program = 0;
    int success = 0;

    assert(vertexShader = glCreateShader(GL_VERTEX_SHADER));
    glShaderBinary(1, &vertexShader, GL_SHADER_BINARY_FORMAT_SPIR_V, vertex, vertexSize);
    glSpecializeShader(vertexShader, "main", 0, nullptr, nullptr);
    glGetShaderiv(vertexShader, GL_COMPILE_STATUS, &success);
    assert(success);

    assert(fragmentShader = glCreateShader(GL_FRAGMENT_SHADER));
    glShaderBinary(1, &fragmentShader, GL_SHADER_BINARY_FORMAT_SPIR_V, fragment, fragmentSize);
    glSpecializeShader(fragmentShader, "main", 0, nullptr, nullptr);
    glGetShaderiv(fragmentShader, GL_COMPILE_STATUS, &success);
    assert(success);

    assert(program = glCreateProgram());
    glAttachShader(program, vertexShader);
    glAttachShader(program, fragmentShader);
    glLinkProgram(program);
    glGetProgramiv(program, GL_LINK_STATUS, &success);
    assert(success);

    glValidateProgram(program);
    glGetProgramiv(program, GL_VALIDATE_STATUS, &success);
    assert(success);

    glDetachShader(program, fragmentShader);
    glDeleteShader(fragmentShader);

    glDetachShader(program, vertexShader);
    glDeleteShader(vertexShader);

    return program;
}

static void createTexquad(Texquad* const restrict texquad, SDL_Surface* const restrict nullable surface, const mat4 model) {
    if (surface) {
        glCreateTextures(GL_TEXTURE_2D, 1, &texquad->texture);
        assert(texquad->texture);
        glTextureParameteri(texquad->texture, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTextureParameteri(texquad->texture, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTextureParameteri(texquad->texture, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
        glTextureParameteri(texquad->texture, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTextureParameterf(texquad->texture, GL_TEXTURE_MAX_ANISOTROPY_EXT, gMaxAnisotropy);
        glTextureStorage2D(texquad->texture, 1, GL_RGBA8, surface->w, surface->h);
        glTextureSubImage2D(texquad->texture, 0, 0, 0, surface->w, surface->h, GL_RGBA, GL_UNSIGNED_BYTE, surface->pixels);
        glGenerateTextureMipmap(texquad->texture);

        SDL_DestroySurface(surface);
    }

    const GLfloat
    x = (float) texquad->x,
    y = (float) texquad->y,
    w = (float) texquad->w,
    h = (float) texquad->h;

    const GLfloat vertices[] = {
        x + w, y + h, 1.f, 1.f,
        x + w, y,     1.f, 0.f,
        x,     y,     0.f, 0.f,
        x,     y + h, 0.f, 1.f
    };
    bootstrapQuad(&texquad->vao, &texquad->vbo, &texquad->ebo, sizeof(vertices), vertices);
    glVertexArrayVertexBuffer(texquad->vao, 0, texquad->vbo, 0, 4 * sizeof(float));

    glVertexArrayAttribFormat(texquad->vao, 0, 4, GL_FLOAT, GL_FALSE, 0);
    glVertexArrayAttribBinding(texquad->vao, 0, 0);
    glEnableVertexArrayAttrib(texquad->vao, 0);

    texquad->program = makeShaders(sizeof(TEXQUAD_VERTEX_SHADER), TEXQUAD_VERTEX_SHADER, sizeof(TEXQUAD_FRAGMENT_SHADER), TEXQUAD_FRAGMENT_SHADER);

    const float wHalf = w / 2.f;
    const float hHalf = h / 2.f;
    glProgramUniform4fv(
        texquad->program,
        3, // uClip
        1,
        !texquad->clip ? (vec4) {0.f} : (vec4) {x + wHalf, y + hHalf, wHalf, hHalf}
    );

    glProgramUniformMatrix4fv(texquad->program, 0 /*uModel*/, 1, GL_FALSE, (void*) model);
}

static SDL_Surface* createTexture(const char* const imgPathOrText, const bool imageOrText) {
    SDL_Surface* const temp = imageOrText
    ? IMG_Load(imgPathOrText)
    : TTF_RenderText_Blended(gFont, imgPathOrText, 0, (SDL_Color) {127, 127, 127, 255}); // TODO: extract color to a constant
    assert(temp);

    SDL_Surface* const surface = SDL_ConvertSurface(temp, SDL_PIXELFORMAT_RGBA32);
    assert(surface);
    SDL_DestroySurface(temp);

    assert(SDL_FlipSurface(surface, SDL_FLIP_VERTICAL));
    return surface;
}

static void renderTexquad(const Texquad* const texquad) {
    glUseProgram(texquad->program);
    glBindTexture(GL_TEXTURE_2D, texquad->texture);
    glBindVertexArray(texquad->vao);

    glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, nullptr);

    glBindVertexArray(0);
    glBindTexture(GL_TEXTURE_2D, 0);
    glUseProgram(0);
}

static void removeTexquad(Texquad* const texquad) {
    glDeleteTextures(1, &texquad->texture);
    glDeleteProgram(texquad->program);
    glDeleteBuffers(2, (GLuint[]) {texquad->ebo, texquad->vao});
    glDeleteVertexArrays(1, &texquad->vao);
}

static void createLine(Line* const line) {
    glGenVertexArrays(1, &line->vao);
    assert(line->vao);

    line->program = makeShaders(sizeof(LINE_VERTEX_SHADER), LINE_VERTEX_SHADER, sizeof(LINE_FRAGMENT_SHADER), LINE_FRAGMENT_SHADER);

    glProgramUniform4fv(line->program, 0 /*uCoords*/, 1, (vec4) {(float) line->x0, (float) line->y0, (float) line->x1, (float) line->y1});
    glProgramUniform1f(line->program, 1 /*uThickness*/, (float) line->width);
    glProgramUniform4fv(line->program, 2 /*uColor*/, 1, (vec4) {0.f, 1.f, 0.f, 1.f});
}

static void renderLine(const Line* const line) {
    glUseProgram(line->program);
    glBindVertexArray(line->vao);
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glBindVertexArray(0);
    glUseProgram(0);
}

static void removeLine(Line* const line) {
    glDeleteVertexArrays(1, &line->vao);
    glDeleteProgram(line->program);
}

static void processObject(Object* const object, const bool renderOrDelete) {
    switch (object->type) {
        case TYPE_TEXQUAD:
            auto* const texquad = (Texquad*) object;
            renderOrDelete ? renderTexquad(texquad) : removeTexquad(texquad);
            break;
        case TYPE_LINE:
            auto* const line = (Line*) object;
            renderOrDelete ? renderLine(line) : removeLine(line);
            break;
    }
    if (!renderOrDelete) free(object);
}

static void render(void) {
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, gMsaaFbo.id);

    glClearColor(1.f, 1.f, 1.f, 1.f);
    glClear(GL_COLOR_BUFFER_BIT);

    for (unsigned i = 0; i < OBJECTS; i++)
        processObject(gObjects[i], true);

    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
    glBlitNamedFramebuffer(gMsaaFbo.id, gPostprocessingFbo.id, 0, 0, WIDTH, HEIGHT, 0, 0, WIDTH, HEIGHT, GL_COLOR_BUFFER_BIT, GL_NEAREST);
    renderTexquad(&gPostprocessingTexquad);
}

static void createUbo(void) {
    mat4 projection;
    glmc_ortho(0.f, (float) WIDTH, 0.f, (float) HEIGHT, 0.f, 1.f, projection);

    glCreateBuffers(1, &gUbo);
    assert(gUbo);
    glNamedBufferStorage(gUbo, sizeof(mat4), projection, 0);
    glBindBufferBase(GL_UNIFORM_BUFFER, 0, gUbo);
}

static void createFbos(void) {
    {
        glCreateTextures(GL_TEXTURE_2D_MULTISAMPLE, 1, &gMsaaFbo.texture);
        assert(gMsaaFbo.texture);
        glTextureStorage2DMultisample(gMsaaFbo.texture, 4, GL_RGBA8, WIDTH, HEIGHT, GL_TRUE);

        glCreateFramebuffers(1, &gMsaaFbo.id);
        assert(gMsaaFbo.id);
        glNamedFramebufferTexture(gMsaaFbo.id, GL_COLOR_ATTACHMENT0, gMsaaFbo.texture, 0);
        assert(glCheckNamedFramebufferStatus(gMsaaFbo.id, GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);
    } {
        glCreateTextures(GL_TEXTURE_2D, 1, &gPostprocessingFbo.texture);
        assert(gPostprocessingFbo.texture);
        glTextureParameteri(gPostprocessingFbo.texture, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTextureParameteri(gPostprocessingFbo.texture, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTextureParameterf(gPostprocessingFbo.texture, GL_TEXTURE_MAX_ANISOTROPY_EXT, gMaxAnisotropy);
        glTextureStorage2D(gPostprocessingFbo.texture, 1, GL_RGBA8, WIDTH, HEIGHT);

        glCreateFramebuffers(1, &gPostprocessingFbo.id);
        assert(gPostprocessingFbo.id);
        glNamedFramebufferTexture(gPostprocessingFbo.id, GL_COLOR_ATTACHMENT0, gPostprocessingFbo.texture, 0);
        assert(glCheckNamedFramebufferStatus(gPostprocessingFbo.id, GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);
    }
}

static void removeFbos(void) {
    glDeleteTextures(2, (GLuint[]) {gMsaaFbo.texture, gPostprocessingFbo.texture});
    glDeleteFramebuffers(2, (GLuint[]) {gMsaaFbo.id, gPostprocessingFbo.id});
}

static inline void togglePostprocessing(const bool onOrOff) {
    glProgramUniform1i(gPostprocessingTexquad.program, 2 /*uPostprocessing*/, onOrOff);
}

static void createObjects(void) {
    createUbo();
    createFbos();

    mat4 model;
    glmc_mat4_identity(model);

    gPostprocessingTexquad = (Texquad) {.type = TYPE_TEXQUAD, .x = 0, .y = 0, .w = WIDTH, .h = HEIGHT};
    createTexquad(&gPostprocessingTexquad, nullptr, model);
    gPostprocessingTexquad.texture = gPostprocessingFbo.texture;

    SDL_Surface* surface = createTexture("Hello World!", false);
    assert(gObjects[0] = malloc(sizeof(Texquad)));
    *(Texquad*) gObjects[0] = (Texquad) {.type = TYPE_TEXQUAD, .x = 210, .y = 310, .w = 420, .h = 320};
    // glmc_rotate_at(model, (vec3) {310.f + 320.f / 2.f, 310.f + 320.f / 2.f, 0.f}, M_PIf, (vec3) {0, 0, 1});
    createTexquad((Texquad*) gObjects[0], surface, model);
    glm_mat4_identity(model);

    surface = createTexture("img.png", true);
    assert(gObjects[1] = malloc(sizeof(Texquad)));
    *(Texquad*) gObjects[1] = (Texquad) {.type = TYPE_TEXQUAD, .x = 50, .y = 50, .clip = true, .w = 320, .h = 320};
    createTexquad((Texquad*) gObjects[1], surface, model);

    assert(gObjects[2] = malloc(sizeof(Line)));
    *(Line*) gObjects[2] = (Line) {.type = TYPE_LINE, .x0 = 500, 100, 600, 100, 10};
    createLine((Line*) gObjects[2]);
}

static void removeObjects(void) {
    for (unsigned i = 0; i < OBJECTS; i++)
        processObject(gObjects[i], false);

    removeTexquad(&gPostprocessingTexquad);
    removeFbos();
    glDeleteBuffers(1, &gUbo);
}

static void loop(SDL_Window* const window) {
    createObjects();

    SDL_Event event;
    unsigned long ticks;
    unsigned elapsed;

    bool postprocessingEnabled = false;
    while (true) {
        ticks = SDL_GetTicks();

        glClearColor(1.f, 1.f, 1.f, 1.f);
        glClear(GL_COLOR_BUFFER_BIT);
        render();

        assert(SDL_GL_SwapWindow(window));

        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT) goto end;
            if (event.type == SDL_EVENT_KEY_DOWN) {
                switch (event.key.key) {
                    case SDLK_Q: goto end;
                    case SDLK_GRAVE: togglePostprocessing((postprocessingEnabled = !postprocessingEnabled)); break;
                }
            }
        }

        elapsed = (unsigned) (SDL_GetTicks() - ticks);
        if (elapsed < UPDATE_PERIOD)
            SDL_Delay(UPDATE_PERIOD - elapsed);
    }
    end:

    captureCanvas();
    removeObjects();
}

void debugCallback(
    const GLenum,
    const GLenum,
    const GLuint,
    const GLenum,
    const GLsizei,
    const GLchar* const restrict message,
    const void* const restrict
) {
    printf("|%s|\n", message);
}

int main(void) {
    assert(SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "wayland,x11"));
    assert(SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS));

    assert(TTF_Init());
    assert(gFont = TTF_OpenFont(FONT, 1.f));
    assert(TTF_SetFontSizeDPI(gFont, 120, 100, 100));

    assert(SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 4));
    assert(SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 6));
    assert(SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE));
    assert(SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 1));
    assert(SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 4));
    assert(SDL_GL_SetAttribute(SDL_GL_ACCELERATED_VISUAL, 1));
    assert(SDL_GL_SetAttribute(SDL_GL_CONTEXT_FLAGS, SDL_GL_CONTEXT_DEBUG_FLAG));

    SDL_Window* const window = SDL_CreateWindow("", WIDTH, HEIGHT, SDL_WINDOW_OPENGL);
    assert(window);

    const SDL_GLContext glContext = SDL_GL_CreateContext(window);
    assert(glContext);

    glewExperimental = GL_TRUE;
    const unsigned glewInitRes = glewInit();
    assert(glewInitRes == GLEW_OK || glewInitRes == GLEW_ERROR_NO_GLX_DISPLAY); // ignore no_glx on wayland

    glViewport(0, 0, WIDTH, HEIGHT);

    glEnable(GL_DEBUG_OUTPUT);
    glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);
    glDebugMessageCallback(debugCallback, nullptr);

    glEnable(GL_MULTISAMPLE);
    glEnable(GL_SAMPLE_ALPHA_TO_COVERAGE);

    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    assert(SDL_GL_SetSwapInterval(1));

    glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, &gMaxAnisotropy);

    loop(window);

    assert(SDL_GL_DestroyContext(glContext));
    SDL_DestroyWindow(window);

    TTF_CloseFont(gFont);
    TTF_Quit();

    SDL_Quit();
    return 0;
}
