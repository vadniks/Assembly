// Copyright (C) 2026 Vadim Nikolaev (https://github.com/vadniks)
// SPDX-License-Identifier: GPL-3.0-only

// THE FILE/PROJECT IS STILL IN DEVELOPMENT (IS BEING PORTED FROM C CODE)

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
// Version: dated July 2026
// Inspired by the book "Learn OpenGL - Graphics Programming" by Joey de Vries, big thanks to him, it's a great book!

// --> current: gcc -s -pie -fpie -fomit-frame-pointer -fno-plt -Wl,-z,relro,-z,now -lSDL3 -lSDL3_ttf -lSDL3_image -lGL libcglm.so.0 -Wl,-rpath,. gm.s -o gm
// vulkan-tools glslang for glsl to spirv compilation
// glslangValidator -G texquad.vert -o texquad.vert.spv
// glslangValidator -G texquad.frag -o texquad.frag.spv
// glslangValidator -G line.vert -o line.vert.spv
// glslangValidator -G line.frag -o line.frag.spv

# TODO: optimize for cmovcc (conditional move), etc

/////////////////////////////////////////////////////////////////////////////////
.section .rodata

WIDTH = 640
HEIGHT = 640
UPDATE_PERIOD = 16
OBJECTS = 3

# little endian
DEBUG_S = 0x0a7325 # // %s\n
DEBUG_P = 0x0a7025 # // %p\n
DEBUG_D = 0x0a6425 # // %d\n
DEBUG_F = 0x0a6625 # // %f\n
DEBUG_A = 0x0a61 # // a\n
DEBUG_B = 0x0a62 # // b\n
TEST_STR = 0x0a54534554 # // TEST\n

.macro constant n # // name
    .align 16
    .local \n
    .type \n, @object
.endm

constant SDL_HINT_VIDEO_DRIVER
SDL_HINT_VIDEO_DRIVER: .asciz "SDL_VIDEO_DRIVER"

constant VIDEO_DRIVERS
VIDEO_DRIVERS: .asciz "wayland,x11"

constant EMPTY_STR
EMPTY_STR: .zero 1

constant FONT
FONT: .asciz "font.ttf"

constant OUTPUT_IMAGE
OUTPUT_IMAGE: .asciz "gmout2.png"

constant BOOTSTRAP_QUAD_INDICES
BOOTSTRAP_QUAD_INDICES: .long 0, 1, 3, 1, 2, 3
BOOTSTRAP_QUAD_INDICES_SIZE = (. - BOOTSTRAP_QUAD_INDICES)

constant UNIFORM_CLIP
UNIFORM_CLIP: .asciz "uClip"

constant UNIFORM_MODEL
UNIFORM_MODEL: .asciz "uModel"

constant ENTRY_POINT
ENTRY_POINT: .asciz "main"

constant TEST_STR
TEST_STR: .asciz "TEST"

constant IMAGE_NAME
IMAGE_NAME: .asciz "img.png"

constant TEXQUAD_VERTEX
TEXQUAD_VERTEX: .incbin "texquad.vert.spv"
TEXQUAD_VERTEX_SIZE = (. - TEXQUAD_VERTEX)

constant TEXQUAD_FRAGMENT
TEXQUAD_FRAGMENT: .incbin "texquad.frag.spv"
TEXQUAD_FRAGMENT_SIZE = (. - TEXQUAD_FRAGMENT)

constant LINE_VERTEX
LINE_VERTEX: .incbin "line.vert.spv"
LINE_VERTEX_SIZE = (. - LINE_VERTEX)

constant LINE_FRAGMENT
LINE_FRAGMENT: .incbin "line.frag.spv"
LINE_FRAGMENT_SIZE = (. - LINE_FRAGMENT)

constant FLOATS
FLOATS: .float 1.0, 2.0

/////////////////////////////////////////////////////////////////////////////////
.section .bss

.macro variable n, s # // name, size
    .local \n
    .type \n, @object
    .comm \n, \s, 16
.endm

variable gFont 8 # // void*
variable gMaxAnisotropy 4 # // float

# structs are also 16-bytes aligned

# typedef enum : int {TYPE_TEXQUAD, TYPE_LINE} Type; // size = 4

# typedef struct {
#     Type type;
#     GLuint vao, program;
#     <int padding>;
# } Object; // size = 4 * 3 + 4 padding = 16
variable gObjects 48 # // <Object*>; 16 * 3

OBJECT_SIZE = 16
OBJECT_TYPE_OFFSET = 0
OBJECT_VAO_OFFSET = 4
OBJECT_PROGRAM_OFFSET = 8

# typedef struct {
#     Object; // ms-anon-structure-tag = copies the whole structure
#     GLfloat x, y;
#     GLuint w, h, vbo, ebo, texture;
#     bool clip;
# } Texquad; // size = 16 + 8 * 4 = 48

TEXQUAD_SIZE = 48
TEXQUAD_X_OFFSET = 16
TEXQUAD_Y_OFFSET = 20
TEXQUAD_W_OFFSET = 24
TEXQUAD_H_OFFSET = 28
TEXQUAD_VBO_OFFSET = 32
TEXQUAD_EBO_OFFSET = 36
TEXQUAD_TEXTURE_OFFSET = 40
TEXQUAD_CLIP_OFFSET = 44

# typedef struct {
#     Object; // ms-anon-structure-tag = copies the whole structure
#     GLfloat x0, y0, x1, y1, width;
#     <long padding>;
#     <int padding>;
# } Line; // size = 16 + 5 * 4 + 12 padding = 48

LINE_SIZE = 48
LINE_X0_OFFSET = 16
LINE_Y0_OFFSET = 20
LINE_X1_OFFSET = 24
LINE_Y1_OFFSET = 28
LINE_WIDTH_OFFSET = 32

variable gUbo 4 # // uint

# typedef struct {
#     GLuint id, texture;
#     <long padding>;
# } Fbo; // size = 2 * 4 + 8 padding = 16

FBO_SIZE = 16
FBO_ID_OFFSET = 0
FBO_TEXTURE_OFFSET = 4

variable gMsaaFbo FBO_SIZE # // Fbo
variable gPostprocessingFbo FBO_SIZE # // Fbo
variable gPostprocessingTexquad TEXQUAD_SIZE # // Texquad

/////////////////////////////////////////////////////////////////////////////////
.section .text

.macro callxt n # call extern
    call *\n@gotpcrel(%rip)
.endm

.macro xprint f, r, x # // formatString registerInWhichTheValueIs(8 bytes) xmmRegistersUsedCount; pushes/pops 8 bytes; caller sets %xmms
    pushq $\f
    movq %rsp, %rdi
    movq %\r, %rsi
    movb $\x, %al
    callxt printf
    popq %rax
.endm

.macro debug s, c # // string (in a form of bytes in a number (8 bytes long max)), count; example: debug 0x0a61 2 // "a\n"
    pushq $\s
    movl $1, %eax
    movl $1, %edi
    movq %rsp, %rsi
    movl $\c, %edx
    syscall
    popq %rax
.endm

.macro function n # // name
    .align 16
    .type n, @function
.endm

// every function's start address is 16-bytes aligned
// malloc/calloc/realloc returns 16-bytes aligned addresses

// int3 - breakpoint

.macro assert # checks eax as the first argument for optimization's sake
    testl %eax, %eax
    jnz 1f
    ud2
1:
    nop
.endm

