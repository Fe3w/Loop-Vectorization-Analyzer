	.section	.rodata.cst16,"aM",@progbits,16
	.p2align	4, 0x0                          # -- Begin function f
.LCPI0_0:
	.long	0x3f800000                      # float 1
	.long	0x3f800000                      # float 1
	.long	0x3f800000                      # float 1
	.long	0x3f800000                      # float 1
	.section	.rodata.cst4,"aM",@progbits,4
	.p2align	2, 0x0
.LCPI0_1:
	.long	0x3f800000                      # float 1
	.text
	.globl	f
	.p2align	4
	.type	f,@function
f:                                      # @f
	.cfi_startproc
# %bb.0:
	testl	%edx, %edx
	jle	.LBB0_8
# %bb.1:
	movl	%edx, %eax
	cmpl	$4, %edx
	jae	.LBB0_3
# %bb.2:
	xorl	%ecx, %ecx
	jmp	.LBB0_6
.LBB0_3:
	movl	%eax, %ecx
	andl	$2147483644, %ecx               # imm = 0x7FFFFFFC
	movl	%eax, %edx
	shrl	$2, %edx
	andl	$536870911, %edx                # imm = 0x1FFFFFFF
	shlq	$4, %rdx
	xorl	%r8d, %r8d
	movaps	.LCPI0_0(%rip), %xmm0           # xmm0 = [1.0E+0,1.0E+0,1.0E+0,1.0E+0]
	.p2align	4
.LBB0_4:                                # =>This Inner Loop Header: Depth=1
	movups	(%rsi,%r8), %xmm1
	addps	%xmm0, %xmm1
	movups	%xmm1, (%rdi,%r8)
	addq	$16, %r8
	cmpq	%r8, %rdx
	jne	.LBB0_4
# %bb.5:
	cmpl	%eax, %ecx
	je	.LBB0_8
.LBB0_6:
	movss	.LCPI0_1(%rip), %xmm0           # xmm0 = [1.0E+0,0.0E+0,0.0E+0,0.0E+0]
	.p2align	4
.LBB0_7:                                # =>This Inner Loop Header: Depth=1
	movss	(%rsi,%rcx,4), %xmm1            # xmm1 = mem[0],zero,zero,zero
	addss	%xmm0, %xmm1
	movss	%xmm1, (%rdi,%rcx,4)
	incq	%rcx
	cmpq	%rcx, %rax
	jne	.LBB0_7
.LBB0_8:
	retq
.Lfunc_end0:
	.size	f, .Lfunc_end0-f
	.cfi_endproc
                                        # -- End function
	.addrsig
