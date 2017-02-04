
.data					# section declaration

        # Useful offset constants for accessing members of a 
        # struct mp1_blink_struct structure
        LOCATION   = 0    
        ON_CHAR    = 2
        OFF_CHAR   = 3 
        ON_LENGTH  = 4
        OFF_LENGTH = 6
        COUNTDOWN  = 8
        STATUS     = 10
        NEXT       = 12

        STRUCT_SIZE = 16

# Pointer to head of list (initialized to NULL)
mp1_list_head:
        .long   0

.text					# section declaration

# Export the function symbol names

.global mp1_rtc_tasklet
.global mp1_ioctl

# void mp1_poke(void);
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX
mp1_poke:
        
	movl    vmem_base_addr(,1),%edx
	movb    %cl,(%edx,%eax,1)
	ret

mp1_rtc_tasklet:
        #store and update frame pointer
        pushl %ebp
        movl %esp,%ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        #assign %edx to the pointer to each structure
        movl mp1_list_head, %edx

next_structure:
        #check head null pointer
        cmpl $0, %edx
        je tasklet_end

        xorl %esi, %esi
        movw COUNTDOWN(%edx), %si
        decw %si
        movw %si, COUNTDOWN(%edx)
        cmpw $0, %si
        jne skip_this_part

        xorl %esi, %esi
        movw STATUS(%edx), %si
        cmpw $1, %si
        jne field_zero

        xorl %ecx, %ecx
        movb OFF_CHAR(%edx), %cl
        xorl %eax, %eax
        movw LOCATION(%edx), %ax
        cmpl $0, %eax
        jb skip_this_part
        cmpl $1999, %eax
        ja skip_this_part

        shll $1, %eax
        pushl %edx
        call mp1_poke
        popl %edx

        movw $0, STATUS(%edx)

        xorl %edi, %edi
        movw OFF_LENGTH(%edx), %di
        movw %di, COUNTDOWN(%edx)

        movl NEXT(%edx), %edi
        movl %edi, %edx
        jmp next_structure

field_zero:
        xorl %ecx, %ecx
        movb ON_CHAR(%edx), %cl
        xorl %eax, %eax
        movw LOCATION(%edx), %ax
        cmpl $0, %eax
        jb skip_this_part
        cmpl $1999, %eax
        ja skip_this_part

        shll $1, %eax
        pushl %edx
        call mp1_poke
        popl %edx

        movw $1, STATUS(%edx)

        xorl %edi, %edi
        movw ON_LENGTH(%edx), %di
        movw %di, COUNTDOWN(%edx)

skip_this_part:
        movl NEXT(%edx), %edi
        movl %edi, %edx
        jmp next_structure

tasklet_end:
        popl %edi
        popl %esi
        popl %ebx
        leave
	ret

mp1_ioctl:
        movl 8(%esp), %edx
        cmpl $3, %edx
        jg error_cmd
        cmpl $0, %edx
        jl error_cmd
        jmp *jump_table(,%edx,4)

error_cmd:
        movl $-1, %eax 
        leave
	ret

jump_table:
        .long mp1_ioctl_add, mp1_ioctl_remove, mp1_ioctl_find, mp1_ioctl_sync



mp1_ioctl_add:
        pushl %ebp
        movl %esp,%ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl $16, %ebx
        pushl %ebx
        call mp1_malloc
        # %eax contains the pointer 
        #to the newly allocated memory address
        #after this
        popl %ebx 

        cmpl $0, %eax
        je add_done

        #get input
        movl 8(%ebp), %edx
        cmpl $0, %edx
        je stop_add

        pushl %ebx
        pushl %edx
        pushl %eax
        call mp1_copy_from_user
        cmpl $0, %eax
        jne copy_fail

        popl %eax
        popl %edx
        popl %ebx

        movw LOCATION(%eax), %di
        cmpl $2000, %edi
        jae stop_add
        cmpl $0, %edi
        jl stop_add

        xorl %edx, %edx
        movw ON_LENGTH(%eax),%dx
        movw %dx, COUNTDOWN(%eax)
        xorl %edx, %edx
        movw $1, %dx
        movw %dx, STATUS(%eax)

        #insert the newly allocated structure
        #to the head of the linked list
        movl mp1_list_head, %edi
        movl %edi, NEXT(%eax)
        movl %eax, mp1_list_head

        xorl %ecx, %ecx
        movb ON_CHAR(%eax), %cl
        xorl %edi, %edi
        movw LOCATION(%eax), %di

        shll $1, %edi
        movl %edi, %eax
        pushl %edx
        call mp1_poke
        popl %edx

        movl $0, %eax
        popl %edi
        popl %esi
        popl %edx
        leave
        ret

copy_fail:
        popl %eax
        popl %edx
        popl %ebx