function captureCanvas
captureCanvas:
    endbr64

    CAPTURE_CANVAS_STACK = 16 + WIDTH * HEIGHT * 4 + 8 # // 0(): stack alignment, pointer to the buffer - 7th argument and later (all in one) - SDL_Surface*, 8() padding for buffer, 16() buffer, ...() padding
    subq $CAPTURE_CANVAS_STACK, %rsp

    //

    xorl %edi, %edi
    xorl %esi, %esi
    movl $WIDTH, %edx
    movl $HEIGHT, %ecx
    movl $0x1908, %r8d # GL_RGBA
    movl $0x1401, %r9d # GL_UNSIGNED_BYTE
    leaq 16(%rsp), %rax # &buffer{}
    movq %rax, (%rsp) # buffer addr, must be on the stack as 7th arg
    callxt glReadPixels

    movl $WIDTH, %edi
    movl $HEIGHT, %esi
    movl $0x16762004, %edx # SDL_PIXELFORMAT_RGBA32
    leaq 16(%rsp), %rcx # &buffer{}
    leal WIDTH(%edi, %edi, 2), %r8d # // WIDTH + (WIDTH + WIDTH * 2) = WIDTH=edi * 4
    callxt SDL_CreateSurfaceFrom
    movq %rax, (%rsp) # SDL_Surface* surface
    assert

    movq (%rsp), %rdi # SDL_Surface* surface
    movl $2, %esi # SDL_FLIP_VERTICAL
    callxt SDL_FlipSurface
    assert

    //

    movq (%rsp), %rdi # SDL_Surface* surface
    leaq OUTPUT_IMAGE(%rip), %rsi
    callxt IMG_SavePNG
    assert

    movq (%rsp), %rdi # SDL_Surface* surface
    callxt SDL_DestroySurface

    addq $CAPTURE_CANVAS_STACK, %rsp
    ret

function bootstrapQuad
bootstrapQuad: # uint* vao, uint* vbo, uint* ebo, uint verticesSize, const float[] vertices
    endbr64

    BOOTSTRAP_QUAD_STACK = 40
    subq $BOOTSTRAP_QUAD_STACK, %rsp # 3 * 8 int* + 4 int + 8 float* + 4 padding for stack alignment

    movq %rdi, (%rsp)
    movq %rsi, 8(%rsp)
    movq %rdx, 16(%rsp)
    movl %ecx, 24(%rsp)
    movq %r8, 28(%rsp)

    //
    
    movl $1, %edi
    movq (%rsp), %rsi # uint* vao
    callxt glCreateVertexArrays
    movq (%rsp), %rax # uint* vao
    movl (%rax), %eax # vao
    assert

    //

    movl $1, %edi
    movq 8(%rsp), %rsi # uint* vbo
    callxt glCreateBuffers
    movq 8(%rsp), %rax # uint* vbo
    movl (%rax), %eax # vbo
    assert

    movq 8(%rsp), %rdi # uint* vbo
    movl (%rdi), %edi # vbo
    movl 24(%rsp), %esi # uint verticesSize
    movq 28(%rsp), %rdx # void* vertices
    xorl %ecx, %ecx
    callxt glNamedBufferStorage

    //

    movl $1, %edi
    movq 16(%rsp), %rsi # uint* ebo
    callxt glCreateBuffers
    movq 16(%rsp), %rax # uint* ebo
    movl (%rax), %eax # ebo
    assert

    movq 16(%rsp), %rdi # uint* ebo
    movl (%rdi), %edi # ebo
    movl $BOOTSTRAP_QUAD_INDICES_SIZE, %esi
    leaq BOOTSTRAP_QUAD_INDICES(%rip), %rdx
    xorl %ecx, %ecx
    callxt glNamedBufferStorage

    movq (%rsp), %rdi # uint* vao
    movl (%rdi), %edi # vao
    movq 16(%rsp), %rsi # uint* ebo
    movl (%rsi), %esi # ebo
    callxt glVertexArrayElementBuffer

    //
    
    addq $BOOTSTRAP_QUAD_STACK, %rsp
    ret

function makeShaders
makeShaders: # returns uint program; int vertexSize, char* vertex, int fragmentSize, char* fragment
    endbr64

    MAKE_SHADERS_STACK = 40
    subq $MAKE_SHADERS_STACK, %rsp # 2 * 4 int + 2 * 8 char* + 4 * 4 int + zero padding for stack alignment
    # 0() vertexSize, 4() vertex, 12() fragmentSize, 16() fragment, 24() vertexShader, 28() fragmentShader, 32() program, 36() success

    movl %edi, (%rsp)
    movq %rsi, 4(%rsp)
    movl %edx, 12(%rsp)
    movq %rcx, 16(%rsp)
    movl $0, 24(%rsp)
    movl $0, 28(%rsp)
    movl $0, 32(%rsp)
    movl $0, 36(%rsp)

    //

    movl $0x8b31, %edi # GL_VERTEX_SHADER
    callxt glCreateShader
    movl %eax, 24(%rsp) # vertexShader
    assert

    movl $1, %edi
    leaq 24(%rsp), %rsi # &vertexShader
    movl $0x9551, %edx # GL_SHADER_BINARY_FORMAT_SPIR_V
    movq 4(%rsp), %rcx # vertex
    movl (%rsp), %r8d # vertexSize
    callxt glShaderBinary

    movl 24(%rsp), %edi # vertexShader
    leaq ENTRY_POINT(%rip), %rsi
    xorl %edx, %edx
    xorq %rcx, %rcx
    xorq %r8, %r8
    callxt glSpecializeShader

    movl 24(%rsp), %edi # vertexShader
    movl $0x8b81, %esi # GL_COMPILE_STATUS
    leaq 36(%rsp), %rdx # &success
    callxt glGetShaderiv
    movl 36(%rsp), %eax # success
    assert

    //

    movl $0x8b30, %edi # GL_FRAGMENT_SHADER
    callxt glCreateShader
    movl %eax, 28(%rsp) # fragmentShader
    assert

    movl $1, %edi
    leaq 28(%rsp), %rsi # &fragmentShader
    movl $0x9551, %edx # GL_SHADER_BINARY_FORMAT_SPIR_V
    movq 16(%rsp), %rcx # fragment
    movl 12(%rsp), %r8d # fragmentSize
    callxt glShaderBinary

    movl 28(%rsp), %edi # fragmentShader
    leaq ENTRY_POINT(%rip), %rsi
    xorl %edx, %edx
    xorq %rcx, %rcx
    xorq %r8, %r8
    callxt glSpecializeShader

    movl 28(%rsp), %edi # fragmentShader
    movl $0x8b81, %esi # GL_COMPILE_STATUS
    leaq 36(%rsp), %rdx # &success
    callxt glGetShaderiv
    movl 36(%rsp), %eax # success
    assert

    //

    callxt glCreateProgram
    movl %eax, 32(%rsp) # program
    assert

    movl 32(%rsp), %edi # program
    movl 24(%rsp), %esi # vertexShader
    callxt glAttachShader

    movl 32(%rsp), %edi # program
    movl 28(%rsp), %esi # fragmentShader
    callxt glAttachShader

    movl 32(%rsp), %edi # program
    callxt glLinkProgram

    movl 32(%rsp), %edi # program
    movl $0x8b82, %esi # GL_LINK_STATUS
    leaq 36(%rsp), %rdx # &success
    callxt glGetProgramiv
    movl 36(%rsp), %eax # success
    assert

    //

    movl 32(%rsp), %edi # program
    callxt glValidateProgram

    movl 32(%rsp), %edi # program
    movl $0x8b83, %esi # GL_VALIDATE_STATUS
    leaq 36(%rsp), %rdx # &success
    callxt glGetProgramiv
    movl 36(%rsp), %eax # success
    assert

    //

    movl 32(%rsp), %edi # program
    movl 28(%rsp), %esi # fragmentShader
    callxt glDetachShader
    movl 28(%rsp), %edi # fragmentShader
    callxt glDeleteShader

    movl 32(%rsp), %edi # program
    movl 24(%rsp), %esi # vertexShader
    callxt glDetachShader
    movl 24(%rsp), %edi # vertexShader
    callxt glDeleteShader

    //

    movl 32(%rsp), %eax # return program
    addq $MAKE_SHADERS_STACK, %rsp
    ret

