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

// --> current: gcc -s -pie -fpie -fomit-frame-pointer -fno-plt -Wl,-z,relro,-z,now -lSDL3 -lSDL3_ttf -lSDL3_image -lGL gm.s -o gm

/////////////////////////////////////////////////////////////////////////////////
.section .rodata

WIDTH = 640
HEIGHT = 640
UPDATE_PERIOD = 16
OBJECTS = 3

.align 16
.local SDL_HINT_VIDEO_DRIVER
.type SDL_HINT_VIDEO_DRIVER, @object
SDL_HINT_VIDEO_DRIVER: .asciz "SDL_VIDEO_DRIVER"

.align 16
.local VIDEO_DRIVERS
.type VIDEO_DRIVERS, @object
VIDEO_DRIVERS: .asciz "wayland,x11"

.align 16
.local EMPTY_STR
.type EMPTY_STR, @object
EMPTY_STR: .zero 1

.align 16
.local FONT
.type FONT, @object
FONT: .asciz "font.ttf"

.align 16
.local OUTPUT_IMAGE
.type OUTPUT_IMAGE, @object
OUTPUT_IMAGE: .asciz "gmout2.png"

.align 16
.local BOOTSTRAP_QUAD_INDICES
.type BOOTSTRAP_QUAD_INDICES, @object
BOOTSTRAP_QUAD_INDICES:
    .float 0.0
    .float 1.0
    .float 3.0
    .float 1.0
    .float 2.0
    .float 3.0
BOOTSTRAP_QUAD_INDICES_SIZE = (. - BOOTSTRAP_QUAD_INDICES)

.align 16
.local UNIFORM_CLIP
.type UNIFORM_CLIP, @object
UNIFORM_CLIP: .asciz "uClip"

.align 16
.local UNIFORM_MODEL
.type UNIFORM_MODEL, @object
UNIFORM_MODEL: .asciz "uModel"

.align 16
.local ENTRY_POINT
.type ENTRY_POINT, @object
ENTRY_POINT: .asciz "main"

#

.align 16
.local TEST_VERTEX
.type TEST_VERTEX, @object
TEST_VERTEX:
    .ascii "#version 460 core\n"
    .ascii "void main() {\n"
    .ascii "gl_Position = vec4(0);\n"
    .ascii "}\n"
    .zero 1

.align 16
.local TEST_FRAGMENT
.type TEST_FRAGMENT, @object
TEST_FRAGMENT:
    .ascii "#version 460 core\n"
    .ascii "out vec4 oColor;\n"
    .ascii "void main() {\n"
    .ascii "oColor = vec4(0);\n"
    .ascii "}\n"
    .zero 1

.align 16
.local DEBUG_LU
.type DEBUG_LU, @object
DEBUG_LU:
    .asciz "%lu\n"
.align 16
.local DEBUG_S
.type DEBUG_S, @object
DEBUG_S:
    .asciz "%s\n"
.align 16
.local DEBUG_F
.type DEBUG_F, @object
DEBUG_F:
    .asciz "%f\n"
.align 16
.local DEBUG_X
.type DEBUG_X, @object
DEBUG_X:
    .asciz "%x\n"
.align 16
.local DEBUG_P
.type DEBUG_p, @object
DEBUG_P:
    .asciz "%p\n"

/////////////////////////////////////////////////////////////////////////////////
.section .bss

.local gFont
.type gFont, @object
.comm gFont, 8, 16

.local gMaxAnisotropy
.type gMaxAnisotropy, @object
.comm gMaxAnisotropy, 4, 16

# pragma pack for structs = no paddings

# typedef enum : byte {TYPE_TEXQUAD, TYPE_LINE} Type; // size = 1

# typedef struct {
#     Type type;
#     GLuint vao, program;
# } Object; // size = 1 + 2 * 4 = 9
.local gObjects
.type gObjects, @object
.comm gObjects, 24, 16 # <Object*>; 8 * 3

