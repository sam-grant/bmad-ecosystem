!+
! subroutine tao_var_show_use (v1_var, lines, nl)
!
! Displays what variables are used by the optimizer for the specied v1_var
!
! Input:
!   v1_var  -- tao_v1_var_struct
!-

subroutine tao_var_show_use (v1_var, lines, nl)

use tao_mod
use location_encode_mod

implicit none

type (tao_v1_var_struct), intent(in) :: v1_var

character(17) :: r_name = "tao_var_show_use"
character(n_char_show) line

character(*), optional, allocatable :: lines(:)
integer, optional :: nl

! find which variables to use

call location_encode (line, v1_var%v%useit_opt, v1_var%v%exists, lbound(v1_var%v,1))
if (len_trim(line) > len(line) - 60) line = line(1:len(line)-70) // ' ...etc...'
write (line, '(2x, 2a, i0, a, i0, a, t50, 2a)') trim(v1_var%name), &
                      '[', lbound(v1_var%v, 1), ':', ubound(v1_var%v, 1), ']', &
                      'Using: ' // trim(line)

if (present(lines)) then
  nl=nl+1; lines(nl) = line
else
  call out_io (s_blank$, r_name, line)
endif

end subroutine tao_var_show_use