function createTexquad
createTexquad: # receivex Texquad*, SDL_Surface* nullable, const mat4 model - pointer
    endbr64
    CREATE_TEXQUAD_STACK = 104 # // 0 alignment + 3 * 8 pointers + vec(4 * 4 floats * 4 bytes each)=64 + 16 padding
    subq $CREATE_TEXQUAD_STACK, %rsp
    movq %rdi, (%rsp) # Texquad*
    movq %rsi, 8(%rsp) # SDL_Surface*
    movq %rdx, 16(%rsp) # model
    # 32() vec4 vertices

    //

    # movq 8(%rsp), %rsi # SDL_Surface*
    testq %rsi, %rsi # surface == null
    jz .LcreateTexquad.skipTexture

    movl $0x0de1, %edi # GL_TEXTURE_2D
    movl $1, %esi
    movq (%rsp), %rdx # Texquad*
    leaq TEXQUAD_TEXTURE_OFFSET(%rdx), %rdx # &texquad->texture
    callxt glCreateTextures
    movq (%rsp), %rax # Texquad*
    movl TEXQUAD_TEXTURE_OFFSET(%rax), %eax # texquad->texture
    assert

    movq (%rsp), %rdi # Texquad*
    movl TEXQUAD_TEXTURE_OFFSET(%rdi), %edi # texquad->texture
    movl $0x2802, %esi # GL_TEXTURE_WRAP_S
    movl $0x812f, %edx # GL_CLAMP_TO_EDGE
    callxt glTextureParameteri

    movq (%rsp), %rdi # Texquad*
    movl TEXQUAD_TEXTURE_OFFSET(%rdi), %edi # texquad->texture
    movl $0x2803, %esi # GL_TEXTURE_WRAP_T
    movl $0x812f, %edx # GL_CLAMP_TO_EDGE
    callxt glTextureParameteri

    movq (%rsp), %rdi # Texquad*
    movl TEXQUAD_TEXTURE_OFFSET(%rdi), %edi # texquad->texture
    movl $0x2801, %esi # GL_TEXTURE_MIN_FILTER
    movl $0x2703, %edx # GL_LINEAR_MIPMAP_LINEAR
    callxt glTextureParameteri

    movq (%rsp), %rdi # Texquad*
    movl TEXQUAD_TEXTURE_OFFSET(%rdi), %edi # texquad->texture
    movl $0x2800, %esi # GL_TEXTURE_MAG_FILTER
    movl $0x2601, %edx # GL_LINEAR
    callxt glTextureParameteri

    movq (%rsp), %rdi # Texquad*
    movl TEXQUAD_TEXTURE_OFFSET(%rdi), %edi # texquad->texture
    movl $0x84fe, %esi # GL_TEXTURE_MAX_ANISOTROPY_EXT
    movss gMaxAnisotropy(%rip), %xmm0
    callxt glTextureParameterf

    movq (%rsp), %rdi # Texquad*
    movl TEXQUAD_TEXTURE_OFFSET(%rdi), %edi # texquad->texture
    movl $1, %esi
    movl $0x8058, %edx # GL_RGBA8
    movq 8(%rsp), %rax # SDL_Surface*
    movl 8(%rax), %ecx # surface->w
    movl 12(%rax), %r8d # surface->h
    callxt glTextureStorage2D

    movq (%rsp), %rdi # Texquad*
    movl TEXQUAD_TEXTURE_OFFSET(%rdi), %edi # texquad->texture
    xorl %esi, %esi
    xorl %edx, %edx
    xorl %ecx, %ecx
    movq 8(%rsp), %rax # SDL_Surface*
    movl 8(%rax), %r8d # surface->w
    movl 12(%rax), %r9d # surface->h
    pushq $0 # // stack alignment
    pushq 24(%rax) # // surface->pixels 9th
    pushq $0x1401 # // GL_UNSIGNED_BYTE 8th
    pushq $0x1908 # // GL_RGBA 7th
    callxt glTextureSubImage2D
    addq $32, %rsp # free stack memory

    movq (%rsp), %rdi # Texquad*
    movl TEXQUAD_TEXTURE_OFFSET(%rdi), %edi # texquad->texture
    callxt glGenerateTextureMipmap

    movq 8(%rsp), %rdi # SDL_Surface*
    callxt SDL_DestroySurface
    # surface is no more needed

.LcreateTexquad.skipTexture:

    //

    # rax = Texquad*
    # edi = 1.f
    # esi = texquad->y
    # edx = texquad->x
    # ecx = x + w
    # r8d = y + h

    xorps %xmm0, %xmm0

    # xmm0: width, -, height, - (ints)
    # then: width, -, height, - (floats)
    movq (%rsp), %rax # Texquad*
    insertps $0b00000000, TEXQUAD_W_OFFSET(%rax), %xmm0 # 00-00-0000 bits 0-7 from left to right - src: 0, dst: 0, zeroout: false; texquad->w
    insertps $0b00100000, TEXQUAD_H_OFFSET(%rax), %xmm0 # src: 0, dst: 2, zeroout: false; texquad->h
    cvtdq2ps %xmm0, %xmm0
    movl FLOATS+0(%rip), %edi # 1.f
    # xmm0: width, x, height, y (floats)
    # then: width + x, height + y, -, - (floats)
    insertps $0b00010000, TEXQUAD_X_OFFSET(%rax), %xmm0 # src: 0, dst: 1, zeroout: false; texquad->x
    insertps $0b00110000, TEXQUAD_Y_OFFSET(%rax), %xmm0 # src: 0, dst: 3, zeroout: false; texquad->y
    haddps %xmm0, %xmm0 # xmm0[0] = xmm0[0] + xmm0[1], xmm0[1] = xmm0[2] + xmm0[3]

    # vertices = vector
    extractps $0b00000000, %xmm0, %ecx # src: 0, dst: 0, zeroout: false; x + w
    movl %ecx, 32+0(%rsp) # vector[0] = x + w
    extractps $0b01000000, %xmm0, %r8d # src: 1, dst: 0, zeroout: false; y + h
    movl %r8d, 32+4(%rsp) # vector[1] = y + h
    movl %edi, 32+8(%rsp) # vector[2] = 1.f
    movl %edi, 32+12(%rsp) # vector[3] = 1.f
    #
    movl %ecx, 32+16(%rsp) # vector[4] = x + w
    movl TEXQUAD_Y_OFFSET(%rax), %esi # texquad->y
    movl %esi, 32+20(%rsp) # vector[5] = texquad->y
    movl %edi, 32+24(%rsp) # vector[6] = 1.f
    movl $0, 32+28(%rsp) # vector[7] = 0.f
    #
    movl TEXQUAD_X_OFFSET(%rax), %edx # texquad->x
    movl %edx, 32+32(%rsp) # vector[8] = texquad->x
    movl %esi, 32+36(%rsp) # vector[9] = texquad->y
    movl $0, 32+40(%rsp) # vector[10] = 0.f
    movl $0, 32+44(%rsp) # vector[11] = 0.f
    #
    movl %edx, 32+48(%rsp) # vector[12] = texquad->x
    movl %r8d, 32+52(%rsp) # vector[13] = y + h
    movl $0, 32+56(%rsp) # vector[14] = 0.f
    movl %edi, 32+60(%rsp) # vector[15] = 1.f

    //

    leaq OBJECT_VAO_OFFSET(%rax), %rdi # &texquad->vao
    leaq TEXQUAD_VBO_OFFSET(%rax), %rsi # &texquad->vbo
    leaq TEXQUAD_EBO_OFFSET(%rax), %rdx # &texquad->ebo
    movl $64, %ecx # sizeof(vertices)
    leaq 32(%rsp), %r8 # &vector
    call bootstrapQuad

    movq (%rsp), %rax # Texquad*
    movl OBJECT_VAO_OFFSET(%rax), %edi # texquad->vao
    xorl %esi, %esi
    movl TEXQUAD_VBO_OFFSET(%rax), %edx # texquad->vbo
    xorl %ecx, %ecx
    movl $16, %r8d # 4 * sizeof(float)
    callxt glVertexArrayVertexBuffer

    //

    movq (%rsp), %rax # Texquad*
    movl OBJECT_VAO_OFFSET(%rax), %edi # texquad->vao
    xorl %esi, %esi
    movl $4, %edx
    movl $0x1406, %ecx # GL_FLOAT
    xorl %r8d, %r8d # GL_FALSE
    xorl %r9d, %r9d
    callxt glVertexArrayAttribFormat

    movq (%rsp), %rax # Texquad*
    movl OBJECT_VAO_OFFSET(%rax), %edi # texquad->vao
    xorl %esi, %esi
    xorl %edx, %edx
    callxt glVertexArrayAttribBinding

    movq (%rsp), %rax # Texquad*
    movl OBJECT_VAO_OFFSET(%rax), %edi # texquad->vao
    xorl %esi, %esi
    callxt glEnableVertexArrayAttrib

    //

    movl $TEXQUAD_VERTEX_SIZE, %edi
    leaq TEXQUAD_VERTEX(%rip), %rsi
    movl $TEXQUAD_FRAGMENT_SIZE, %edx
    leaq TEXQUAD_FRAGMENT(%rip), %rcx
    call makeShaders
    movq (%rsp), %rdi # Texquad*
    movl %eax, OBJECT_PROGRAM_OFFSET(%rdi) # texquad->program = result

    //

    movq (%rsp), %rax # Texquad*
    movl TEXQUAD_CLIP_OFFSET(%rax), %edi # texquad->clip
    testl %edi, %edi
    jz .LcreateTexquad.skipTempVector

    xorps %xmm0, %xmm0
    xorps %xmm1, %xmm1

    # xmm0: texquad->w, -, texquad->h, - (ints)
    # then: ... (floats)
    insertps $0b00000000, TEXQUAD_W_OFFSET(%rax), %xmm0 # src: 0, dst: 0, zeroout: false; xmm0[0] = texquad->w
    insertps $0b00100000, TEXQUAD_H_OFFSET(%rax), %xmm0 # src: 0, dst: 2, zeroout: false; xmm0[2] = texquad->h
    cvtdq2ps %xmm0, %xmm0
    # xmm1: 2.f, -, 2.f, - (floats)
    insertps $0b00000000, FLOATS+4(%rip), %xmm1 # src: 0, dst: 0, zeroout: false; xmm1[0] = 2.f
    insertps $0b00100000, FLOATS+4(%rip), %xmm1 # src: 0, dst: 2, zeroout: false; xmm1[2] = 2.f

    # xmm0: texquad->w / 2.f, -, texquad->h / 2.f, - (floats)
    divps %xmm1, %xmm0
    movaps %xmm0, %xmm1 # copy xmm0 to xmm1

    # xmm0: wHalf, -, hHalf, - (floats)
    # then: wHalf, x, hHalf, y (floats)
    insertps $0b00010000, TEXQUAD_X_OFFSET(%rax), %xmm0 # src: 0, dst: 1, zeroout: false; texquad->x
    insertps $0b00110000, TEXQUAD_Y_OFFSET(%rax), %xmm0 # src: 0, dst: 3, zeroout: false; texquad->y
    # xmm0: wHalf + x, hHalf + y, -, - (floats)
    haddps %xmm0, %xmm0

    # 32() vec4(4 floats) temp
    movsd %xmm0, 32+0(%rsp) # vector[0] = x + wHalf and vector[1] = y + hHalf
    extractps $0b00000000, %xmm1, 32+8(%rsp) # src: 0, dst: 0, zeroout: false; vector[2] = wHalf
    extractps $0b10000000, %xmm1, 32+12(%rsp) # src: 2, dst: 0, zeroout: false; vector[3] = hHalf
