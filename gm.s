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

DEBUG_S = 0x0a7325 # // %s\n
DEBUG_P = 0x0a7025 # // %p\n
DEBUG_D = 0x0a6425 # // %p\n
DEBUG_F = 0x0a6625 # // %f\n

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
BOOTSTRAP_QUAD_INDICES: .float 0.0, 1.0, 3.0, 1.0, 2.0, 3.0
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
TEST_VERTEX: # TODO: replace with spirv bytecode
    .ascii "#version 460 core\n"
    .ascii "void main() {\n"
    .ascii "gl_Position = vec4(0);\n"
    .ascii "}\n"
    .zero 1
TEST_VERTEX_SIZE = (. - TEST_VERTEX)

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
TEST_FRAGMENT_SIZE = (. - TEST_FRAGMENT)

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

# typedef struct {
#     Object; // ms-anon-structure-tag = copies the whole structure
#     GLfloat x0, y0, x1, y1, width;
# } Line; // size = 9 + 5 * 4 = 29

/////////////////////////////////////////////////////////////////////////////////
.section .text

.macro callxt n # call extern
    call *\n@gotpcrel(%rip)
.endm

.macro xprint f, r, x # // formatString registerInWhichTheValueIs(8 bytes) xmmRegistersUsedCount; pushes/pops 8 bytes
    pushq $\f
    movq %rsp, %rdi
    movq %\r, %rsi
    movb $\x, %al
    callxt printf
    popq %rax
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

    CAPTURE_CANVAS_STACK = WIDTH * HEIGHT * 4 + 8 # // stack alignment and also this is a space for the 7th argument, starts at 0(%rsp)
    subq $CAPTURE_CANVAS_STACK, %rsp # buffer for pixels, starts at 8(%rsp)

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
    leal WIDTH(%edi, %edi, 2), %r8d # // WIDTH + (WIDTH + WIDTH * 2) = WIDTH=edi * 4
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

    addq $CAPTURE_CANVAS_STACK, %rsp
    ret

.align 16
.type bootstrapQuad, @function
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

    # 8 texquad + 8 surface + 8 model + zero padding for stack alignment
    CREATE_TEXQUAD_STACK = 24
    subq CREATE_TEXQUAD_STACK, %rsp

    movq %rdi, (%rsp)
    movq %rsi, 8(%rsp)
    movq %rdx, 16(%rsp)

    //
    
    testq %rsi, %rsi
    jz .LcreateTexquad.bootstrap # // surface == null

    //

    leaq 33(%rsp), %rbp # &texquad->texture

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
    movq 8(%rsp), %rcx
    movl 8(%rcx), %ecx # surface->w
    movq 8(%rsp), %r8
    movl 12(%r8), %r8d  # surface->h
    callxt glTextureStorage2D

    movl %ebp, %edi
    xorl %esi, %esi
    xorl %esi, %edx
    xorl %esi, %ecx
    movq 8(%rsp), %r8
    movl 8(%r8), %r8d # surface->w
    movq 8(%rsp), %r9
    movl 12(%r9), %r9d # surface->h
    subq $8, %rsp # stack alignment // TODO: align the stack everywhere there's any push and more than 6 arguments for a function <--------------------------------------------------------------------
    pushq $24 # // surface->pixels # // 9th
    pushq $0x1401 # // GL_UNSIGNED_BYTE # 8th
    pushq $0x1908 # // GL_RGBA # 7th
    callxt glTextureSubImage2D # // arguments go on stack in reverse order
    addq $32, %rsp # free arguments

    movl %ebp, %edi
    callxt glGenerateTextureMipmap

    movq 8(%rsp), %rdi
    callxt SDL_DestroySurface

