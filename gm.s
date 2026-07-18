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

// --> current: gcc -s -pie -fpie -fomit-frame-pointer -fno-plt -Wl,-z,relro,-z,now -lSDL3 -lSDL3_ttf -lGL gm.s -o gm

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

# typedef struct {
#     Type type;
#     GLuint vao, program;
# } Object;
.local gObjects
.type gObjects, @object
.comm gObjects, 24, 16 # <Object*>; 8 * 3

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
    jnz .assert.ret
    callxt abort
.assert.ret:
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
makeShaders: # returns uint program; char* vertex, char* fragment
    endbr64

    MAKE_SHADERS_STACK = 40
    subq $MAKE_SHADERS_STACK, %rsp # 2 * 8 char* + 4 * 4 int + 8 padding so + another 8 from calls it would be 16-aligned
    # 0() vertex, 8() fragment, 16() vertexShader, 20() fragmentShader, 24() program, 28() success
    
    movq %rdi, (%rsp)
    movq %rsi, 8(%rsp)
    movl $0, 16(%rsp)
    movl $0, 20(%rsp)
    movl $0, 24(%rsp)
    movl $0, 28(%rsp)

    //
    
    movl $0x8b31, %edi # GL_VERTEX_SHADER
    callxt glCreateShader
    call assert
    movl %eax, 16(%rsp)

    movl 16(%rsp), %edi
    movl $1, %esi
    leaq (%rsp), %rdx
    xorl %ecx, %ecx
    callxt glShaderSource

    movl 16(%rsp), %edi
    callxt glCompileShader

    movl 16(%rsp), %edi
    movl $0x8b81, %esi # GL_COMPILE_STATUS
    leaq 28(%rsp), %rdx
    callxt glGetShaderiv
    movl 28(%rsp), %eax
    call assert

    //

    movl $0x8b30, %edi # GL_FRAGMENT_SHADER
    callxt glCreateShader
    call assert
    movl %eax, 20(%rsp)

    movl 20(%rsp), %edi
    movl $1, %esi
    leaq 8(%rsp), %rdx
    xorl %ecx, %ecx
    callxt glShaderSource

    movl 20(%rsp), %edi
    callxt glCompileShader

    movl 20(%rsp), %edi
    movl $0x8b81, %esi # GL_COMPILE_STATUS
    leaq 28(%rsp), %rdx
    callxt glGetShaderiv
    movl 28(%rsp), %eax
    call assert

    //

    callxt glCreateProgram
    call assert
    movl %eax, 24(%rsp)

    movl 24(%rsp), %edi
    movl 16(%rsp), %esi
    callxt glAttachShader

    movl 24(%rsp), %edi
    movl 20(%rsp), %esi
    callxt glAttachShader

    movl 24(%rsp), %edi
    callxt glLinkProgram

    //

    movl 24(%rsp), %edi
    callxt glValidateProgram

    movl 24(%rsp), %edi
    movl $0x8b82, %esi # GL_LINK_STATUS
    leaq 28(%rsp), %rdx
    callxt glGetProgramiv
    movl 28(%rsp), %eax
    call assert

    //

    movl 20(%rsp), %edi
    callxt glDeleteShader
    movl 16(%rsp), %edi
    callxt glDeleteShader

    //

    movl 24(%rsp), %eax # return program
    addq $MAKE_SHADERS_STACK, %rsp
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

    # TODO: debug:
    leaq TEST_VERTEX(%rip), %rdi
    leaq TEST_FRAGMENT(%rip), %rsi
    call makeShaders
    pushq %rax
    leaq DEBUG_LU(%rip), %rdi
    movl %eax, %esi
    movb $0, %al
    callxt printf
    popq %rdi
    callxt glDeleteProgram
    # TODO: :debug

.loop.infiniteLoop:
    callxt SDL_GetTicks
    movq %rax, 8(%rsp)

    movl $0x3f800000, %eax # IEEE-754 floating point hex representation = 1.f
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

.loop.eventsLoop:
    leaq 16(%rsp), %rdi
    callxt SDL_PollEvent
    testl %eax, %eax
    jz .loop.eventsLoopEnd

    cmpl $0x100, 16(%rsp) # event.type SDL_EVENT_QUIT
    je .loop.infiniteLoopEnd

    cmpl $0x300, 16(%rsp) # event.type SDL_EVENT_KEY_DOWN
    jne .loop.eventsLoop
    cmpl $0x71, 16+28(%rsp) # event.key.key SDLK_Q
    je .loop.infiniteLoopEnd

    jmp .loop.eventsLoop

.loop.eventsLoopEnd:
    callxt SDL_GetTicks # rax = elapsed
    subq 8(%rsp), %rax
    cmpq $UPDATE_PERIOD, %rax
    ja .loop.infiniteLoop

    movl $UPDATE_PERIOD, %edi
    subl %eax, %edi
    callxt SDL_Delay
    jmp .loop.infiniteLoop

.loop.infiniteLoopEnd:
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

    # debug:
    leaq VIDEO_DRIVERS(%rip), %r9
    call debugCallback
    #
    movl $135, %eax # personality
    movl $0x0007, %edi # PER_XENIX (stripped)
    orl $0x4000000, %edi # STICKY_TIMEOUTS
    orl $0x1000000, %edi # SHORT_INODE
    syscall
    testl %eax, %eax
    jns .main.personalityOk
    xorl %eax, %eax
    call assert
.main.personalityOk:
    xchgl %eax, %eax
    leaq DEBUG_X(%rip), %rdi
    movl %eax, %esi
    movb $0, %al
    callxt printf
    # :debug

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