.LcreateTexquad.skipTempVector:
    # 32() vec4(4 floats) temp, zero it out
    xorps %xmm0, %xmm0
    movaps %xmm0, 32(%rsp)

    //
// TODO: check the name of all the functions

    # movq (%rsp), %rax # Texquad*
    movl OBJECT_PROGRAM_OFFSET(%rax), %edi # texquad->program
    movl $3, %esi
    movl $1, %edx
    leaq 32(%rsp), %rcx # &vector
    callxt glProgramUniform4fv

    //

    movq (%rsp), %rax # Texquad*
    movl OBJECT_PROGRAM_OFFSET(%rax), %edi # texquad->program
    xorl %esi, %esi
    movl $1, %edx
    xorl %ecx, %ecx # GL_FALSE
    movq 16(%rsp), %r8 # mat4* model
    callxt glProgramUniformMatrix4fv

    //

    addq $CREATE_TEXQUAD_STACK, %rsp
    ret

function createTexture
createTexture: # return SDL_Surface*; receives: char* imgPathOrText, bool imageOrText
    endbr64

    CREATE_TEXTURE_STACK = 40
    subq $CREATE_TEXTURE_STACK, %rsp # 3 * 8 void* + 4 int + 12 padding for stack alignment
    # 0() imgPathOrText, 8() imageOrText, 12() SDL_Surface* temp, 20() SDL_Surface* converted

    movq %rdi, (%rsp) # * imgPathOrText
    movl %esi, 8(%rsp) # bool/int imageOrText
    movq $0, 12(%rsp) # * temp
    movq $0, 20(%rsp) # * converted

    //

    testl %esi, %esi # if imageOrText
    jz .LcreateTexture.text
    #movq %rdi, %rdi # imgPathOrText
    callxt IMG_Load
    jmp .LcreateTexture.endCondition
.LcreateTexture.text:
    movq gFont(%rip), %rdi
    movq (%rsp), %rsi # imgPathOrText
    xorq %rdx, %rdx
    movl $0x7f7f7fff, %ecx # (SDL_Color) {127, 127, 127, 255}
    callxt TTF_RenderText_Blended
.LcreateTexture.endCondition:
    movq %rax, 12(%rsp) # temp surface
    assert

    //

    movq 12(%rsp), %rdi # temp surface
    movl $0x16762004, %esi # SDL_PIXELFORMAT_RGBA32
    callxt SDL_ConvertSurface
    movq %rax, 20(%rsp) # converted surface
    assert

    movq 12(%rsp), %rdi # temp surface
    callxt SDL_DestroySurface

    //

    movq 20(%rsp), %rdi # converted surface
    movl $2, %esi # SDL_FLIP_VERTICAL
    callxt SDL_FlipSurface
    assert

    //

    movq 20(%rsp), %rax # return converted surface
    addq $CREATE_TEXTURE_STACK, %rsp
    retq

function renderTexquad
renderTexquad: # receives Texquad*
    endbr64
    subq $8, %rsp # stack alignment (cuz inside a caller it's aligned until the call instruction which substructs 8, making the stack misaligned, so we need to substract 8 more bytes to align the stack)
    movq %rdi, (%rsp) # Texquad* inside 0()

    //

    #movq %rdi, %rdi # texquad
    movl OBJECT_PROGRAM_OFFSET(%rdi), %edi # *(Texquad* + OFF) = texquad->program
    callxt glUseProgram
    movl $0x0de1, %edi # GL_TEXTURE_2D
    movq (%rsp), %rsi # Texquad*
    movl TEXQUAD_TEXTURE_OFFSET(%rsi), %esi # *(Texquad* + OFF) = texquad->texture
    callxt glBindTexture
    movq (%rsp), %rax # Texquad*
    movl OBJECT_VAO_OFFSET(%rax), %edi # texquad->vao
    callxt glBindVertexArray

    //

    movl $4, %edi # GL_TRIANGLES
    movl $6, %esi
    movl $0x1405, %edx # GL_UNSIGNED_INT
    xorq %rcx, %rcx
    callxt glDrawElements

    //

    xorl %edi, %edi
    callxt glBindVertexArray
    movl $0x0de1, %edi # GL_TEXTURE_2D
    xorl %esi, %esi
    callxt glBindTexture
    xorl %edi, %edi
    callxt glUseProgram

    addq $8, %rsp
    ret