.LcreateTexquad.bootstrap:

    pxor %xmm0, %xmm0
    pxor %xmm1, %xmm1

    movq (%rsp), %rdi
    pinsrd $0, 9(%rdi), %xmm0 # texquad->x float
    #
    movq (%rsp), %rsi
    pinsrd $1, 13(%rsi), %xmm0 # texquad->y float
    #
    movq (%rsp), %rdx
    pinsrd $0, 17(%rdx), %xmm1 # texquad->w long starting at the lower 4 bytes of the lower 8 bytes
    #
    movq (%rsp), %rcx
    pinsrd $1, 21(%rcx), %xmm1 # texquad->h long starting at the upper 4 bytes of the lower 8 bytes

    cvtdq2ps %xmm1, %xmm1 # convert longwords in xmm1 to single precision floats and store them in xmm1
    addps %xmm0, %xmm1 # sum all floats at once, store them in xmm1

    # TODO: replace movd with vmovsd

    CREATE_TEXQUAD_STACK2 = 64 # // also add CREATE_TEXQUAD_STACK from previous allocation
    subq $CREATE_TEXQUAD_STACK2, %rsp # 64 bytes for actual vertices + zero bytes padding for stack alignment

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

    movq (%rsp), %rdi
    addq $1, %rdi # &texquad->vao
    movq (%rsp), %rsi
    addq $25, %rsi # &texquad->vbo
    movq (%rsp), %rdx
    addq $29, %rdx # &texquad->ebo
    movl $64, %ecx # sizeof(vertices)
    leaq CREATE_TEXQUAD_STACK(%rsp), %r8 # &vertices
    call bootstrapQuad

    addq $CREATE_TEXQUAD_STACK2, %rsp # drop vertices

    movq (%rsp), %rdi
    movl 1(%rdi), %edi # texquad->vao
    movl %edi, %ebp # texquad->vao
    xorl %esi, %esi
    movq (%rsp), %rdx
    movl 25(%rdx), %edx # texquad->vbo
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

    # movl $TEXQUAD_VERTEX_SHADER_SIZE, %edi // <-- TODO: replace with the real ones
    movl $TEST_VERTEX_SIZE, %edi
    # leaq TEXQUAD_VERTEX_SHADER(%rip), %rsi
    leaq TEST_VERTEX(%rip), %rsi
    # movl $TEXQUAD_FRAGMENT_SHADER_SIZE, %edx
    movl $TEST_FRAGMENT_SIZE, %edx
    # leaq TEXQUAD_FRAGMENT_SHADER(%rip), %rcx
    leaq TEST_FRAGMENT(%rip), %rcx
    call makeShaders
    movq (%rsp), %rdi
    movl %eax, 5(%rdi) # &texquad->program
    movl %eax, %ebp # texquad->program

    //

    pxor %xmm0, %xmm0

    movq (%rsp), %rax
    pinsrd $0, 17(%rax), %xmm0 # texquad->w
    movq (%rsp), %rax
    pinsrd $1, 21(%rax), %xmm0 # texquad->h

    movabs $0x4000000040000000, %rax # two 2.f floats in hex (little endian)
    movq %rax, %xmm1

    cvtdq2ps %xmm0, %xmm0 # convert longwords to floats (4 bytes each)
    divps %xmm1, %xmm0 # wHalf and hHalf are in the 0-64 bits of xmm0

    movq (%rsp), %rax
    pinsrd $0, 9(%rax), %xmm1 # texquad->x
    movq (%rsp), %rax
    pinsrd $1, 13(%rax), %xmm1 # texquad->y

    movq (%rsp), %rax
    movb 37(%rax), %al # texquad->clip
    testb %al, %al
    jnz .LcreateTexquad.useClip # // if texquad->clip = true
    pxor %xmm1, %xmm1 # vec4(0.f) in xmm1
    jmp .LcreateTexquad.endClip
.LcreateTexquad.useClip: # TODO: optimize
    addps %xmm0, %xmm1 # texquad->x + wHalf, texquad->y + hHalf in xmm1
    movlhps %xmm0, %xmm1
.LcreateTexquad.endClip:

    movl %ebp, %edi # texquad->program
    leaq UNIFORM_CLIP(%rip), %rsi
    callxt glGetUniformLocation

    CREATE_TEXQUAD_STACK3 = 16 # // also add CREATE_TEXQUAD_STACK from previous allocation
    subq $CREATE_TEXQUAD_STACK3, %rsp # 4 floats + zero padding
    movaps %xmm0, CREATE_TEXQUAD_STACK(%rsp)

    movl %ebp, %edi # texquad->program
    movl %eax, %esi # clip uniform location
    movl $1, %edx
    leaq CREATE_TEXQUAD_STACK(%rsp), %rcx
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

    //

    addq CREATE_TEXQUAD_STACK, %rsp
    ret

.align 16
.type createTexture, @function
createTexture: # return SDL_Surface*; receives: char* imgPathOrText, bool imageOrText
    endbr64

    CREATE_TEXTURE_STACK = 40
    subq $CREATE_TEXTURE_STACK, %rsp # 3 * 8 void* + 4 int + 12 padding for stack alignment
    # 0() imgPathOrText, 8() imageOrText, 12() SDL_Surface* temp, 20() SDL_Surface* converted

    movq %rdi, (%rsp)
    movl %esi, 8(%rsp)
    movq $0, 12(%rsp)
    movq $0, 20(%rsp)

    //

    testl %esi, %esi # if imgOrText
    jz .LcreateTexture.text
    #movq %rdi, %rdi
    callxt IMG_Load
    jmp .LcreateTexture.endCondition
.LcreateTexture.text:
    movq gFont(%rip), %rdi
    movq (%rsp), %rsi
    xorq %rdx, %rdx
    movl $0x7f7f7fff, %ecx # (SDL_Color) {127, 127, 127, 255}
    callxt TTF_RenderText_Blended
.LcreateTexture.endCondition:
    call assert
    movq %rax, 12(%rsp) # temp surface

    //

    movq %rax, %rdi # temp surface
    movl $0x16762004, %esi # SDL_PIXELFORMAT_RGBA32
    callxt SDL_ConvertSurface
    call assert
    movq %rax, 20(%rsp) # converted surface

    movq 12(%rsp), %rdi
    callxt SDL_DestroySurface

    //

    movq 20(%rsp), %rdi
    movl $2, %esi # SDL_FLIP_VERTICAL
    callxt SDL_FlipSurface
    call assert

    //

    movq 20(%rsp), %rax
    addq $CREATE_TEXTURE_STACK, %rsp
    retq