# typedef struct {
#     Object; // ms-anon-structure-tag = copies the whole structure
#     GLfloat x, y;
#     GLuint w, h, vbo, ebo, texture;
#     bool clip;
# } Texquad; // size = 9 + 2 * 4 + 5 * 4 + 1 = 38

/////////////////////////////////////////////////////////////////////////////////
.section .text

.macro callxt n # call extern
    call *\n@gotpcrel(%rip)
.endm

.align 16
.type assert, @function
assert: # first parameter int is in the eax for optimization's sake
    endbr64
    testl %eax, %eax
    jnz .Lassert.ret
    callxt abort
.Lassert.ret:
    ret

.align 16
.type captureCanvas, @function
captureCanvas:
    endbr64

    movl $WIDTH, %ebp
    imull $HEIGHT, %ebp # TODO: calculate inside lea instruction directly
    imull $4, %ebp # stack displacement, the result is divisible by 16 already but as we will call smth we need to take additional 8 from any call so for the stack pointer to be 16-aligned we need to add 8
    addl $8, %ebp # also this is an argument for 7th argument, starts at 0(%rsp)
    subq %rbp, %rsp # buffer for pixels, starts at 8(%rsp)

    //
    
    xorl %edi, %edi
    xorl %esi, %esi
    movl $WIDTH, %edx
    movl $HEIGHT, %ecx
    movl $0x1908, %r8d # GL_RGBA
    movl $0x1401, %r9d # GL_UNSIGNED_BYTE
    leaq 8(%rsp), %rax # &buffer{}
    movq %rax, (%rsp) # buffer addr
    callxt glReadPixels

    //
    
    movl $WIDTH, %edi
    movl $HEIGHT, %esi
    movl $0x16762004, %edx # SDL_PIXELFORMAT_RGBA32
    leaq 8(%rsp), %rcx # &buffer{}
    movl $WIDTH, %r8d
    imull $4, %r8d
    callxt SDL_CreateSurfaceFrom
    call assert
    movq %rax, %rbx # SDL_Surface* surface

    movq %rbx, %rdi
    movl $2, %esi # SDL_FLIP_VERTICAL
    callxt SDL_FlipSurface
    call assert

    //

    movq %rbx, %rdi
    leaq OUTPUT_IMAGE(%rip), %rsi
    callxt IMG_SavePNG 
    call assert

    movq %rbx, %rdi
    callxt SDL_DestroySurface
    
    addq %rbp, %rsp
    ret

.align 16
.type bootstrapQuad, @function
bootstrapQuad: # uint* vao, uint* vbo, uint* ebo, uint verticesSize, const float[] vertices
    endbr64

    BOOTSTRAP_QUAD_STACK = 40
    subq $BOOTSTRAP_QUAD_STACK, %rsp # 3 * 8 int* + 4 int + 8 float* + 4 padding

    movq %rdi, (%rsp)
    movq %rsi, 8(%rsp)
    movq %rdx, 16(%rsp)
    movl %ecx, 24(%rsp)
    movq %r8, 28(%rsp)

    //
    
    movl $1, %edi
    movq (%rsp), %rsi
    callxt glCreateVertexArrays
    movq (%rsp), %rax
    movl (%rax), %eax
    call assert

    //
    
    movl $1, %edi
    movq 8(%rsp), %rsi
    callxt glCreateBuffers
    movq 8(%rsp), %rax
    movl (%rax), %eax
    call assert

    movq 8(%rsp), %rdi
    movl (%rdi), %edi
    movl 24(%rsp), %esi
    movq 28(%rsp), %rdx
    xorl %ecx, %ecx
    callxt glNamedBufferStorage

    //

    movl $1, %edi
    movq 16(%rsp), %rsi
    callxt glCreateBuffers
    movq 16(%rsp), %rax
    movl (%rax), %eax
    call assert

    movl 16(%rsp), %edi
    movl $BOOTSTRAP_QUAD_INDICES_SIZE, %esi
    leaq BOOTSTRAP_QUAD_INDICES(%rip), %rdx
    xorl %ecx, %ecx
    callxt glNamedBufferStorage

    movq (%rsp), %rdi
    movl (%rdi), %edi
    movq 16(%rsp), %rsi
    movl (%rsi), %esi
    callxt glVertexArrayElementBuffer

    //
    
    addq $BOOTSTRAP_QUAD_STACK, %rsp
    ret

