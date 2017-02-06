
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

        HIGH_LIMIT = 1999
        UPPER_BOUND = 2000

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

# void mp1_rtc_tasklet(unsigned long);
#
# Interface: This is a function that updates the state of game
# Inputs: n/a
#   Outputs: this function goes through the linked list of structures and updates
#   the necessary fields.
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

        xorl %esi, %esi                 #decrement the countdown field 
        movw COUNTDOWN(%edx), %si
        decw %si
        movw %si, COUNTDOWN(%edx)
        cmpw $0, %si                    #check if it reaches the end of the list
        jne skip_this_part

        xorl %esi, %esi                 #check the status value
        movw STATUS(%edx), %si
        cmpw $1, %si
        jne field_zero

        xorl %ecx, %ecx                 #if status is one, print OFF_CHAR
        movb OFF_CHAR(%edx), %cl
        xorl %eax, %eax                 #put location in the corresponding Registers
        movw LOCATION(%edx), %ax
        cmpl $0, %eax                   #check if location is in range
        jb skip_this_part
        cmpl $HIGH_LIMIT, %eax
        ja skip_this_part

        shll $1, %eax                   #location*2 to put in the register
        pushl %edx
        call mp1_poke                   #call poke to draw
        popl %edx

        movw $0, STATUS(%edx)           #update status

        xorl %edi, %edi                 #move OFF_LENGTH to countdown field
        movw OFF_LENGTH(%edx), %di
        movw %di, COUNTDOWN(%edx)

        movl NEXT(%edx), %edi           #go to the next structure
        movl %edi, %edx
        jmp next_structure

field_zero:
        xorl %ecx, %ecx                 #if status is one, print ON_CHAR
        movb ON_CHAR(%edx), %cl
        xorl %eax, %eax
        movw LOCATION(%edx), %ax        #get location of current structure
        cmpl $0, %eax                   #check range of location
        jb skip_this_part
        cmpl $HIGH_LIMIT, %eax
        ja skip_this_part

        shll $1, %eax
        pushl %edx
        call mp1_poke                   #draw
        popl %edx

        movw $1, STATUS(%edx)           #update status field

        xorl %edi, %edi                 #update countdown field
        movw ON_LENGTH(%edx), %di
        movw %di, COUNTDOWN(%edx)

skip_this_part:
        movl NEXT(%edx), %edi           #going to next one on the linked list
        movl %edi, %edx
        jmp next_structure

tasklet_end:                            #pop registers and restore frame pointer before return
        popl %edi
        popl %esi
        popl %ebx
        leave
	ret


# void mp1_ioctl(unsigned long arg, unsigned long cmd);
#
# Interface: This is a dispatcher function used to call different subroutines. 
# Inputs: arg: the argument to pass along to sub functions
#         cmd: determine which function to call in ioctl
#   Outputs: Other than jumping to other functions. If cmd is invalid, this function will return -1.

mp1_ioctl:
        movl 8(%esp), %edx              #get cmd from stack and check range
        cmpl $3, %edx                   #check if cmd is within the range of 0 to 3
        jg error_cmd
        cmpl $0, %edx
        jl error_cmd
        jmp *jump_table(,%edx,4)        #jump table used to call functions

error_cmd:
        movl $-1, %eax                  #error condition return
	ret

jump_table:
        .long mp1_ioctl_add, mp1_ioctl_remove, mp1_ioctl_find, mp1_ioctl_sync


# void mp1_ioctl_add(unsigned long arg);
#
# Interface: This is the function that actually draws stuff on the screen.
# Inputs: this function takes a pointer to a user level structure.
#   Outputs: return 0 if the graph was successfully drawn and -1 if not.