function removeTexquad
removeTexquad: # receives Texquad*
    endbr64
    REMOVE_TEXQUAD_STACK = 24 # // 8 Texquad* + arr(4 int + 4 int) + 8 padding
    subq $REMOVE_TEXQUAD_STACK, %rsp # stack alignment (aligned -> call -> misaligned -> *align* -> free -> return); 0() Texquad*, 8() array of ids, 16() padding
    movq %rdi, (%rsp) # Texquad*

    movl $1, %edi
    movq (%rsp), %rax # Texquad*
    leaq TEXQUAD_TEXTURE_OFFSET(%rax), %rsi # &texquad->texture
    callxt glDeleteTextures

    movq (%rsp), %rax # Texquad*
    movl OBJECT_PROGRAM_OFFSET(%rax), %edi # texquad->program
    callxt glDeleteProgram

    movl $2, %edi
    movq (%rsp), %rsi # Texquad*
    movl TEXQUAD_EBO_OFFSET(%rsi), %eax # texquad->ebo
    movl %eax, 8+0(%rsp) # arr[0] = ebo
    movl TEXQUAD_VBO_OFFSET(%rsi), %eax # texquad->vbo
    movl %eax, 8+4(%rsp) # arr[1] = vbo
    leaq 8(%rsp), %rsi # (uint[2]) {texquad->ebo, texquad->vbo}
    callxt glDeleteBuffers

    movl $1, %edi
    movq (%rsp), %rax # Texquad*
    leaq OBJECT_VAO_OFFSET(%rax), %rsi # &texquad->vao
    callxt glDeleteVertexArrays

    addq $REMOVE_TEXQUAD_STACK, %rsp
    ret

function createLine
createLine: # receives Line*
    endbr64
    CREATE_LINE_STACK = 24 # // 4 * 4 float + Line* = 16 + 8
    subq $CREATE_LINE_STACK, %rsp # 0() vector(4 * floats), 16() Line* and stack alignment
    movq %rdi, 16(%rsp) # Line*

    movl $1, %edi
    movq 16(%rsp), %rax # Line*
    leaq OBJECT_VAO_OFFSET(%rax), %rsi # &line->vao
    callxt glGenVertexArrays
    movq 16(%rsp), %rax # Line*
    movl OBJECT_VAO_OFFSET(%rax), %eax # line->vao
    assert

    //

    movl $LINE_VERTEX_SIZE, %edi
    leaq LINE_VERTEX(%rip), %rsi
    movl $LINE_FRAGMENT_SIZE, %edx
    leaq LINE_FRAGMENT(%rip), %rcx
    call makeShaders
    movq 16(%rsp), %rdi # Line*
    movl %eax, OBJECT_PROGRAM_OFFSET(%rdi) # line->program

    //

    movl %eax, %edi # line->program
    xorl %esi, %esi
    movl $1, %edx
    movq 16(%rsp), %rcx # Line*
    leaq LINE_X0_OFFSET(%rcx), %rcx # &line->x0 = &vecor(line->x0, line->y0, line->x1, line->y1) # aligned inside the struct
    callxt glProgramUniform4fv

    movq 16(%rsp), %rax # Line*
    movl OBJECT_PROGRAM_OFFSET(%rax), %edi # line->program
    movl $1, %esi
    movss LINE_WIDTH_OFFSET(%rax), %xmm0 # line->width
    callxt glProgramUniform1f

    # xmm0 = {0.f, 1.f, 0.f, 1.f}
    # vector = xmm0, aligned
    xorps %xmm0, %xmm0 # xmm0 = 0
    insertps $0b00010000, FLOATS+0(%rip), %xmm0 # src: 0, dst: 1, zeroout: false; xmm0[1] = 1.f
    insertps $0b00110000, FLOATS+0(%rip), %xmm0 # src: 0, dst: 3, zeroout: false; xmm0[3] = 1.f
    movaps %xmm0, (%rsp) # vector = xmm0

    movq 16(%rsp), %rdi # Line*
    movl OBJECT_PROGRAM_OFFSET(%rdi), %edi # line->program
    movl $2, %esi
    movl $1, %edx
    leaq (%rsp), %rcx # &vector[0]
    callxt glProgramUniform4fv

    //

    addq $CREATE_LINE_STACK, %rsp
    ret

function renderLine
renderLine: # receives const Line*
    endbr64
    subq $8, %rsp # stack alignment
    movq %rdi, (%rsp) # Line* line

    //

    # movq %rdi, %rdi
    movl OBJECT_PROGRAM_OFFSET(%rdi), %edi # line->program
    callxt glUseProgram

    movq (%rsp), %rdi # Line*
    movl OBJECT_VAO_OFFSET(%rdi), %edi # line->vao
    callxt glBindVertexArray

    movl $4, %edi # GL_TRIANGLES
    xorl %esi, %esi
    movl $6, %edx
    callxt glDrawArrays

    xorl %edi, %edi
    callxt glBindVertexArray

    xorl %edi, %edi
    callxt glUseProgram

    //

    addq $8, %rsp
    ret

function removeLine
removeLine: # receives Line* line
    endbr64
    subq $8, %rsp # stack alignment
    movq %rdi, (%rsp) # Line*

    //

    movl $1, %edi
    movq (%rsp), %rsi # Line*
    leaq OBJECT_VAO_OFFSET(%rsi), %rsi # &line->vao
    callxt glDeleteVertexArrays

    movq (%rsp), %rdi # Line*
    movl OBJECT_PROGRAM_OFFSET(%rdi), %edi # line->program
    callxt glDeleteProgram

    //

    addq $8, %rsp
    ret

function processObject
processObject: # receives Object* object (rdi), bool renderOrDelete (4 bytes, esi)
    endbr64
    PROCESS_OBJECT_STACK = 24 # // 8 Object* + 4 bool/int + 12 padding
    subq $PROCESS_OBJECT_STACK, %rsp # 0() Object*, 8() bool, 12() padding
    movq %rdi, (%rsp) # * object
    movl %esi, 8(%rsp) # renderOrDelete?

    //

    # movq %rdi, %rdi
    movl OBJECT_TYPE_OFFSET(%rdi), %eax # object->type

    cmpl $0, %eax # TYPE_TEXQUAD # TODO: replace with 'and'
    je .LprocessObject.texquad
    cmpl $1, %eax # TYPE_LINE
    je .LprocessObject.line

    xorl %eax, %eax
    assert

    //

.LprocessObject.texquad:
    # movl 8(%rsp), %esi # renderOrDelete?
    testl %esi, %esi
    jz .LprocessObject.texquad.delete

    movq (%rsp), %rdi # * object # TODO: optimize
    call renderTexquad
    jmp .LprocessObject.end
.LprocessObject.texquad.delete:
    movq (%rsp), %rdi # * object
    call removeTexquad
    jmp .LprocessObject.end

    //

.LprocessObject.line:
    # movl 8(%rsp), %esi # renderOrDelete?
    testl %esi, %esi
    jz .LprocessObject.line.delete

    movq (%rsp), %rdi # * object
    call renderLine
    jmp .LprocessObject.end
.LprocessObject.line.delete:
    movq (%rsp), %rdi # * object
    call removeLine
    jmp .LprocessObject.end

    //

.LprocessObject.end:
    movl 8(%rsp), %eax # renderOrDelete?
    testl %eax, %eax
    jnz .LprocessObject.end.noFree
    movq (%rsp), %rdi # * object
    callxt free
.LprocessObject.end.noFree:

    //

    addq $PROCESS_OBJECT_STACK, %rsp
    ret