.align 16
.type makeShaders, @function
makeShaders: # returns uint program; int vertexSize, char* vertex, int fragmentSize, char* fragment
    endbr64

    MAKE_SHADERS_STACK = 40
    subq $MAKE_SHADERS_STACK, %rsp # 2 * 4 int + 2 * 8 char* + 4 * 4 int + another 8 from any call would make rsp be 16-aligned
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
    call assert
    movl %eax, 24(%rsp)

    movl $1, %edi
    leaq 24(%rsp), %rsi
    movl $0x9551, %edx # GL_SHADER_BINARY_FORMAT_SPIR_V
    movq 4(%rsp), %rcx
    movl (%rsp), %r8d
    callxt glShaderBinary

    movl 24(%rsp), %edi
    leaq ENTRY_POINT(%rip), %rsi
    xorl %edx, %edx
    xorq %rcx, %rcx
    xorq %r8, %r8
    callxt glSpecializeShader

    movl 24(%rsp), %edi
    movl $0x8b81, %esi # GL_COMPILE_STATUS
    leaq 36(%rsp), %rdx # 36 - not aligned... can be problematic... - nope;)
    callxt glGetShaderiv
    movl 36(%rsp), %eax
    call assert

    //

    movl $0x8b30, %edi # GL_FRAGMENT_SHADER
    callxt glCreateShader
    call assert
    movl %eax, 28(%rsp)

    movl $1, %edi
    leaq 28(%rsp), %rsi
    movl $0x9551, %edx # GL_SHADER_BINARY_FORMAT_SPIR_V
    movl 16(%rsp), %ecx
    movl 12(%rsp), %r8d
    callxt glShaderBinary

    movl 28(%rsp), %edi
    leaq ENTRY_POINT(%rip), %rsi
    xorl %edx, %edx
    xorq %rcx, %rcx
    xorq %r8, %r8
    callxt glSpecializeShader

    movl 28(%rsp), %edi
    movl $0x8b81, %esi # GL_COMPILE_STATUS
    leaq 36(%rsp), %rdx
    callxt glGetShaderiv
    movl 36(%rsp), %eax
    call assert

    //

    callxt glCreateProgram
    call assert
    movl %eax, 32(%rsp)

    movl 32(%rsp), %edi
    movl 24(%rsp), %esi
    callxt glAttachShader

    movl 32(%rsp), %edi
    movl 28(%rsp), %esi
    callxt glAttachShader

    movl 32(%rsp), %edi
    callxt glLinkProgram

    movl 32(%rsp), %edi
    movl $0x8b82, %esi # GL_LINK_STATUS
    leaq 36(%rsp), %rdx
    callxt glGetProgramiv
    movl 36(%rsp), %eax
    call assert

    //

    movl 32(%rsp), %edi
    callxt glValidateProgram

    movl 32(%rsp), %edi
    movl $0x8b83, %esi # GL_VALIDATE_STATUS
    leaq 36(%rsp), %rdx
    callxt glGetProgramiv
    movl 36(%rsp), %eax
    call assert

    //

    movl 32(%rsp), %edi
    movl 28(%rsp), %esi
    callxt glDetachShader
    movl 28(%rsp), %edi
    callxt glDeleteShader

    movl 32(%rsp), %edi
    movl 24(%rsp), %esi
    callxt glDetachShader
    movl 24(%rsp), %edi
    callxt glDeleteShader

    //

    movl 32(%rsp), %eax # return program
    addq $MAKE_SHADERS_STACK, %rsp
    ret

