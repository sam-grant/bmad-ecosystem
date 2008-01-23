!+
! Subroutine tao_init_single_mode (single_mode_file)
!
! Subroutine to initialize the tao single mode stuff.
! If the single_mode_file is not in the current directory then it will be searched
! for in the directory:
!   TAO_INIT_DIR
!
! Input:
!   single_mode_file -- Character(*): Tao initialization file.

! Output:
!-

subroutine tao_init_single_mode (single_mode_file)

use tao_mod
use tao_input_struct
use tao_init_global_mod

implicit none

type (tao_key_input) key(500)

integer ios, iu, i, j, n, n1, n2, nn, i_max, ix_u, ix, num

character(*) single_mode_file
character(40) :: r_name = 'tao_init_single_mode'
character(200) file_name
character(16) name

logical err
logical, automatic :: unis(ubound(s%u, 1))

namelist / key_bindings / key

! Init lattaces
! read global structure from tao_params namelist
! nu(i) keeps track of the sizes of allocatable pointers in universe s%u(i).

key%ele_name = ' '
key%universe = '*'
key%merit_type = s%global%default_key_merit_type

call tao_open_file ('TAO_INIT_DIR', single_mode_file, iu, file_name)
call out_io (s_blank$, r_name, '*Init: Opening File: ' // file_name)

i_max = 0
n1 = s%n_var_used + 1

read (iu, nml = key_bindings, iostat = ios)
close (iu)

if (ios < 0) then
  call out_io (s_blank$, r_name, 'Init: No key_bindings namelist found')
  allocate (s%key(count(s%var%key_bound)))

elseif (ios > 0) then
  call out_io (s_error$, r_name, 'KEY_BINDINGS NAMELIST READ ERROR.')
  allocate (s%key(count(s%var%key_bound)))

else
  call out_io (s_blank$, r_name, 'Init: Read key_bindings namelist')
  key_loop: do i = 1, size(key)
    if (key(i)%ele_name == ' ') cycle
    i_max = i
    call str_upcase (key(i)%ele_name,    key(i)%ele_name)
    call str_upcase (key(i)%attrib_name, key(i)%attrib_name)
    call str_upcase (key(i)%universe,     key(i)%universe)
    if (key(i)%universe(1:2) == 'U:') key(i)%universe = key(i)%universe(3:)
  enddo key_loop

  ! allocate the key table. 

  allocate (s%key(i_max + count(s%var%key_bound)))
  s%n_var_used = s%n_var_used + i_max
  n2 = s%n_var_used
  s%var(n1:n2)%exists = .false.
  s%key(:) = 0

  do i = 1, i_max

    if (key(i)%ele_name == ' ') cycle
    write (name, *) i
    call string_trim (name, name, ix)
    n = i + n1 - 1
    s%var(n)%ele_name    = key(i)%ele_name
    s%var(n)%attrib_name = key(i)%attrib_name
    s%var(n)%weight      = key(i)%weight
    s%var(n)%step        = key(i)%small_step  
    s%var(n)%high_lim    = key(i)%high_lim
    s%var(n)%low_lim     = key(i)%low_lim
    s%var(n)%good_user   = key(i)%good_opt
    s%var(n)%merit_type  = key(i)%merit_type
    s%var(n)%exists      = .true.
    s%var(n)%key_val0    = s%var(n)%model_value
    s%var(n)%key_delta   = key(i)%delta
    s%var(n)%key_bound   = .true.

    if (key(i)%universe == '*') then
      unis = .true.
    else
      call location_decode (key(i)%universe, unis, 1, num)
      if (num < 0 .or. count(unis) == 0) then
        call out_io (s_abort$, r_name, 'BAD UNIVERSE INDEX FOR KEY: ' // key(i)%ele_name)
        call err_exit
      endif
    endif

    call var_stuffit2 (unis, s%var(n), .false.)
 
    s%key(i) = n

  enddo

  ! setup s%v1_var for the key table

  nn = s%n_v1_var_used + 1
  s%n_v1_var_used = nn
  call tao_point_v1_to_var (s%v1_var(nn), s%var(n1:n2), 1, n1)
  s%v1_var(nn)%name = 'key'
  s%var(n1:n2)%good_opt = .true.

endif

! Put the variables marked by key_bound in the key table.

do i = 1, n1 - 1
  if (.not. s%var(i)%key_bound) cycle
  i_max = i_max + 1
  s%key(i_max) = i
  s%var(i)%key_val0 = s%var(i)%model_value
enddo

end subroutine