mp1_ioctl_add:
        pushl %ebp                      # c calling convention
        movl %esp,%ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl $STRUCT_SIZE, %ebx                  #allocate memory location for new structure
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
        call mp1_copy_from_user         #copy the structure from user space to kernel space
        cmpl $0, %eax                   #check if the copy was successful
        jne copy_fail

        popl %eax
        popl %edx
        popl %ebx

        xorl %edi, %edi
        movw LOCATION(%eax), %di        #get the location from current structure
        cmpl $UPPER_BOUND, %edi
        jae stop_add
        cmpl $0, %edi
        jl stop_add

        xorl %edx, %edx
        movw ON_LENGTH(%eax),%dx        #update countdown from ON_LENGTH
        movw %dx, COUNTDOWN(%eax)
        xorl %edx, %edx
        movw $1, %dx
        movw %dx, STATUS(%eax)          #update status

        #insert the newly allocated structure
        #to the head of the linked list
        movl mp1_list_head, %edi
        movl %edi, NEXT(%eax)
        movl %eax, mp1_list_head

        xorl %ecx, %ecx
        movb ON_CHAR(%eax), %cl         #put ON_CHAR into register in preparation of printing
        xorl %edi, %edi
        movw LOCATION(%eax), %di        #get location

        shll $1, %edi                   #adjust locatoin offset for printing
        movl %edi, %eax
        pushl %edx
        call mp1_poke                   #call poke to print
        popl %edx

        movl $0, %eax                   #successful return
        popl %edi
        popl %esi
        popl %ebx
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
        movl $-1, %eax                  #unsuccessful return
        popl %edi
        popl %esi
        popl %ebx
        leave
        ret
        
# void mp1_ioctl_remove(unsigned long arg);
#
# Interface: This is the function that remove on the structure from linked list.
# Inputs: this function takes an integer location as parameter.
#   Outputs: return 0 if one of the structure in linked list was
# successfully removed and -1 if not.


mp1_ioctl_remove:
        pushl %ebp                      #c calling convention
        movl %esp,%ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl 8(%ebp), %esi #take the user input
        cmpl $UPPER_BOUND, %esi                #check if location was in range
        jae remove_fail
        cmpl $0, %esi
        jl remove_fail

        movl mp1_list_head, %edi        #get the head of the list
        cmpl $0, %edi
        je remove_fail
        movw LOCATION(%edi), %bx        # get location
        cmpw %bx, %si
        je delete_head

        remove_next:
        cmpl $0, %edi                   #validate current structure pointer
        je remove_fail
        movw LOCATION(%edi), %bx        #get location
        cmpw %bx, %si
        je remove_found
        movl %edi, %ecx
        movl NEXT(%edi), %edi           #move on to the next struct
        jmp remove_next

        remove_found:
        #edi is current and ecx is last one
        movl NEXT(%edi), %ebx           #modify linked list
        movl %ebx, NEXT(%ecx)
        movl $0, NEXT(%edi)
        pushl %edi
        call mp1_free                   #free memory
        popl %edi

	movl $0, %eax                  #successful return
        popl %edi
        popl %esi
        popl %ebx
        leave
        ret

        delete_head:
        movl NEXT(%edi), %eax                   #delete the head of linked list
        movl %eax, mp1_list_head
        movl $0, NEXT(%edi)
        pushl %edi
        call mp1_free                           #free memory of deleted structure
        popl %edi

        movl $0, %eax                           #successful return
        popl %edi
        popl %esi
        popl %ebx
        leave
        ret

        remove_fail:                            #unsuccessful return
        movl $-1, %eax
        popl %edi
        popl %esi
        popl %ebx
        leave
        ret
        

# void mp1_ioctl_remove(unsigned long arg);
#
# Interface: This function finds a certain struct and copys to user. 
# Inputs: This function takes a pointer to mp1_blink_struct.
#   Outputs: return 0 if one of the structure in linked list was
# successfully removed and -1 if not.