.align 16
.type createTexquad, @function
createTexquad: # Texquad* texquad, SDL_Surface* nullable surface - is being destroyed here, const float* model
    endbr64

    # 8 texquad + 8 surface + 8 model + 8 any call = 16 aligned
    CREATE_TEXQUAD_STACK = 24
    subq CREATE_TEXQUAD_STACK, %rsp

    movq %rdi, (%rsp)
    movq %rsi, 8(%rsp)
    movq %rdx, 16(%rsp)
    
    //
    
    testq %rsi, %rsi
    jz .LcreateTexquad.bootstrap # surface == null 

    //

    movq (%rsp), %rbp
    addq $33, %rbp # &texquad->texture

    movl $0xde1, %edi # GL_TEXTURE_2D
    movl $1, %esi
    movq %rbp, %rdx
    callxt glCreateTextures
    movl (%rbp), %eax
    call assert

    movl (%rbp), %ebp # texquad->texture

    movl %ebp, %edi
    movl $0x2802, %esi # GL_TEXTURE_WRAP_S
    movl $0x812f, %edx # GL_CLAMP_TO_EDGE
    callxt glTextureParameteri

    movl %ebp, %edi
    movl $0x2803, %esi # GL_TEXTURE_WRAP_T
    movl $0x812f, %edx # GL_CLAMP_TO_EDGE
    callxt glTextureParameteri

    movl %ebp, %edi
    movl $0x2801, %esi # GL_TEXTURE_MIN_FILTER
    movl $0x2703, %edx # GL_LINEAR_MIPMAP_LINEAR
    callxt glTextureParameteri

    movl %ebp, %edi
    movl $0x2800, %esi # GL_TEXTURE_MAG_FILTER
    movl $0x2601, %edx # GL_LINEAR
    callxt glTextureParameteri

    movl %ebp, %edi
    movl $0x84fe, %esi # GL_TEXTURE_MAX_ANISOTROPY_EXT
    movss gMaxAnisotropy(%rip), %xmm0
    callxt glTextureParameteri

    movl %ebp, %edi
    movl $1, %esi
    movl $0x8058, %edx # GL_RGBA8
    movl 8+8(%rsp), %ecx # surface->w
    movl 8+12(%rsp), %r8d # surface->h
    callxt glTextureStorage2D

    movl %ebp, %edi
    xorl %esi, %esi
    xorl %esi, %edx
    xorl %esi, %ecx
    movl 8+8(%rsp), %r8d # surface->w
    movl 8+12(%rsp), %r9d # surface->h
    pushq $24 # surface->pixels # 9th
    pushq $0x1401 # GL_UNSIGNED_BYTE # 8th
    pushq $0x1908 # GL_RGBA # 7th
    callxt glTextureSubImage2D # arguments go on stack in reverse order

    movl %ebp, %edi
    callxt glGenerateTextureMipmap

    movq 8(%rsp), %rdi
    callxt SDL_DestroySurface

