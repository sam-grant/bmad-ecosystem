!+
! subroutine tao_data_show_use(d2_data, lines, nl)
!
! Displays what data is used by the optimizer for the specied d2_data
!
! Input:
!   d2_data	-- tao_d2_data_struct: 
!-

subroutine tao_data_show_use (d2_data, lines, nl)

use tao_mod
use location_encode_mod

implicit none

type (tao_d2_data_struct), intent(in), target :: d2_data
type (tao_d1_data_struct), pointer :: d1

character(17) :: r_name = "tao_data_show_use"
character(n_char_show) line

character(*), optional, allocatable :: lines(:)
integer, optional :: nl

integer i

! print out used data for each name

do i = 1, size(d2_data%d1)

  d1 => d2_data%d1(i)

  call location_encode (line, d1%d%useit_opt, d1%d%exists, lbound(d1%d, 1))
  if (len_trim(line) > len(line) - 60) line = line(1:len(line)-70) // ' ...etc...'

  write (line, '(2x, 2a, i0, a, i0, a, t50, 2a)') trim(tao_d2_d1_name(d1)), &
            '[', lbound(d1%d, 1), ':', ubound(d1%d, 1), ']', 'Using: ', trim(line)

  if (present(lines)) then
    nl=nl+1; lines(nl) = line
  else
    call out_io (s_blank$, r_name, line)
  endif

enddo

end subroutine tao_data_show_use
