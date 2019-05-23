program long_term_tracking

use lt_tracking_mod

implicit none

type (ltt_params_struct) lttp
type (lat_struct), target :: lat
type (beam_init_struct) beam_init
type (ptc_map_with_rad_struct) rad_map
type (ltt_internal_struct) ltt_internal

real(rp) del_time

!

call ltt_init_params(lttp, lat, beam_init)
call ltt_init_tracking (lttp, lat, ltt_internal, rad_map)
call ltt_print_inital_info (lttp, rad_map)

call run_timer ('START')

select case (lttp%simulation_mode)
case ('CHECK');  call ltt_run_check_mode(lttp, lat, rad_map, beam_init, ltt_internal)  ! A single turn tracking check
case ('SINGLE'); call ltt_run_single_mode(lttp, lat, beam_init, ltt_internal, rad_map) ! Single particle tracking
case ('BUNCH');  call ltt_run_bunch_mode(lttp, lat, beam_init, ltt_internal, rad_map)  ! Beam tracking
case ('STAT');   call ltt_run_stat_mode(lttp, lat, ltt_internal)                            ! Lattice statistics (radiation integrals, etc.).
case default
  print *, 'BAD SIMULATION_MODE: ' // lttp%simulation_mode
end select

call run_timer ('READ', del_time)
print '(a, f8.2)', 'Tracking time (min)', del_time/60

end program