.LcreateTexquad.bootstrap:

    pxor %xmm0, %xmm0
    pxor %xmm1, %xmm1

    movq (%rsp), %rdi
    addq $9, %rdi
    pinsrd $0, (%rdi), %xmm0 # texquad->x float
    #
    movq (%rsp), %rsi
    addq $13, %rsi
    pinsrd $1, (%rsi), %xmm0 # texquad->y float
    #
    movq (%rsp), %rdx
    addq $17, %rdx
    pinsrd $0, (%rdx), %xmm1 # texquad->w long starting at the lower 4 bytes of the lower 8 bytes
    #
    movq (%rsp), %rcx
    addq $21, %rcx
    pinsrd $1, (%rcx), %xmm1 # texquad->h long starting at the upper 4 bytes of the lower 8 bytes
    
    cvtdq2ps %xmm1, %xmm1 # convert longwords in xmm1 to single precision floats and store them in xmm1
    addps %xmm0, %xmm1 # sum all floats at once, store them in xmm1

    # TODO: replace movd with vmovsd

    CREATE_TEXQUAD_STACK2 = 80 # also add CREATE_TEXQUAD_STACK from previous allocation
    subq $CREATE_TEXQUAD_STACK2, %rsp # 8 bytes padding to align the vertices themselves + 64 bytes for actual vertices + 8 bytes padding so that a call would add another 8 to complete 16-alignment

    pextrd $0, %xmm1, CREATE_TEXQUAD_STACK+0(%rsp) # x + w
    pextrd $1, %xmm1, CREATE_TEXQUAD_STACK+4(%rsp) # y + h
    movl $0x3f800000, CREATE_TEXQUAD_STACK+8(%rsp) # 1.f
    movl $0x3f800000, CREATE_TEXQUAD_STACK+12(%rsp) # 1.f
    #
    pextrd $0, %xmm1, CREATE_TEXQUAD_STACK+16(%rsp) # x + w
    pextrd $1, %xmm0, CREATE_TEXQUAD_STACK+20(%rsp) # y
    movl $0x3f800000, CREATE_TEXQUAD_STACK+24(%rsp) # 1.f
    movl $0, CREATE_TEXQUAD_STACK+28(%rsp) # 0.f
    #
    pextrd $0, %xmm0, CREATE_TEXQUAD_STACK+32(%rsp) # x
    pextrd $1, %xmm0, CREATE_TEXQUAD_STACK+36(%rsp) # y
    movl $0, CREATE_TEXQUAD_STACK+40(%rsp) # 0.f
    movl $0, CREATE_TEXQUAD_STACK+44(%rsp) # 0.f
    #
    pextrd $0, %xmm0, CREATE_TEXQUAD_STACK+48(%rsp) # x
    pextrd $1, %xmm1, CREATE_TEXQUAD_STACK+52(%rsp) # y + h
    movl $0, CREATE_TEXQUAD_STACK+56(%rsp) # 0.f
    movl $0x3f800000, CREATE_TEXQUAD_STACK+60(%rsp) # 1.f

    movq (%rsp), %rax
    movq %rax, %rdi
    addq $1, %rdi # &texquad->vao
    movq %rax, %rsi
    addq $25, %rsi # &texquad->vbo
    movq %rax, %rdx
    addq $29, %rdx # &texquad->ebo
    movl $64, %ecx # sizeof(vertices)
    leaq CREATE_TEXQUAD_STACK(%rsp), %r8 # &vertices
    call bootstrapQuad

    addq $CREATE_TEXQUAD_STACK2, %rsp # drop vertices

    movq (%rsp), %rax
    movq %rax, %rdi
    addq $1, %rdi
    movl (%rdi), %edi # texquad->vao
    movl %edx, %ebp
    xorl %esi, %esi
    movq %rax, %rdx
    addq $25, %rdx
    movl (%rdx), %edx # texquad->vbo
    xorl %ecx, %ecx
    movl $16, %r8d
    callxt glVertexArrayVertexBuffer
    
    //

    movl %ebp, %edi # texquad->vao
    xorl %esi, %esi
    movl $4, %edx
    movl $0x1406, %ecx # GL_FLOAT
    xorl %r8d, %r8d
    xorl %r9d, %r9d
    callxt glVertexArrayAttribFormat

    movl %ebp, %edi # texquad->vao
    xorl %esi, %esi
    xorl %edx, %edx
    callxt glVertexArrayAttribBinding

    movl %ebp, %edi # texquad->vao
    xorl %esi, %esi
    callxt glEnableVertexArrayAttrib

    //

    # leaq TEXQUAD_VERTEX_SHADER(%rip), %rdi
    leaq TEST_VERTEX(%rip), %rdi
    # leaq TEXQUAD_FRAGMENT_SHADER(%rip), %rsi
    leaq TEST_FRAGMENT(%rip), %rsi
    call makeShaders
    movq (%rsp), %rdi
    addq $5, %rdi # &texquad->program
    movl %eax, (%rdi)
    movl %eax, %ebp # texquad->program

    //

    pxor %xmm0, %xmm0

    movq (%rsp), %rax
    addq $17, %rax
    pinsrd $0, (%rax), %xmm0 # texquad->w
    movq (%rsp), %rax
    addq $21, %rax
    pinsrd $1, (%rax), %xmm0 # texquad->h

    movabs $0x4000000040000000, %rax # two 2.f floats in hex (little endian)
    movq %rax, %xmm1

    cvtdq2ps %xmm0, %xmm0 # convert longwords to floats (4 bytes each)
    divps %xmm1, %xmm0 # wHalf and hHalf are in the 0-64 bits of xmm0

    movq (%rsp), %rax
    addq $9, %rax
    pinsrd $0, (%rax), %xmm1 # texquad->x
    movq (%rsp), %rax
    addq $13, %rax
    pinsrd $1, (%rax), %xmm1 # texquad->y
    
    movb 37(%rsp), %al # texquad->clip
    testb %al, %al
    jnz .LcreateTexquad.useClip # if texquad->clip = true
    pxor %xmm1, %xmm1 # vec4(0.f) in xmm1
    jmp .LcreateTexquad.endClip