.align 16
.type renderTexquad, @function
renderTexquad: # receives Texquad*
    endbr64
    subq $8, %rsp # stack alignment (cuz inside a caller it's aligned until the call instruction which substructs 8, making the stack misaligned, so we need to substract 8 more bytes to align the stack)
    movq %rdi, %rbp # Texquad*

    //

    #movq %rdi, %rdi
    addq $5, %rdi # &texquad->program
    callxt glUseProgram

    movl $0x0de1, %edi # GL_TEXTURE_2D
    movq %rbp, %rsi
    addq $33, %rsi # &texquad->texture
    callxt glBindTexture

    leaq 1(%rbp), %rdi # &texquad->vao
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

.align 16
.type removeTexquad, @function
removeTexquad: # receives Texquad*
    endbr64
    subq $8, %rsp # stack alignment (aligned -> call -> misaligned -> *align* -> free -> return) and a space for temp array of buffer ids
    movq %rdi, %rbp # Texquad*

    movl $1, %edi
    leaq 33(%rbp), %rsi # &texquad->texture
    callxt glDeleteTextures

    movl 5(%rbp), %edi # texquad->program
    callxt glDeleteProgram

    movl $2, %edi
    movl 29(%rbp), %eax # texquad->ebo
    movl %eax, (%rsp)
    movl 25(%rbp), %eax # texquad->vbo
    movl %eax, 4(%rsp)
    leaq (%rsp), %rsi # (uint[2]) {texquad->ebo, texquad->vbo}
    callxt glDeleteBuffers

    movl $1, %edi
    leaq 1(%rbp), %rsi # &texquad->vao
    callxt glDeleteVertexArrays

    addq $8, %rsp
    ret

.align 16
.type createLine, @object
createLine:
    endbr64
    subq $8, %rsp # stack alignment
    movq %rdi, %rbp # Line*

    movl $1, %edi
    leal 1(%rbp), %esi # &line->vao
    callxt glGenVertexArrays
    movl 1(%rbp), %eax # line->vao
    call assert

    //

    // TODO: replace with the real ones
    movl $TEST_VERTEX_SIZE, %edi
    leaq TEST_VERTEX(%rip), %rsi
    movl $TEST_FRAGMENT_SIZE, %edx
    leaq TEST_FRAGMENT(%rip), %rcx
    call makeShaders
    movl %eax, 5(%rbp) # line->program

    //

    movl 5(%rbp), %edi # line->program
    xorl %esi, %esi
    movl $1, %edx
    leaq 9(%rbp), %rcx # &line->x0 = &vecor(line->x0, line->y0, line->x1, line->y1)
    callxt glProgramUniform4fv

    movl 5(%rbp), %edi # line->program
    movl $1, %esi
    movss 25(%rbp), %xmm0 # line->width
    callxt glProgramUniform1f

    subq $16, %rsp # space for the vector(4 * floats), no alignment needed
    movl 5(%rbp), %edi # line->program
    movl $2, %esi
    movl $1, %edx
    movl $0, 8+0(%rsp)
    movl $0x3f800000, 8+4(%rsp) # 1.f
    movl $0, 8+8(%rsp)
    movl $0x3f800000, 8+12(%rsp) # 1.f
    leaq 8(%rsp), %rcx # &vector[0]
    callxt glProgramUniform4fv
    addq $16, %rsp # free the vector

    //

    addq $8, %rsp
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

    # 8 - window, 128 - event, 8 - ticks, 8 padding for stack alignment
    LOOP_STACK = 152
    subq $LOOP_STACK, %rsp
    # (%rsp) = window, 8(%rsp) = ticks, 16(%rsp) = event
    movq %rdi, (%rsp)

.Lloop.infiniteLoop:
    callxt SDL_GetTicks
    movq %rax, 8(%rsp)

    movl $0x3f80000, %eax # IEEE-754 floating point hex representation (little endian) = 1.f
    movd %eax, %xmm0
    movd %eax, %xmm1
    movd %eax, %xmm2
    movd %eax, %xmm3
    callxt glClearColor

    movl $0x4000, %edi # GL_COLOR_BUFFER_BIT
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
    callxt SDL_GetTicks # // rax = elapsed
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
    # ignore misalignment
    xprint DEBUG_S r9 0 # // push/pop stack - makes it temporary aligned so we don't have to do it here
    ret

.align 16
.type main, @function
.global main
main:
    endbr64
    MAIN_STACK = 24
    subq $MAIN_STACK, %rsp # 0() window, 8() glContext, 16() padding; rsp initially is not 16-aligned so we need to add extra 8 -> 16 + 8 = 24

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
    addq $MAIN_STACK, %rsp
    ret