function render
render:
    endbr64
    subq $8, %rsp # stack alignment and temp variable

    movl $0x8ca9, %edi # GL_DRAW_FRAMEBUFFER
    movl FBO_ID_OFFSET+gMsaaFbo(%rip), %esi # gMsaaFbo.id
    callxt glBindFramebuffer

    //

    movss FLOATS+0(%rip), %xmm0 # 1.f
    movss FLOATS+0(%rip), %xmm1 # 1.f
    movss FLOATS+0(%rip), %xmm2 # 1.f
    movss FLOATS+0(%rip), %xmm3 # 1.f
    callxt glClearColor

    movl $0x4000, %edi # GL_COLOR_BUFFER_BIT
    callxt glClear

    //

    movl $0, (%rsp) # counter = 0
.Lrender.loop:
    leaq gObjects(%rip), %rdi # &gObjects[0] = gObjects
    movl (%rsp), %esi # counter
    movq 0(%rdi, %rsi, 8), %rdi # rdi = 0 + rdi + rsi * 8 = gObjects[counter] = Object*
    movl $1, %esi # true
    call processObject

    incl (%rsp) # counter++
    cmpl $OBJECTS, (%rsp)
    jl .Lrender.loop # // if (counter < OBJECTS) repeat

    //

    movl $0x8ca9, %edi # GL_DRAW_FRAMEBUFFER
    xorl %esi, %esi
    callxt glBindFramebuffer

    subq $48, %rsp # 6 arguments (8 bytes each due to pushq/popq)
    movl FBO_ID_OFFSET+gMsaaFbo(%rip), %edi # gMsaaFbo.id
    movl FBO_ID_OFFSET+gPostprocessingFbo(%rip), %esi # gPostprocessingFbo.id
    xorl %edx, %edx
    xorl %ecx, %ecx
    movl $WIDTH, %r8d
    movl $HEIGHT, %r9d
    movl $0, 0(%rsp) # args are put in reverse order after 6th one
    movl $0, 8(%rsp)
    movl $WIDTH, 16(%rsp)
    movl $HEIGHT, 24(%rsp)
    movl $0x4000, 32(%rsp) # GL_COLOR_BUFFER_BIT
    movl $0x2600, 40(%rsp) # GL_NEAREST
    callxt glBlitNamedFramebuffer
    addq $48, %rsp # free stack memmory

    leaq gPostprocessingTexquad(%rip), %rdi # &gPostprocessingTexquad
    call renderTexquad

    addq $8, %rsp
    ret

function createUbo
createUbo:
    endbr64
    CREATE_UBO_STACK = 72 # // projection matrix of 4 vectors of 4 floats each 0(rsp) + 8 alignment
    subq $CREATE_UBO_STACK, %rsp

    //

    movl $WIDTH, (%rsp) # temp
    movl $HEIGHT, 4(%rsp) # temp
    movlpd (%rsp), %xmm0 # xmm0[0-1 of 4] = quadword; moves 8 bytes to lower 8 bytes of xmm0
    cvtdq2ps %xmm0, %xmm0 # convert them to floats
    insertps $0b00001110, %xmm0, %xmm1 # src: 0, dst: 0, zeroout: 1_2_3; xmm1[0] = xmm0[0]
    insertps $0b01001110, %xmm0, %xmm3 # src: 1, dst: 0, zeroout: 1_2_3; xmm3[0] = xmm0[1]
    xorps %xmm0, %xmm0
    # xmm1
    xorps %xmm2, %xmm2
    # xmm3
    xorps %xmm4, %xmm4
    movss FLOATS+0(%rip), %xmm5 # 1.f
    leaq (%rsp), %rdi # &projection
    callxt glmc_ortho

    //

    movl $1, %edi
    leaq gUbo(%rip), %rsi
    callxt glCreateBuffers
    movl gUbo(%rip), %eax
    assert

    movl gUbo(%rip), %edi
    movl $64, %esi # sizeof(mat4)
    leaq (%rsp), %rdx # &projection
    xorl %ecx, %ecx
    callxt glNamedBufferStorage

    movl $0x8a11, %edi # GL_UNIFORM_BUFFER
    xorl %esi, %esi
    movl gUbo(%rip), %edx
    callxt glBindBufferBase

    //

    addq $CREATE_UBO_STACK, %rsp
    ret

function removeUbo
removeUbo:
    endbr64
    subq $8, %rsp # stack alignment

    movl $1, %edi
    leaq gUbo(%rip), %rsi
    callxt glDeleteBuffers

    addq $8, %rsp # stack alignment
    ret

function createFbos
createFbos:
    endbr64
    subq $8, %rsp # stack alignment

    // msaa

    movl $0x9100, %edi # GL_TEXTURE_2D_MULTISAMPLE
    movl $1, %esi
    leaq FBO_TEXTURE_OFFSET+gMsaaFbo(%rip), %rdx # &gMsaaFbo.texture
    callxt glCreateTextures
    movl FBO_TEXTURE_OFFSET+gMsaaFbo(%rip), %eax # gMsaaFbo.texture
    assert

    movl FBO_TEXTURE_OFFSET+gMsaaFbo(%rip), %edi # gMsaaFbo.texture
    movl $4, %esi
    movl $0x8058, %edx # GL_RGBA8
    movl $WIDTH, %ecx
    movl $HEIGHT, %r8d
    movl $1, %r9d # GL_TRUE
    callxt glTextureStorage2DMultisample

    //

    movl $1, %edi
    leaq FBO_ID_OFFSET+gMsaaFbo(%rip), %rsi # &gMsaaFbo.id
    callxt glCreateFramebuffers
    movl FBO_ID_OFFSET+gMsaaFbo(%rip), %eax # gMsaaFbo.id
    assert

    movl FBO_ID_OFFSET+gMsaaFbo(%rip), %edi # gMsaaFbo.id
    movl $0x8ce0, %esi # GL_COLOR_ATTACHMENT0
    movl FBO_TEXTURE_OFFSET+gMsaaFbo(%rip), %edx # gMsaaFbo.texture
    xorl %ecx, %ecx
    callxt glNamedFramebufferTexture

    movl FBO_ID_OFFSET+gMsaaFbo(%rip), %edi # gMsaaFbo.id
    movl $0x8d40, %esi # GL_FRAMEBUFFER
    callxt glCheckNamedFramebufferStatus
    andl $0x8cd5, %eax # eax == <> ?, GL_FRAMEBUFFER_COMPLETE
    assert # // result == constant

    // postprocessing

    movl $0x0de1, %edi # GL_TEXTURE_2D
    movl $1, %esi
    leaq FBO_TEXTURE_OFFSET+gPostprocessingFbo(%rip), %rdx # &gPostprocessingFbo.texture
    callxt glCreateTextures
    movl FBO_TEXTURE_OFFSET+gPostprocessingFbo(%rip), %eax # gPostprocessingFbo.texture
    assert

    movl FBO_TEXTURE_OFFSET+gPostprocessingFbo(%rip), %edi # gPostprocessingFbo.texture
    movl $0x2801, %esi # GL_TEXTURE_MIN_FILTER
    movl $0x2601, %edx # GL_LINEAR
    callxt glTextureParameteri

    movl FBO_TEXTURE_OFFSET+gPostprocessingFbo(%rip), %edi # gPostprocessingFbo.texture
    movl $0x2800, %esi # GL_TEXTURE_MAG_FILTER
    movl $0x2601, %edx # GL_LINEAR
    callxt glTextureParameteri

    movl FBO_TEXTURE_OFFSET+gPostprocessingFbo(%rip), %edi # gPostprocessingFbo.texture
    movl $0x84fe, %esi # GL_TEXTURE_MAX_ANISOTROPY_EXT
    movss gMaxAnisotropy(%rip), %xmm0
    callxt glTextureParameterf

    movl FBO_TEXTURE_OFFSET+gPostprocessingFbo(%rip), %edi # gPostprocessingFbo.texture
    movl $1, %esi
    movl $0x8058, %edx # GL_RGBA8
    movl $WIDTH, %ecx
    movl $HEIGHT, %r8d
    callxt glTextureStorage2D

    //

    movl $1, %edi
    leaq FBO_ID_OFFSET+gPostprocessingFbo(%rip), %rsi # &gPostprocessingFbo.id
    callxt glCreateFramebuffers
    movl FBO_ID_OFFSET+gPostprocessingFbo(%rip), %eax # gPostprocessingFbo.id
    assert

    movl FBO_ID_OFFSET+gPostprocessingFbo(%rip), %edi # gPostprocessingFbo.id
    movl $0x8ce0, %esi # GL_COLOR_ATTACHMENT0
    movl FBO_TEXTURE_OFFSET+gPostprocessingFbo(%rip), %edx # gPostprocessingFbo.texture
    xorl %ecx, %ecx
    callxt glNamedFramebufferTexture

    movl FBO_ID_OFFSET+gPostprocessingFbo(%rip), %edi # gPostprocessingFbo.id
    movl $0x8d40, %esi # GL_FRAMEBUFFER
    callxt glCheckNamedFramebufferStatus
    andl $0x8cd5, %eax # eax == <> ?, GL_FRAMEBUFFER_COMPLETE
    assert # // result == constant

    //

    addq $8, %rsp # stack alignment
    ret