.LcreateTexquad.useClip: # TODO: optimize
    addps %xmm0, %xmm1 # texquad->x + wHalf, texquad->y + hHalf in xmm1
    movlhps %xmm0, %xmm1
.LcreateTexquad.endClip:
    
    movl %ebp, %edi # texquad->program
    leaq UNIFORM_CLIP(%rip), %rsi
    callxt glGetUniformLocation

    CREATE_TEXQUAD_STACK3 = 56 # also add CREATE_TEXQUAD_STACK from previous allocation
    subq $CREATE_TEXQUAD_STACK3, %rsp # 24 from previous allocation + 8 alignment + 4 floats + 8 padding + any call = 16-aligned
    movaps %xmm0, CREATE_TEXQUAD_STACK+8(%rsp)

    movl %ebp, %edi # texquad->program
    movl %eax, %esi # clip uniform location
    movl $1, %edx
    leaq CREATE_TEXQUAD_STACK+8(%rsp), %rcx
    callxt glProgramUniform4fv

    addq $CREATE_TEXQUAD_STACK3, %rsp

    //

    movl %ebp, %edi # texquad->program
    leaq UNIFORM_MODEL(%rip), %rsi
    callxt glGetUniformLocation
    
    movl %ebp, %edi # texquad->program
    movl %eax, %esi # model uniform location
    movl $1, %edx
    xorl %ecx, %ecx
    movq 16(%rsp), %r8 # float* model
    callxt glProgramUniformMatrix4fv
    
    addq CREATE_TEXQUAD_STACK, %rsp    
    ret

.align 16
.type render, @function
render:
    endbr64
    nop
    ret

.align 16
.type loop, @function
loop:
    endbr64

    # 8 - window, 128 - event, 8 - ticks, 8 from each call - so additional 8 for 16-alignment
    LOOP_STACK = 152
    subq $LOOP_STACK, %rsp
    # (%rsp) = window, 8(%rsp) = ticks, 16(%rsp) = event
    movq %rdi, (%rsp)

.Lloop.infiniteLoop:
    callxt SDL_GetTicks
    movq %rax, 8(%rsp)

    movl $0x3f800000, %eax # IEEE-754 floating point hex representation (little endian) = 1.f
    movd %eax, %xmm0
    movd %eax, %xmm1
    movd %eax, %xmm2
    movd %eax, %xmm3
    callxt glClearColor

    movl $0x4000, %edi
    callxt glClear

    call render

    movq (%rsp), %rdi
    callxt SDL_GL_SwapWindow
    call assert

.Lloop.eventsLoop:
    leaq 16(%rsp), %rdi
    callxt SDL_PollEvent
    testl %eax, %eax
    jz .Lloop.eventsLoopEnd

    cmpl $0x100, 16(%rsp) # event.type SDL_EVENT_QUIT
    je .Lloop.infiniteLoopEnd

    cmpl $0x300, 16(%rsp) # event.type SDL_EVENT_KEY_DOWN
    jne .Lloop.eventsLoop
    cmpl $0x71, 16+28(%rsp) # event.key.key SDLK_Q
    je .Lloop.infiniteLoopEnd

    jmp .Lloop.eventsLoop

