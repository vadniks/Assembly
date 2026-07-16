// Copyright (C) 2026 Vadim Nikolaev (https://github.com/vadniks)
// SPDX-License-Identifier: GPL-3.0-only

// THE FILE/PROJECT IS STILL IN DEVELOPMENT (IS BEING PORTED FROM C CODE)

// License: GNU GPLv3 only - this code is not intended for production - only for demonstration/learning purposes.
// GM/gm/gm.s/gm.S - Graphics meme challenge:
//     OpenGL 2D graphics prototype for demonstrating certain computer graphics concepts and their implementations, mathematics,
//     as well as dynamic libraries usage in position independent executables on GNU/Linux x86_64 platforms in GNU Assembly(er), 
//     and x64 Linux assembly (low-level) development/programming techniques, manually rewritten from the C source. This program 
//     is basically a tiny image manipulation program with all the necessary features to create meme-like images via code - the 
//     lowest level possible! The features include: render of various sized textures of different images, text render, 
//     arbitrary lines (size, color, position, width, slope, opacity), texture clipping, antializing, postprocessing effects, 
//     result saving to file with image container encoding.
// Dependencies: GLibC, LibM, SDL3, SDL3_Image, SDL3_TTF, CGLM, GL (OpenGL 4.6 Core), GLEW
// Version: dated July 2026
// Inspired by the book "Learn OpenGL - Graphics Programming" by Joey de Vries, big thanks to him, it's a great book!

// compile: as -o gm.o gm.s
// link: gcc -pie -z relro -z now -o gm gm.o
// compile, link, run: as -o gm.o gm.s && gcc -s -pie -z relro -z now -lSDL3 -lGL -lGLEW -o gm gm.o && ./gm 
// build via ninja
// --> build in one go: gcc -s -pie -fpie -fomit-frame-pointer -fno-plt -Wl,-z,relro,-z,now gm.s -lSDL3 -lGL -lGLEW -o gm
// GLEW appears to be unnecessary in assembly - calling GL dirrectly
// --> current: gcc -s -pie -fpie -fomit-frame-pointer -fno-plt -Wl,-z,relro,-z,now gm.s -lSDL3 -lSDL3_ttf -lGL -o gm

/////////////////////////////////////////////////////////////////////////////////
.section .rodata

WIDTH = 640
HEIGHT = 640
UPDATE_PERIOD = 16
OBJECTS = 3

.align 16
.local SDL_HINT_VIDEO_DRIVER
.type SDL_HINT_VIDEO_DRIVER, @object
SDL_HINT_VIDEO_DRIVER:
    .asciz "SDL_VIDEO_DRIVER"
.align 16
.local VIDEO_DRIVERS
.type VIDEO_DRIVERS, @object
VIDEO_DRIVERS:
    .asciz "wayland,x11"
.align 16
.local EMPTY_STR
.type EMPTY_STR, @object
EMPTY_STR:
    .zero 1
.align 16
.local FONT
.type FONT, @object
FONT:
    .asciz "font.ttf"

#
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

.local gMaxAnisotropy
.type gMaxAnisotropy, @object
.comm gMaxAnisotropy, 4, 16

.local gFont
.type gFont, @object
.comm gFont, 8, 16

/////////////////////////////////////////////////////////////////////////////////
.section .text

.macro callxt n # call extern
    call *\n@gotpcrel(%rip)
.endm

.align 16
.type assert, @function
assert:
    endbr64
    testl %eax, %eax # input is in eax for optimization's sake
    jnz .assert.ret
    callxt abort
.assert.ret:
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
    popq %rax # unused 7th argument

    leaq DEBUG_S(%rip), %rdi
    movq %r9, %rsi
    callxt printf

    ret

.align 16
.type main, @function
.global main
main:
    endbr64
    subq $24, %rsp # 0() window, 8() glContext, 16() padding; 16 + 8 + call = 16-aligned
    xorq %rax, %rax

    #
    # leaq DEBUG_P(%rip), %rdi
    # leaq gMaxAnisotropy(%rip), %rsi
    # callxt printf
    # leaq DEBUG_P(%rip), %rdi
    # leaq gFont(%rip), %rsi
    # callxt printf
    #

    leaq SDL_HINT_VIDEO_DRIVER(%rip), %rdi
    leaq VIDEO_DRIVERS(%rip), %rsi
    callxt SDL_SetHint
    call assert

    movl $0x32, %edi # SDL_INIT_VIDEO
    orl $0x4000, %edi # SDL_INIT_EVENTS
    callxt SDL_Init
    call assert

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

    leaq EMPTY_STR(%rip), %rdi
    movl $WIDTH, %esi
    movl $HEIGHT, %edx
    movl $2, %ecx # SDL_WINDOW_OPENGL
    callxt SDL_CreateWindow
    call assert
    movq %rax, (%rsp) # window

    movq (%rsp), %rdi
    callxt SDL_GL_CreateContext
    call assert
    movq %rax, 8(%rsp) # glContext

    xorl %edi, %edi
    xorl %esi, %esi
    movl $WIDTH, %edx
    movl $HEIGHT, %ecx
    callxt glViewport

    movl $0x92e0, %edi # GL_DEBUG_OUTPUT
    callxt glEnable
    movl $0x8242, %edi # GL_DEBUG_OUTPUT_SYNCHRONOUS
    callxt glEnable
    leaq debugCallback(%rip), %rdi
    callxt glDebugMessageCallback

    movl $0x809d, %edi # GL_MULTISAMPLE
    callxt glEnable
    movl $0x809e, %edi # GL_SAMPLE_ALPHA_TO_COVERAGE
    callxt glEnable

    movl $0xbe2, %edi # GL_BLEND
    callxt glEnable
    movl $0x302, %edi # GL_SRC_ALPHA
    movl $0x303, %esi # GL_ONE_MINUS_SRC_ALPHA
    callxt glBlendFunc

    movl $1, %edi
    callxt SDL_GL_SetSwapInterval
    call assert

    movl $0x84ff, %edi # GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT
    leaq gMaxAnisotropy(%rip), %rsi
    callxt glGetFloatv
    
    movq (%rsp), %rdi
    call loop

    leaq 8(%rsp), %rdi # glContext
    callxt SDL_GL_DestroyContext
    call assert

    movq (%rsp), %rdi # window
    callxt SDL_DestroyWindow

    movq gFont(%rip), %rdi
    callxt TTF_CloseFont
    callxt TTF_Quit

    callxt SDL_Quit

    addq $24, %rsp
    xorl %eax, %eax
    ret
