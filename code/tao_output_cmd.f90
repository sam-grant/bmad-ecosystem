!+
! Subroutine tao_output_cmd (s, what)
!
! 
! Input:
!   s        -- tao_super_universe_struct
!
!  Output:
!   s        -- tao_super_universe_struct
!-

subroutine tao_output_cmd (s, what)

use tao_mod
use quick_plot

type (tao_super_universe_struct) s

character(*) what
character(16) action
character(20) :: r_name = 'tao_output_cmd'

integer ix

action = what

!

select case (action)

! hard

case ('hard')
  call qp_open_page ('PS')
  call tao_plot_out (s)   ! Update the plotting window
  call qp_close_page
  call qp_select_page (s%plot_page%id_window)  ! Back to X-windows
  call tao_plot_out (s)   ! Update the plotting window
  call out_io (s_info$, r_name, 'Postscript file created: quick_plot.ps')

! ps

case ('ps')
  call qp_open_page ('PS')
  call tao_plot_out (s)   ! Update the plotting window
  call qp_close_page
  call qp_select_page (s%plot_page%id_window)  ! Back to X-windows
  call tao_plot_out (s)   ! Update the plotting window
  call out_io (s_info$, r_name, 'Postscript file created: quick_plot.ps')

  if (s%global%print_command == ' ') then
    call out_io (s_fatal$, r_name, &
        'P%PRINT_COMMAND NEEDS TO BE SET TO SEND THE PS FILE TO THE PRINTER!')
    return
  endif

  call system (trim(s%global%print_command) // ' quick_plot.ps')
  call out_io (s_blank$, r_name, 'Printing with command: ' // &
                                              s%global%print_command)

! error

case default

  call out_io (s_error$, r_name, 'UNKNOWN "WHAT": ' // what)

end select

end subroutine 