.Lloop.eventsLoopEnd:
    callxt SDL_GetTicks # rax = elapsed
    subq 8(%rsp), %rax
    cmpq $UPDATE_PERIOD, %rax
    ja .Lloop.infiniteLoop

    movl $UPDATE_PERIOD, %edi
    subl %eax, %edi
    callxt SDL_Delay
    jmp .Lloop.infiniteLoop

.Lloop.infiniteLoopEnd:
    addq $LOOP_STACK, %rsp
    ret

.align 16
.type debugCallback, @function
debugCallback:
    endbr64
    # popq %rax # unused 7th argument and to substract 8 from rsp so when the call to printf substract 8 more bytes it will be 16-aligned

    leaq DEBUG_S(%rip), %rdi
    movq %r9, %rsi
    movb $0, %al # zero xmm* registers used
    callxt printf

    ret

.align 16
.type main, @function
.global main
main:
    endbr64
    subq $24, %rsp # 0() window, 8() glContext, 16() padding; 16 + 8 + call = 16-aligned

    leaq SDL_HINT_VIDEO_DRIVER(%rip), %rdi
    leaq VIDEO_DRIVERS(%rip), %rsi
    callxt SDL_SetHint
    call assert

    movl $0x32, %edi # SDL_INIT_VIDEO
    orl $0x4000, %edi # SDL_INIT_EVENTS
    callxt SDL_Init
    call assert

    //

    callxt TTF_Init
    call assert

    leaq FONT(%rip), %rdi
    movl $0x3f800000, %eax # 1.f
    movd %eax, %xmm0
    callxt TTF_OpenFont
    call assert
    movq %rax, gFont(%rip)

    movq gFont(%rip), %rdi
    movl $0x42f00000, %eax # 120.f
    movd %eax, %xmm0
    movl $100, %esi
    movl $100, %edx
    callxt TTF_SetFontSizeDPI
    call assert

    //
    
    movl $17, %edi # SDL_GL_CONTEXT_MAJOR_VERSION
    movl $4, %esi
    callxt SDL_GL_SetAttribute
    call assert
    movl $18, %edi # SDL_GL_CONTEXT_MINOR_VERSION
    movl $6, %esi
    callxt SDL_GL_SetAttribute
    call assert
    movl $20, %edi # SDL_GL_CONTEXT_PROFILE_MASK
    movl $1, %esi # SDL_GL_CONTEXT_PROFILE_CORE
    callxt SDL_GL_SetAttribute
    call assert
    movl $13, %edi # SDL_GL_MULTISAMPLEBUFFERS
    movl $1, %esi
    callxt SDL_GL_SetAttribute
    call assert
    movl $14, %edi # SDL_GL_MULTISAMPLESAMPLES
    movl $4, %esi
    callxt SDL_GL_SetAttribute
    call assert
    movl $15, %edi # SDL_GL_ACCELERATED_VISUAL
    movl $1, %esi
    callxt SDL_GL_SetAttribute
    call assert
    movl $19, %edi # SDL_GL_CONTEXT_FLAGS
    movl $1, %esi # SDL_GL_CONTEXT_DEBUG_FLAG
    callxt SDL_GL_SetAttribute
    call assert

    //
    
    leaq EMPTY_STR(%rip), %rdi
    movl $WIDTH, %esi
    movl $HEIGHT, %edx
    movl $2, %ecx # SDL_WINDOW_OPENGL
    callxt SDL_CreateWindow
    call assert
    movq %rax, (%rsp) # window

    //

    movq (%rsp), %rdi
    callxt SDL_GL_CreateContext
    call assert
    movq %rax, 8(%rsp) # glContext

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
    call assert

    //
    
    movl $0x84ff, %edi # GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT
    leaq gMaxAnisotropy(%rip), %rsi
    callxt glGetFloatv

    //
    
    movq (%rsp), %rdi
    call loop

    //

    leaq 8(%rsp), %rdi # glContext
    callxt SDL_GL_DestroyContext
    call assert

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
    addq $24, %rsp
    ret
