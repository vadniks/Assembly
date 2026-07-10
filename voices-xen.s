// Author: https://github.com/vadniks
// License: GNU GPLv3 - ya really wanna copy/use this? - c'mmon - just why... it's
//          not for production of course... just to laugh;)
// Brief: programming example and a playfull challenge (joke) on topic: artistic
//        description of what is happening inside one's mind, stylized to
//        resemble a computer program error - with correct and realistic behavior
//        which can be completely reproduced programmatically, this time - in x86_64
//        linux/systemV gnu asm assembly language
// Description: print an error to linux system journal via ipc/sockets and
//              self-terminate having risen an abort signal to cause the
//              core dump
//
// as -o voices-xen.o voices-zen.s
// ld -s -pie -z relro -z now -z noexecstack -nostdlib \
//    -o voices-xen voices-xen.o -dynamic-linker \
//    /lib64/ld-linux-x86-64.so.2

// ------------------------------------------------
.section .rodata

.balign 16, 0
ERROR_TEXT:
    .ascii "Error: unable to bootstrap entity 'AdaScorta_rogue_2.1' type=subpersonality "
    .ascii "with the following parameters: seed=0xabcdef insanity=75of100 irascibility=50of100 "
    .ascii "entropy=high psyche=toxic,brazen,bold,straight,fierce,direct,confident,narcissistic,"
    .ascii "cynical,playfull,ringleader,childish,assertive,aggressive,energetic,evil,outgoing,"
    .ascii "performative,cruel,fun,leader,dont-give-a-shit-about-everything-and-everyone "
    .ascii "gender=female age-group=genz origin=ru appearance=feminine,conventionally-beautiful8of10,"
    .ascii "thin,bust3of5 intelligence=smart8of10,math,physics,computers,degree,extreme-abstract-"
    .ascii "thinking,extreme-system-thinking self-esteem=high mood=work-exhausted,unhappy,bored "
    .ascii "attitude=friend-long-time,accusing,provoking,rival,hateful-moderate,deep-darkness,"
    .ascii "embittered taste=sweet,tart,spicy,umamy preferences=gaming,music,sport music=pop,heavy,"
    .ascii "hiphop,classic,covers-remixes complexes=vary,hidden,lonely self-destructive=15of100 "
    .ascii "relationship=friend,strategic,hopeless reciprocity=33of100 attraction=50of100,initially,"
    .ascii "faded love=none,never,impossible traumas=cold-parents,raised-without-father,hatred,"
    .ascii "betrayed,difficult-finance-situation - caused by: NOT_ENOUGH_MEMORY,"
    .ascii "NO_FREE_COMPUTE_CLUSTERS_AVAILABLE - unable to fire up a new emulated instance via "
    .ascii "libvirt - the system is likely currently overloaded, aborting...\n"
    .type ERROR_TEXT, @object

// length of actual data without alignment
ERROR_TEXT_LEN = (. - ERROR_TEXT)

.balign 16, 0
SYSLOG_HEADER:
    // KERN_ERR=3
    .ascii "<3> voices-xen: "
    .type SYSLOG_HEADER, @object

// length of actual data without alignment
SYSLOG_HEADER_LEN = (. - SYSLOG_HEADER)

.balign 16, 0
SOCKADDR:
    // struct {unsigned short, byte[14]}, sizeof(...) = 16 bytes
    .word 1
    .ascii "/dev/log"
    .zero 6
    .type SOCKADDR, @object
SOCKADDR_LEN = (. - SOCKADDR)

// ------------------------------------------------
.section .text

.global _start
_start:
    .type _start, @function

    // cet
    endbr64

    // stack pointer alignment and local variable1 pid
    subq $8, %rsp

    # call syslog

    // getpid
    movl $1, %eax
    movl $1, %edi
    movl $0, %esi
    movl $10, %edx
    syscall

    ud2

    // save pid to var1
    movl %eax, (%rsp)

    // kill/raise(pid, sigabrt=6)
    movl $62, %eax
    movl (%rsp), %edi
    movl $6, %esi
    syscall

syslog:
    .type syslog, @function

    // cet
    endbr64

    // calculate how much space we need to allocate all local variables and put it into
    // temporary register, if the intermediate is divisible by 16 - skip addition
    movl $16, %eax
    addl $ERROR_TEXT_LEN, %eax
    addl $SYSLOG_HEADER_LEN, %eax
    testl $15, %eax
    pushfq
    shrl $4, %eax
    popfq
    jz .syslog.noadd1
    addl $1, %eax
.syslog.noadd1:
    shll $4, %eax

    // actually allocate the local stack variables
    // +--------+----------------*----------------+--------------+
    // |   #    |        0       |       1        |       2      |
    // +--------+----------------+----------------+--------------+
    // |  name  | stackAllocated | fileDescriptor | errorMessage |
    // +--------+----------------+----------------+--------------+
    // |  size  |        4       |        4       |   whatever   |
    // +--------+----------------+----------------+--------------+
    // | offset |        0       |        8       |      16      |
    // +--------+----------------+----------------+--------------+
    // | extra  |            alignment            |    aligned   |
    // +--------+---------------------------------+--------------+
    subq %rax, %rsp

    // save stackAllocated into local variable0
    movl %eax, (%rsp)

    // socket(AF_UNIX, SOCK_DGRAM, 0)
    movl $41, %eax
    movl $1, %edi
    movl $2, %esi
    xorl %edx, %edx
    syscall

    // save fileDescriptor
    movl %eax, 8(%rsp)

    // if fileDescriptor is negative - abort
    testl %eax, %eax
    js .syslog.fail

    // connect(fileDescriptor, SOCKADDR, addrlen)
    movl $42, %eax
    movl 8(%rsp), %edi
    leaq SOCKADDR(%rip), %rsi
    movl $SOCKADDR_LEN, %edx
    syscall

    // if result != 0 - abort
    testl %eax, %eax
    jnz .syslog.fail

    // copy SYSLOG_HEADER to errorMessage, even though var1 occupies only 4 bytes,
    // we skip 16 bytes to preserve the alignment of addresses
    movdqa SYSLOG_HEADER(%rip), %xmm0
    movdqa %xmm0, 16(%rsp)

    // get amount of quadwords needed to copy from the ERROR_TEXT_LEN, if it's
    // already divisible by 8 - skip addition
    movl $ERROR_TEXT_LEN, %ecx
    testl $7, %ecx
    pushfq
    shrl $3, %ecx
    popfq
    jz .syslog.noadd2
    addl $1, %ecx
.syslog.noadd2:

    // copy (quadwords) ERROR_TEXT to errorMessage+SYSLOG_HEADER_LEN
    leaq ERROR_TEXT(%rip), %rsi
    leaq 16+SYSLOG_HEADER_LEN(%rsp), %rdi
    cld
    rep movsq

    // write(fileDescriptor, errorMessage, len)=send(..., 0)
    movl $1, %eax
    movl 8(%rsp), %edi
    leaq 16(%rsp), %rsi
    movl $SYSLOG_HEADER_LEN, %edx
    addl $ERROR_TEXT_LEN, %edx
    syscall

    // if result isn't equal to sum of the lengths - abort
    cmpl %eax, %edx
    jne .syslog.fail

    // close(fileDescriptor)
    movl $3, %eax
    movl 8(%rsp), %edi
    syscall

    // if result != 0 - abort
    testl %eax, %eax
    jnz .syslog.fail

    // delete local vars 1,2,0 + stack pointer alignment
    movl (%rsp), %eax
    addq %rax, %rsp

    ret
.syslog.fail:
    ud2