stop_add:
        #free memory
        pushl %eax
        call mp1_free
        popl %eax

add_done:
        movl $-1, %eax
        popl %edi
        popl %esi
        popl %edx
        leave
        ret
        


mp1_ioctl_remove:
        pushl %ebp
        movl %esp,%ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl 8(%ebp), %esi #take the user input
        cmpl $2000, %esi
        jae remove_fail
        cmpl $0, %esi
        jl remove_fail

        movl mp1_list_head, %edi
        cmpl $0, %edi
        je remove_fail
        movw LOCATION(%edi), %bx
        cmpw %bx, %si
        je delete_head

        remove_next:
        cmpl $0, %edi
        je remove_fail
        movw LOCATION(%edi), %bx
        cmpw %bx, %si
        je remove_found
        movl %edi, %ecx
        movl NEXT(%edi), %edi
        jmp remove_next

        remove_found:
        #edi is current and ecx is last one
        movl NEXT(%edi), %ebx
        movl %ebx, NEXT(%ecx)
        movl $0, NEXT(%edi)
        pushl %edi
        call mp1_free
        popl %edi

	movl $0, %eax
        popl %edi
        popl %esi
        popl %ebx
        leave
        ret

        delete_head:
        movl NEXT(%edi), %eax
        movl %eax, mp1_list_head
        movl $0, NEXT(%edi)
        pushl %edi
        call mp1_free
        popl %edi

        movl $0, %eax
        popl %edi
        popl %esi
        popl %ebx
        leave
        ret

        remove_fail:
        movl $-1, %eax
        popl %edi
        popl %esi
        popl %ebx
        leave
        ret
        
mp1_ioctl_find:
        pushl %ebp
        movl %esp,%ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl 8(%ebp), %edx #take the user input
        cmpl $0, %edx   #verify
        je invalid_structure

        xorl %esi, %esi
        movw LOCATION(%edx), %si
        cmpl $2000, %esi
        jae invalid_structure
        cmpl $0, %esi
        jl invalid_structure

        movl mp1_list_head, %edi

        onto_next_one:
        cmpl $0, %edi
        je invalid_structure
        movw LOCATION(%edi), %bx
        cmpw %bx, %si
        je finish_searching
        movl NEXT(%edi), %edi
        jmp onto_next_one

        finish_searching:
        pushl $16
        pushl %edi
        pushl %edx
        call mp1_copy_to_user
        cmpl $0, %eax
        jne copyto_fail

        popl %edx
        popl %edi
        popl %esi

        movl %edx, %eax
        popl %edi
        popl %esi
        popl %ebx
        leave
        ret

copyto_fail:
        addl $12, %esp
invalid_structure:
        movl $-1, %eax
        popl %edi
        popl %esi
        popl %ebx
        leave
	ret



mp1_ioctl_sync:
        pushl %ebp
        movl %esp,%ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        xorl %eax, %eax
        movl 8(%ebp), %ebx
        movw %bx, %si #%si stores lower bits
        shrl $16, %ebx #%bx stores upper bits

        movl mp1_list_head, %edi

onto_next1:
        cmpl $0, %edi
        je cant_find
        movw LOCATION(%edi), %cx

        cmpw %cx, %bx
        je finish_search_first

        movl NEXT(%edi), %edi
        jmp onto_next1

finish_search_first:
        movl %edi, %eax

        movl mp1_list_head, %edi
 onto_next2:
        cmpl $0, %edi
        je cant_find
        movw LOCATION(%edi), %cx
        
        cmpw %cx, %si
        je finish_search_second

        movl NEXT(%edi), %edi
        jmp onto_next2

finish_search_second:
        #eax is first, edi is second

        movw ON_LENGTH(%eax), %cx
        movw %cx, ON_LENGTH(%edi)
        movw OFF_LENGTH(%eax), %cx
        movw %cx, OFF_LENGTH(%edi)
        movw COUNTDOWN(%eax), %cx
        movw %cx, COUNTDOWN(%edi)
        movw STATUS(%eax), %cx
        movw %cx, STATUS(%edi)

        cmpw $0,%cx
        je draw_off

        movb ON_CHAR(%edi), %cl
        jmp finish_off

draw_off:
        movb OFF_CHAR(%edi), %cl

finish_off:
        xorl %eax, %eax
        movw LOCATION(%edi), %ax
        cmpw $2000, %ax
        jae cant_find
        cmpw $0, %ax
        jl cant_find
        shll $1, %eax
        pushl %edx
        call mp1_poke
        popl %edx

        movl $0, %eax
        popl %edi
        popl %esi
        popl %ebx
        leave
	ret

cant_find:
        movl $-1, %eax
        popl %edi
        popl %esi
        popl %ebx
        leave
        ret

.end