function removeFbos
removeFbos:
    endbr64
    subq $8, %rsp # stack alignment and vector of 2 uints // TODO: address of the vector isn't aligned

    //

    movl FBO_TEXTURE_OFFSET+gMsaaFbo(%rip), %eax # gMsaaFbo.texture
    movl %eax, 0(%rsp) # vector<uint>[0]
    movl FBO_TEXTURE_OFFSET+gPostprocessingFbo(%rip), %eax # gPostprocessingFbo.texture
    movl %eax, 4(%rsp) # vector<uint>[1]

    movl $2, %edi
    leaq 0(%rsp), %rsi # &vector
    callxt glDeleteTextures

    movl FBO_ID_OFFSET+gMsaaFbo(%rip), %eax # gMsaaFbo.id
    movl %eax, 0(%rsp) # vector<uint>[0]
    movl FBO_ID_OFFSET+gPostprocessingFbo(%rip), %eax # gPostprocessingFbo.id
    movl %eax, 4(%rsp) # vector<uint>[1]

    movl $2, %edi
    leaq 0(%rsp), %rsi # &vector
    callxt glDeleteFramebuffers

    //

    addq $8, %rsp # stack alignment
    ret

function togglePostprocessing
togglePostprocessing: # receives bool (4 bytes) onOrOff
    endbr64
    subq $8, %rsp # stack alignment
    movl %edi, %edx # onOrOff?

    movl OBJECT_PROGRAM_OFFSET+gPostprocessingTexquad(%rip), %edi # gPostprocessingTexquad.program
    movl $2, %esi
    # movl %edx, %edx
    callxt glProgramUniform1i

    addq $8, %rsp # stack alignment
    ret

function createObjects # // ------------------> TODO: for buffers: aligned allocation and 8(%rsp) - would yield unaligned addr for buffer start -> change to 0(%rsp) (move padding to the other end)
createObjects:
    endbr64
    CREATE_OBJECTS_STACK = 88 # // 8 alignment and SDL_Surface* 0(%rsp) + padding + 4 vectors of 4 floats of 4 bytes each = 8 + 8 + 4^3 + padding; 16(%rsp) = mat4 model
    subq $CREATE_OBJECTS_STACK, %rsp

    //

    call createUbo
    call createFbos

    leaq 16(%rsp), %rdi # &model
    callxt glmc_mat4_identity

    //

    # everything inside .bss is initialized with zeroes
    movl $0, OBJECT_TYPE_OFFSET+gPostprocessingTexquad(%rip)
    movl $WIDTH, TEXQUAD_W_OFFSET+gPostprocessingTexquad(%rip)
    movl $HEIGHT, TEXQUAD_H_OFFSET+gPostprocessingTexquad(%rip)

    leaq gPostprocessingTexquad(%rip), %rdi # &gPostprocessingTexquad
    xorq %rsi, %rsi
    leaq 16(%rsp), %rdx # &model
    call createTexquad

    movl FBO_TEXTURE_OFFSET+gPostprocessingFbo(%rip), %eax
    movl %eax, TEXQUAD_TEXTURE_OFFSET+gPostprocessingTexquad(%rip) # gPostprocessingTexquad.texture = gPostprocessingFbo.texture

    //

    leaq TEST_STR(%rip), %rdi
    xorl %esi, %esi # false
    call createTexture
    movq %rax, (%rsp) # SDL_Surface*

    movl $TEXQUAD_SIZE, %edi # sizeof(Texquad)
    movl $1, %esi
    callxt calloc
    movq %rax, 0+gObjects(%rip) # gObjects[0] = Texquad*
    assert

    movq 0+gObjects(%rip), %rax # Texquad*
    movl $0, OBJECT_TYPE_OFFSET(%rax) # TYPE_TEXQUAD
    movl $0x43520000, TEXQUAD_X_OFFSET(%rax) # 210
    movl $0x439b0000, TEXQUAD_Y_OFFSET(%rax) # 310
    movl $420, TEXQUAD_W_OFFSET(%rax)
    movl $320, TEXQUAD_H_OFFSET(%rax)

    movq %rax, %rdi # gObjects[0]
    movq (%rsp), %rsi # SDL_Surface*, no longer needed
    leaq 16(%rsp), %rdx # &model
    call createTexquad

    leaq 16(%rsp), %rdi # &model
    callxt glmc_mat4_identity

    //

    leaq IMAGE_NAME(%rip), %rdi
    movl $1, %esi # true
    call createTexture
    movq %rax, (%rsp) # SDL_Surface*

    movl $TEXQUAD_SIZE, %edi # sizeof(Texquad)
    movl $1, %esi
    callxt calloc
    movq %rax, 8+gObjects(%rip) # gObjects[1] = Texquad*
    assert

    movq 8+gObjects(%rip), %rax # gObjects[1] = Texquad*
    movl $0, OBJECT_TYPE_OFFSET(%rax) # TYPE_TEXQUAD
    movl $0x42480000, TEXQUAD_X_OFFSET(%rax) # 50
    movl $0x42480000, TEXQUAD_Y_OFFSET(%rax) # 50
    movl $320, TEXQUAD_W_OFFSET(%rax)
    movl $320, TEXQUAD_H_OFFSET(%rax)
    movl $1, TEXQUAD_CLIP_OFFSET(%rax)

    movq %rax, %rdi # gObjects[1]
    movq (%rsp), %rsi # SDL_Surface*
    leaq 16(%rsp), %rdx # &model
    call createTexquad

    movl $LINE_SIZE, %edi # sizeof(Line)
    movl $1, %esi
    callxt calloc
    movq %rax, 16+gObjects(%rip) # gObjects[2] = Line*
    assert

    movq 16+gObjects(%rip), %rax # gObjects[2] = Line*
    movl $1, OBJECT_TYPE_OFFSET(%rax) # TYPE_LINE
    movl $0x43fa0000, LINE_X0_OFFSET(%rax) # 500
    movl $0x42c80000, LINE_Y0_OFFSET(%rax) # 100
    movl $0x44160000, LINE_X1_OFFSET(%rax) # 600
    movl $0x42c80000, LINE_Y1_OFFSET(%rax) # 100
    movl $0x41200000, LINE_WIDTH_OFFSET(%rax) # 10

    movq %rax, %rdi
    call createLine

    //

    addq $CREATE_OBJECTS_STACK, %rsp
    ret

function removeObjects
removeObjects:
    endbr64
    subq $8, %rsp # stack alignment and counter

    movl $0, (%rsp) # counter
.LremoveObjects.loop:
    movl (%rsp), %eax # counter (i)
    leaq gObjects(%rip), %rdi # &gObjects[0]
    movq 0(%rdi, %rax, 8), %rdi # 0 + rdi + rax * 8 # gObjects[i]
    xorl %esi, %esi # false
    call processObject

    incl (%rsp) # i++ # TODO: use non-volatile register

    cmpl $OBJECTS, (%rsp) # while i < OBJECTS
    jl .LremoveObjects.loop

    //

    leaq gPostprocessingTexquad(%rip), %rdi
    call removeTexquad
    call removeFbos
    call removeUbo

    addq $8, %rsp # stack alignment
    ret

