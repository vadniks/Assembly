
cmake_minimum_required(VERSION 4.2)
set(CMAKE_C_COMPILER "/usr/bin/clang")
# set(CMAKE_LINKER_TYPE LLD)
project(Gm LANGUAGES C VERSION 0.1)

set(CMAKE_C_STANDARD 23)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS ON)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_executable(${PROJECT_NAME} gm.c)

target_compile_options(${PROJECT_NAME} PUBLIC --save-temps) # output preprocessed, assembly and llvm bitcode
target_compile_options(${PROJECT_NAME} PUBLIC -std=gnu2y)
target_compile_options(${PROJECT_NAME} PUBLIC -Wall -Wextra -Wpedantic -Wabi -Wpsabi)
target_compile_options(${PROJECT_NAME} PUBLIC -Wformat -Wformat=2 -Wconversion -Wimplicit-fallthrough -Werror=format-security -Wstrict-prototypes -Wdeprecated-non-prototype -Wold-style-definition -Wthread-safety)
target_compile_options(${PROJECT_NAME} PUBLIC -O3 -mavx2 -mbmi2 -mrdrnd) # -mavxvnni
target_compile_options(${PROJECT_NAME} PUBLIC -ffast-math -fsemantic-interposition)
target_compile_options(${PROJECT_NAME} PUBLIC -Werror=return-type)
target_link_options(${PROJECT_NAME} PUBLIC -s)
target_compile_options(${PROJECT_NAME} PUBLIC -fvisibility=hidden)
target_compile_options(${PROJECT_NAME} PUBLIC -fstack-protector-all)
target_compile_options(${PROJECT_NAME} PUBLIC -fstack-check)
target_compile_options(${PROJECT_NAME} PUBLIC -fstack-clash-protection)
target_compile_options(${PROJECT_NAME} PUBLIC -fsanitize=undefined)
target_compile_options(${PROJECT_NAME} PUBLIC -fsanitize-trap=all)
target_compile_options(${PROJECT_NAME} PUBLIC -fcf-protection=full)
# -fsanitize=unsigned-integer-overflow
target_compile_options(${PROJECT_NAME} PUBLIC -fsanitize=alignment -fsanitize=bounds -fsanitize=vla-bound -fsanitize=null -fsanitize=object-size -fsanitize=nonnull-attribute -fsanitize=returns-nonnull-attribute -fsanitize=signed-integer-overflow -fsanitize=float-cast-overflow -fsanitize=pointer-overflow -fsanitize=enum -fsanitize=bool)
target_compile_options(${PROJECT_NAME} PUBLIC -fPIE -fpie)
target_compile_options(${PROJECT_NAME} PUBLIC -fno-delete-null-pointer-checks -fno-strict-overflow -fno-strict-aliasing -ftrivial-auto-var-init=zero -Werror=implicit -Werror=incompatible-pointer-types -Werror=int-conversion -fstrict-flex-arrays=3 -fwrapv -fno-delete-null-pointer-checks)
target_compile_options(${PROJECT_NAME} PUBLIC -ftrapv)
target_link_options(${PROJECT_NAME} PUBLIC -pie -Wl,-z,relro -Wl,-z,now -Wl,-z,nodlopen -Wl,-z,noexecstack -Wl,--as-needed -Wl,--no-copy-dt-needed-entries)
target_compile_options(${PROJECT_NAME} PUBLIC -Wno-nullability-extension)
target_compile_options(${PROJECT_NAME} PUBLIC -Wno-nullability-completeness)
target_compile_options(${PROJECT_NAME} PUBLIC -Wno-language-extension-token)
target_compile_options(${PROJECT_NAME} PUBLIC -Wno-gnu-folding-constant)
target_compile_options(${PROJECT_NAME} PUBLIC -Wno-logical-op-parentheses)
target_compile_options(${PROJECT_NAME} PUBLIC -Wno-gnu-pointer-arith)
target_compile_options(${PROJECT_NAME} PUBLIC -Wno-zero-length-array)
target_compile_options(${PROJECT_NAME} PUBLIC -Wno-gnu-empty-struct)
target_compile_options(${PROJECT_NAME} PUBLIC -Wno-gnu-compound-literal-initializer)
#target_compile_options(${PROJECT_NAME} -Wno-gnu-flexible-array-initializer)
target_compile_options(${PROJECT_NAME} PUBLIC -Wno-address-of-packed-member)
target_compile_options(${PROJECT_NAME} PUBLIC -Wno-microsoft-flexible-array)
target_compile_options(${PROJECT_NAME} PUBLIC -Wno-flexible-array-extensions)
target_compile_options(${PROJECT_NAME} PUBLIC -Wno-gnu-variable-sized-type-not-at-end)
target_compile_options(${PROJECT_NAME} PUBLIC -Wno-unknown-pragmas)
target_compile_options(${PROJECT_NAME} PUBLIC -Wno-sign-conversion)
target_compile_options(${PROJECT_NAME} PUBLIC -fms-extensions -Wno-microsoft-anon-tag -Wno-microsoft-string-literal-from-predefined -Wno-auto-decl-extensions)
target_compile_options(${PROJECT_NAME} PUBLIC -fcommon)
target_compile_definitions(${PROJECT_NAME} PUBLIC "-D_GNU_SOURCE -D_THREAD_SAFE -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3")
# target_compile_options(${PROJECT_NAME} -flto=full)
# target_compile_options(${PROJECT_NAME} -fno-fat-lto-objects)
# target_link_options(${PROJECT_NAME} -flto=full)
# target_link_options(${PROJECT_NAME} -fuse-ld=ld.lld)

target_include_directories(${PROJECT_NAME} PUBLIC ./cglm)

target_link_libraries(
    ${PROJECT_NAME}
    c
    m
    SDL3
    SDL3_image
    SDL3_ttf
    /home/admin/Downloads/cglm-0.9.6/build/libcglm.so.0.9.6
    GL
    GLEW
)