mp1_ioctl_find:
        pushl %ebp                              #c calling convention
        movl %esp,%ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl 8(%ebp), %edx #take the user input
        cmpl $0, %edx   #verify
        je invalid_structure

        xorl %esi, %esi
        movw LOCATION(%edx), %si                #take location
        cmpl $UPPER_BOUND, %esi                        #check range
        jae invalid_structure
        cmpl $0, %esi
        jl invalid_structure

        movl mp1_list_head, %edi                #get the linked list head

        onto_next_one:
        cmpl $0, %edi
        je invalid_structure
        movw LOCATION(%edi), %bx                #get location
        cmpw %bx, %si                           #check if the current struct matches our struct on location
        je finish_searching
        movl NEXT(%edi), %edi                   #get to the next in the list
        jmp onto_next_one

        finish_searching:
        pushl $STRUCT_SIZE                               #push parameters on the stack prior to the call
        pushl %edi
        pushl %edx
        call mp1_copy_to_user                   #copy from kernel space to user space
        cmpl $0, %eax
        jne copyto_fail                         #check if copy was successful

        popl %edx
        popl %edi
        popl %esi

        movl %edx, %eax                         #return pointer
        popl %edi
        popl %esi
        popl %ebx
        leave
        ret

copyto_fail:
        addl $12, %esp                          #tear down stack (there are 3 registers to pop
invalid_structure:                              # and each register is 3 bytes, that's 12bytes in total)
        movl $-1, %eax                          #unsuccessful return
        popl %edi
        popl %esi
        popl %ebx
        leave
	ret

# void mp1_ioctl_sync(unsigned long arg);
#
# Interface: This function syncronize two existing locations on the screen.
# Inputs: this function takes a 32 bits integer to hold two locations seperately
#   Outputs: return 0 if the graph was successfully synced and -1 if not.


mp1_ioctl_sync:
        pushl %ebp                              #c calling convention
        movl %esp,%ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        xorl %eax, %eax
        movl 8(%ebp), %ebx                      #take the input argument
        movw %bx, %si #%si stores lower bits
        shrl $16, %ebx #%bx stores upper bits   #move 16 bits to move the upper 16 bits to the lower bits position

        movl mp1_list_head, %edi

onto_next1:
        cmpl $0, %edi                           #check if the pointer is valid
        je cant_find
        movw LOCATION(%edi), %cx                #get location

        cmpw %cx, %bx                           #check if the location matches the first input
        je finish_search_first

        movl NEXT(%edi), %edi                   #go to next struct if not
        jmp onto_next1

finish_search_first:
        movl %edi, %eax

        movl mp1_list_head, %edi                #start searching for the second location
 onto_next2:
        cmpl $0, %edi
        je cant_find
        movw LOCATION(%edi), %cx
        
        cmpw %cx, %si                           #get the second struct
        je finish_search_second

        movl NEXT(%edi), %edi
        jmp onto_next2

finish_search_second:
        #eax is first, edi is second

        movw ON_LENGTH(%eax), %cx               #copy over the elements from first struct to second one
        movw %cx, ON_LENGTH(%edi)
        movw OFF_LENGTH(%eax), %cx
        movw %cx, OFF_LENGTH(%edi)
        movw COUNTDOWN(%eax), %cx
        movw %cx, COUNTDOWN(%edi)
        movw STATUS(%eax), %cx
        movw %cx, STATUS(%edi)

        cmpw $0,%cx
        je draw_off

        movb ON_CHAR(%edi), %cl                 #finally get the ON_CHAR ready to draw
        jmp finish_off

draw_off:
        movb OFF_CHAR(%edi), %cl                #draw OFF_CHAR instead if status is 0

finish_off:
        xorl %eax, %eax                         #get the location and call poke to draw
        movw LOCATION(%edi), %ax
        cmpw $UPPER_BOUND, %ax
        jae cant_find
        cmpw $0, %ax
        jl cant_find
        shll $1, %eax
        pushl %edx
        call mp1_poke
        popl %edx

        movl $0, %eax                           #successful return
        popl %edi
        popl %esi
        popl %ebx
        leave
	ret

cant_find:
        movl $-1, %eax                          #unsuccessful return
        popl %edi
        popl %esi
        popl %ebx
        leave
        ret

.end