function loop
loop: # receives SDL_Window*
    endbr64

    # 8 - window, 128 - event, 8 - ticks, 4 postprocessingEnabled, 4 padding for stack alignment
    LOOP_STACK = 152
    subq $LOOP_STACK, %rsp
    # 0(%rsp) = window, 8(%rsp) = ticks, 16(%rsp) = event, 144(%rsp) = postprocessingEnabled? 4 bytes
    movq %rdi, (%rsp) # * window
    movl $0, 144(%rsp) # postprocessingEnabled

    //

    call createObjects

.Lloop.infiniteLoop:
    callxt SDL_GetTicks
    movq %rax, 8(%rsp) # ticks

    //

    # movl $0x3f80000, %eax # IEEE-754 floating point hex representation (little endian) = 1.f
    movss FLOATS+0(%rip), %xmm0
    movss FLOATS+0(%rip), %xmm1
    movss FLOATS+0(%rip), %xmm2
    movss FLOATS+0(%rip), %xmm3
    callxt glClearColor

    movl $0x4000, %edi # GL_COLOR_BUFFER_BIT
    callxt glClear

    call render

    //

    movq (%rsp), %rdi # * window
    callxt SDL_GL_SwapWindow
    assert

    //

.Lloop.eventsLoop:
    leaq 16(%rsp), %rdi # event
    callxt SDL_PollEvent
    testl %eax, %eax
    jz .Lloop.eventsLoopEnd

    cmpl $0x100, 16(%rsp) # event.type SDL_EVENT_QUIT
    je .Lloop.infiniteLoopEnd

    cmpl $0x300, 16(%rsp) # event.type SDL_EVENT_KEY_DOWN
    jne .Lloop.eventsLoop

    cmpl $0x71, 16+28(%rsp) # event.key.key SDLK_Q
    je .Lloop.infiniteLoopEnd

    cmpl $0x60, 16+28(%rsp) # event.key.key SDLK_GRAVE
    jne .Lloop.eventsLoop

    notl 144(%rsp) # postprocessingEnabled
    movl 144(%rsp), %edi
    call togglePostprocessing

    jmp .Lloop.eventsLoop

.Lloop.eventsLoopEnd:
    callxt SDL_GetTicks # // rax = elapsed
    subq 8(%rsp), %rax # ticks, elapsed # rax=elapsed = returned - ticks
    cmpq $UPDATE_PERIOD, %rax # elapsed - update
    jae .Lloop.infiniteLoop # // if elapsed >= update then ignore = if elapsed < update then delay

    movl $UPDATE_PERIOD, %edi
    subl %eax, %edi # edi = update - elapsed
    callxt SDL_Delay
    jmp .Lloop.infiniteLoop

.Lloop.infiniteLoopEnd:

    call captureCanvas
    call removeObjects

    addq $LOOP_STACK, %rsp
    ret

function debugCallback
debugCallback: # recieves many things, we care only about char* message 6h argument - r9
    endbr64
    # ignore misalignment
    xprint DEBUG_S r9 0 # // push/pop stack - makes it temporary aligned so we don't have to do it here
    ret

.global main
function main
main:
    endbr64
    MAIN_STACK = 24 # // SDL_Window* + SDL_GLContextState*
    subq $MAIN_STACK, %rsp # 0() window, 8() glContext, 16() padding; rsp initially is not 16-aligned so we need to add extra 8 -> 16 + 8 = 24

    leaq SDL_HINT_VIDEO_DRIVER(%rip), %rdi
    leaq VIDEO_DRIVERS(%rip), %rsi
    callxt SDL_SetHint
    assert

    movl $0x20, %edi # SDL_INIT_VIDEO
    orl $0x4000, %edi # SDL_INIT_EVENTS
    callxt SDL_Init
    assert

    //

    callxt TTF_Init
    assert

    leaq FONT(%rip), %rdi
    movss FLOATS+0(%rip), %xmm0 # 1.f
    callxt TTF_OpenFont
    movq %rax, gFont(%rip)
    assert

    movq gFont(%rip), %rdi
    movl $0x42f00000, %eax # 120.f
    movd %eax, %xmm0
    movl $100, %esi
    movl $100, %edx
    callxt TTF_SetFontSizeDPI
    assert

    //

    movl $17, %edi # SDL_GL_CONTEXT_MAJOR_VERSION
    movl $4, %esi
    callxt SDL_GL_SetAttribute
    assert
    movl $18, %edi # SDL_GL_CONTEXT_MINOR_VERSION
    movl $6, %esi
    callxt SDL_GL_SetAttribute
    assert
    movl $20, %edi # SDL_GL_CONTEXT_PROFILE_MASK
    movl $1, %esi # SDL_GL_CONTEXT_PROFILE_CORE
    callxt SDL_GL_SetAttribute
    assert
    movl $13, %edi # SDL_GL_MULTISAMPLEBUFFERS
    movl $1, %esi
    callxt SDL_GL_SetAttribute
    assert
    movl $14, %edi # SDL_GL_MULTISAMPLESAMPLES
    movl $4, %esi
    callxt SDL_GL_SetAttribute
    assert
    movl $15, %edi # SDL_GL_ACCELERATED_VISUAL
    movl $1, %esi
    callxt SDL_GL_SetAttribute
    assert
    movl $19, %edi # SDL_GL_CONTEXT_FLAGS
    movl $1, %esi # SDL_GL_CONTEXT_DEBUG_FLAG
    callxt SDL_GL_SetAttribute
    assert

    //

    leaq EMPTY_STR(%rip), %rdi
    movl $WIDTH, %esi
    movl $HEIGHT, %edx
    movl $2, %ecx # SDL_WINDOW_OPENGL
    callxt SDL_CreateWindow
    movq %rax, (%rsp) # window
    assert

    //

    movq (%rsp), %rdi # window
    callxt SDL_GL_CreateContext
    movq %rax, 8(%rsp) # glContext
    assert

    //

    xorl %edi, %edi
    xorl %esi, %esi
    movl $WIDTH, %edx
    movl $HEIGHT, %ecx
    callxt glViewport

    //

    movl $0x92e0, %edi # GL_DEBUG_OUTPUT
    callxt glEnable
    movl $0x8242, %edi # GL_DEBUG_OUTPUT_SYNCHRONOUS
    callxt glEnable
    leaq debugCallback(%rip), %rdi
    xorq %rsi, %rsi # nullptr
    callxt glDebugMessageCallback

    //

    movl $0x809d, %edi # GL_MULTISAMPLE
    callxt glEnable
    movl $0x809e, %edi # GL_SAMPLE_ALPHA_TO_COVERAGE
    callxt glEnable

    //

    movl $0xbe2, %edi # GL_BLEND
    callxt glEnable
    movl $0x302, %edi # GL_SRC_ALPHA
    movl $0x303, %esi # GL_ONE_MINUS_SRC_ALPHA
    callxt glBlendFunc

    //

    movl $1, %edi
    callxt SDL_GL_SetSwapInterval
    assert

    //

    movl $0x84ff, %edi # GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT
    leaq gMaxAnisotropy(%rip), %rsi
    callxt glGetFloatv

    //

    movq (%rsp), %rdi # window
    call loop

    //

    leaq 8(%rsp), %rdi # glContext
    callxt SDL_GL_DestroyContext
    assert

    movq (%rsp), %rdi # window
    callxt SDL_DestroyWindow

    //

    movq gFont(%rip), %rdi
    callxt TTF_CloseFont
    callxt TTF_Quit

    //

    callxt SDL_Quit

    //

    xorl %eax, %eax # return 0
    addq $MAIN_STACK, %rsp
    ret
