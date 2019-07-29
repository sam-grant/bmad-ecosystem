!+
! Subroutine tao_write_cmd (what)
!
! Routine to write output to a file or files or send the output to the printer.
! 
! Input:
!   what -- Character(*): What to output. See the code for more details.
!-

subroutine tao_write_cmd (what)

use tao_interface, dummy => tao_write_cmd
use tao_command_mod, only: tao_cmd_split, tao_next_switch
use tao_plot_mod, only: tao_draw_plots
use tao_top10_mod, only: tao_var_write

use quick_plot, only: qp_open_page, qp_base_library, qp_close_page
use write_lat_file_mod, only: write_lattice_in_foreign_format, write_bmad_lattice_file
use blender_interface_mod, only: write_blender_lat_layout
use madx_ptc_module, only: m_u, m_t, print_universe_pointed, &
                           print_complex_single_structure, print_new_flat, print_universe
use beam_file_io, only: write_beam_file

implicit none

type (tao_curve_array_struct), allocatable, save :: curve(:)
type (tao_curve_struct), pointer :: c
type (tao_plot_struct), pointer :: tp
type (tao_universe_struct), pointer :: u
type (beam_struct), pointer :: beam
type (bunch_struct), pointer :: bunch
type (branch_struct), pointer :: branch
type (ele_pointer_struct), allocatable, save :: eles(:)
type (ele_struct), pointer :: ele
type (coord_struct), pointer :: p
type (lat_nametable_struct) etab
type (tao_d2_data_struct), pointer :: d2
type (tao_d1_data_struct), pointer :: d1
type (tao_data_struct), pointer :: dat
type (tao_v1_var_struct), pointer :: v1

real(rp) scale

character(*) what
character(20) action, name, lat_type, which, last_col
character(200) line, switch, header1, header2
character(200) file_name0, file_name, what2
character(200) :: word(12)
character(*), parameter :: r_name = 'tao_write_cmd'

integer i, j, k, m, n, ie, ix, iu, nd, ii, i_uni, ib, ip, ios, loc
integer i_chan, ix_beam, ix_word, ix_w2, file_format
integer n_type, n_ref, n_start, n_ele, n_merit, n_meas, n_weight, n_good, n_bunch, n_eval, n_s
integer i_min, i_max, n_len

logical is_open, ok, err, good_opt_only, at_switch, new_file, append
logical write_data_source, write_data_type, write_merit_type, write_weight, write_attribute, write_step

!

call string_trim (what, what2, ix)
action = what2(1:ix)
call string_trim(what2(ix+1:), what2, ix_w2)

call tao_cmd_split (what2, 10, word, .true., err)
if (err) return

call match_word (action, [character(20):: &
              'hard', 'gif', 'ps', 'variable', 'bmad_lattice', 'derivative_matrix', 'digested', &
              'curve', 'mad_lattice', 'beam', 'ps-l', 'hard-l', 'covariance_matrix', 'orbit', &
              'mad8_lattice', 'madx_lattice', 'pdf', 'pdf-l', 'opal_lattice', '3d_model', 'gif-l', &
              'plot', 'ptc', 'sad_lattice', 'blender', 'namelist'], ix, .true., matched_name = action)

if (ix == 0) then
  call out_io (s_error$, r_name, 'UNRECOGNIZED "WHAT": ' // action)
  return
elseif (ix < 0) then
  call out_io (s_error$, r_name, 'AMBIGUOUS "WHAT": ' // action)
  return
endif

select case (action)

!---------------------------------------------------
! beam

case ('beam')

  file_format = hdf5$
  is_open = .false.
  at_switch = .false.
  ix_word = 0
  file_name0 = ''

  do 
    ix_word = ix_word + 1
    if (ix_word == size(word)-1) exit

    call tao_next_switch (word(ix_word), [character(8):: '-ascii', '-at', '-binary', '-hdf5'], .true., switch, err, ix)
    if (err) return

    select case (switch)
    case ('');       exit
    case ('-ascii');  file_format = ascii$
    case ('-binary'); file_format = binary$
    case ('-hdf5');   file_format = hdf5$
    case ('-at')
      ix_word = ix_word + 1
      call tao_locate_elements (word(ix_word), s%com%default_universe, eles, err)
      if (err .or. size(eles) == 0) return
      at_switch = .true.
    case default
      if (file_name0 /= '') then
        call out_io (s_error$, r_name, 'EXTRA STUFF ON THE COMMAND LINE. NOTHING DONE.')
        return
      endif
      file_name0 = switch
    end select
  enddo

  if (file_format == hdf5$) then
    if (file_name0 == '') then
      file_name0 = 'beam_#.hdf5'
    else
      n = len_trim(file_name0)
      if (file_name0(n-2:n) /= '.h5' .and. file_name0(n-4:n) /= '.hdf5') then
        file_name0 = trim(file_name0) // '.hdf5'
      endif
    endif

  elseif (file_name0 == '') then
    if (file_format == ascii$) then
      file_name0 = 'beam_#.dat'
    else
      file_name0 = 'beam_#.bin'
    endif
  endif

  if (.not. at_switch) then
    call out_io (s_error$, r_name, 'YOU NEED TO SPECIFY "-at".')
    return
  endif 

  iu = lunget()

  uni_loop: do i = lbound(s%u, 1), ubound(s%u, 1)
    u => s%u(i)

    if (.not. tao_subin_uni_number (file_name0, i, file_name)) return
    call fullfilename (file_name, file_name)
    new_file = .true.

    do ie = 1, size(eles)
      ele => eles(ie)%ele
      ! Write file

      beam => u%uni_branch(ele%ix_branch)%ele(ele%ix_ele)%beam
      if (.not. allocated(beam%bunch)) cycle

      call write_beam_file (file_name, beam, new_file, file_format, u%model%lat)
      new_file = .false.
    enddo 

    if (new_file) then
      call out_io (s_error$, r_name, 'BEAM NOT SAVED AT THIS ELEMENT.', &
                    'CHECK THE SETTING OF THE BEAM_SAVED_AT COMPONENT OF THE TAO_BEAM_INIT NAMELIST.', &
                    'ANOTHER POSSIBILITY IS THAT GLOBAL%TRACK_TYPE = "single" SO NO BEAM TRACKING HAS BEEN DONE.')
    else
      call out_io (s_info$, r_name, 'Written: ' // file_name)
    endif

  enddo uni_loop


!---------------------------------------------------
! 3D model script for Blender
! Note: Old cubit interface code was in tao_write_3d_floor_plan.f90 which was deleted 9/2015.

case ('3d_model', 'blender')

  file_name0 = 'blender_lat_#.py'
  if (word(1) /= '') file_name0 = word(1) 

  if (word(2) /= '') then
    call out_io (s_error$, r_name, 'EXTRA STUFF ON THE COMMAND LINE. NOTHING DONE.')
    return
  endif

  do i = lbound(s%u, 1), ubound(s%u, 1)
    if (.not. tao_subin_uni_number (file_name0, i, file_name)) return
    call write_blender_lat_layout (file_name, s%u(i)%model%lat)
    call out_io (s_info$, r_name, 'Written: ' // file_name)
  enddo

!---------------------------------------------------
! bmad_lattice

case ('bmad_lattice')

  file_format = ascii$
  file_name0 = 'lat_#.bmad'
  ix_word = 0

  do 
    ix_word = ix_word + 1
    if (ix_word == size(word)-1) exit

    call tao_next_switch (word(ix_word), [character(16):: '-binary', '-at'], .true., switch, err, ix)
    if (err) return

    select case (switch)
    case ('');       exit
    case ('-binary'); file_format = binary$
    case default
      if (file_name0 /= 'lat_#.bmad') then
        call out_io (s_error$, r_name, 'EXTRA STUFF ON THE COMMAND LINE. NOTHING DONE.')
        return
      endif
      file_name0 = switch
    end select
  enddo

  do i = lbound(s%u, 1), ubound(s%u, 1)
    if (.not. tao_subin_uni_number (file_name0, i, file_name)) return
    call write_bmad_lattice_file (file_name, s%u(i)%model%lat, err, file_format)
    if (err) return
    call out_io (s_info$, r_name, 'Written: ' // file_name)
  enddo

!---------------------------------------------------
case ('covariance_matrix')

  if (.not. allocated (s%com%covar)) then
    call out_io (s_error$, r_name, 'COVARIANCE MATRIX NOT YET CALCULATED!')
    return
  endif

  file_name = 'lat_#.bmad'
  if (word(1) /= '') file_name = word(1) 

  if (word(2) /= '') then
    call out_io (s_error$, r_name, 'EXTRA STUFF ON THE COMMAND LINE. NOTHING DONE.')
    return
  endif

  call fullfilename (file_name, file_name)

  iu = lunget()
  open (iu, file = file_name)

  write (iu, '(i7, 2x, a)') count(s%var%useit_opt), '! n_var'

  write (iu, *)
  write (iu, *) '! Index   Variable'

  do i = 1, s%n_var_used
    if (.not. s%var(i)%useit_opt) cycle
    write (iu, '(i7, 3x, a)') s%var(i)%ix_dvar, tao_var1_name(s%var(i))
  enddo

  write (iu, *)
  write (iu, *) '!   i     j    Covar_Mat    Alpha_Mat'

  do i = 1, ubound(s%com%covar, 1)
    do j = 1, ubound(s%com%covar, 2)
      write (iu, '(2i6, 2es13.4)') i, j, s%com%covar(i,j), s%com%alpha(i,j)
    enddo
  enddo

  call out_io (s_info$, r_name, 'Written: ' // file_name)
  close(iu)

!---------------------------------------------------
! curve

case ('curve')

  call tao_find_plots (err, word(1), 'BOTH', curve = curve, always_allocate = .true.)
  if (err .or. size(curve) == 0) then
    call out_io (s_error$, r_name, 'CANNOT FIND CURVE')
    return
  endif

  if (size(curve) > 1) then
    call out_io (s_error$, r_name, 'MULTIPLE CURVES FIT NAME')
    return
  endif

  file_name = 'curve'
  if (word(2) /= ' ') file_name = word(2)
  call fullfilename (file_name, file_name)

  c => curve(1)%c
  iu = lunget()
  ok = .false.

  if (c%g%type == "phase_space") then
    i_uni = c%ix_universe
    if (i_uni == 0) i_uni = s%com%default_universe
    beam => s%u(i_uni)%uni_branch(c%ix_branch)%ele(c%ix_ele_ref_track)%beam
    call file_suffixer (file_name, file_name, 'particle_dat', .true.)
    open (iu, file = file_name)
    write (iu, '(a, 6(12x, a))') '  Ix', '  x', 'px', '  y', 'py', '  z', 'pz'
    do i = 1, size(beam%bunch(1)%particle)
      write (iu, '(i6, 6es15.7)') i, (beam%bunch(1)%particle(i)%vec(j), j = 1, 6)
    enddo
    call out_io (s_info$, r_name, 'Written: ' // file_name)
    close(iu)
    ok = .true.
  endif

  if (allocated(c%x_symb) .and. allocated(c%y_symb)) then
    call file_suffixer (file_name, file_name, 'symbol_dat', .true.)
    open (iu, file = file_name)
    write (iu, '(a, 6(12x, a))') '  Ix', '  x', '  y'
    do i = 1, size(c%x_symb)
      write (iu, '(i6, 2es15.7)') i, c%x_symb(i), c%y_symb(i)
    enddo
    call out_io (s_info$, r_name, 'Written: ' // file_name)
    close(iu)
    ok = .true.
  endif

  if (allocated(c%x_line) .and. allocated(c%y_line)) then
    call file_suffixer (file_name, file_name, 'line_dat', .true.)
    open (iu, file = file_name)
    write (iu, '(a, 6(12x, a))') '  Ix', '  x', '  y'
    do i = 1, size(c%x_line)
      write (iu, '(i6, 2es15.7)') i, c%x_line(i), c%y_line(i)
    enddo
    call out_io (s_info$, r_name, 'Written: ' // file_name)
    close(iu)
    ok = .true.
  endif

  if (.not. ok) then
    call out_io (s_info$, r_name, 'No data found in curve to write')
  endif

!---------------------------------------------------
! derivative_matrix

case ('derivative_matrix')

  nd = 0
  do i = lbound(s%u, 1), ubound(s%u, 1)  
    if (.not. s%u(i)%is_on) cycle
    nd = nd + count(s%u(i)%data%useit_opt)
    if (.not. allocated(s%u(i)%dmodel_dvar)) then
      call out_io (s_error$, r_name, 'DERIVATIVE MATRIX NOT YET CALCULATED!')
      return
    endif
  enddo

  file_name = word(1)
  if (file_name == ' ') file_name = 'derivative_matrix.dat'
  call fullfilename (file_name, file_name)

  iu = lunget()
  open (iu, file = file_name)

  write (iu, *) count(s%var%useit_opt), '  ! n_var'
  write (iu, *) nd, '  ! n_data'

  write (iu, *)
  write (iu, *) '! Index   Variable'

  do i = 1, s%n_var_used
    if (.not. s%var(i)%useit_opt) cycle
    write (iu, '(i7, 3x, a)') s%var(i)%ix_dvar, tao_var1_name(s%var(i))
  enddo

  write (iu, *)
  write (iu, *) '! Index   Data'

  do i = lbound(s%u, 1), ubound(s%u, 1)
    if (.not. s%u(i)%is_on) cycle
    do j = 1, size(s%u(i)%data)
      if (.not. s%u(i)%data(j)%useit_opt) cycle
      write (iu, '(i7, 3x, a)') s%u(i)%data(j)%ix_dModel, tao_datum_name(s%u(i)%data(j))
    enddo
  enddo

  write (iu, *)
  write (iu, *) ' ix_dat ix_var  dModel_dVar'
  nd = 0
  do i = lbound(s%u, 1), ubound(s%u, 1)
    if (.not. s%u(i)%is_on) cycle
    do ii = 1, size(s%u(i)%dmodel_dvar, 1)
      do j = 1, size(s%u(i)%dmodel_dvar, 2)
        write (iu, '(2i7, es15.5)') nd + ii, j, s%u(i)%dmodel_dvar(ii, j)
      enddo
    enddo
    nd = nd + count(s%u(i)%data%useit_opt)
  enddo


  call out_io (s_info$, r_name, 'Written: ' // file_name)
  close(iu)

!---------------------------------------------------
! digested

case ('digested')

  file_name0 = word(1)
  if (file_name0 == ' ') file_name0 = 'lat_#.digested'

  do i = lbound(s%u, 1), ubound(s%u, 1)
    if (.not. tao_subin_uni_number (file_name0, i, file_name)) return
    call write_digested_bmad_file (file_name, s%u(i)%model%lat)
    call out_io (s_info$, r_name, 'Written: ' // file_name)
  enddo

!---------------------------------------------------
! hard

case ('hard', 'hard-l')

  if (action == 'hard') then
    call qp_open_page ('PS', scale = 0.0_rp)
  else
    call qp_open_page ('PS-L', scale = 0.0_rp)
  endif
  call tao_draw_plots ()   ! PS out
  call qp_close_page
  call tao_draw_plots ()   ! Update the plotting window

  if (s%global%print_command == ' ') then
    call out_io (s_fatal$, r_name, 'P%PRINT_COMMAND NEEDS TO BE SET TO SEND THE PS FILE TO THE PRINTER!')
    return
  endif

  call system (trim(s%global%print_command) // ' quick_plot.ps')
  call out_io (s_blank$, r_name, 'Printing with command: ' // s%global%print_command)

!---------------------------------------------------
! Foreign lattice format

case ('mad_lattice', 'mad8_lattice', 'madx_lattice', 'opal_latice', 'sad_lattice')

  select case (action)
  case ('mad_lattice');   file_name0 = 'lat_#.mad8'; lat_type = 'MAD-8'
  case ('mad8_lattice');  file_name0 = 'lat_#.mad8'; lat_type = 'MAD-8'
  case ('madx_lattice');  file_name0 = 'lat_#.madX'; lat_type = 'MAD-X'
  case ('opal_latice');   file_name0 = 'lat_#.opal'; lat_type = 'OPAL-T'
  case ('sad_lattice');   file_name0 = 'lat_#.sad';  lat_type = 'SAD'
  end select

  if (word(1) /= '') file_name0 = word(1)

  do i = lbound(s%u, 1), ubound(s%u, 1)
    if (.not. tao_subin_uni_number (file_name0, i, file_name)) return
    call write_lattice_in_foreign_format (lat_type, file_name, s%u(i)%model%lat, &
                                             s%u(i)%model%tao_branch(0)%orbit, err = err)
    if (err) return
    call out_io (s_info$, r_name, 'Written: ' // file_name)
  enddo

!---------------------------------------------------
! orbit

case ('namelist')

  ix_word = 0
  file_name = ''
  which = ''
  append = .false.

  do 
    ix_word = ix_word + 1
    if (ix_word == size(word)-1) exit

    call tao_next_switch (word(ix_word), [character(16):: '-data', '-variable', '-append'], .true., switch, err, ix)
    if (err) return

    select case (switch)
    case ('');                    exit
    case ('-data', '-variable');  which = switch
    case ('-append');             append = .true.
    case default
      if (file_name /= '') then
        call out_io (s_error$, r_name, 'EXTRA STUFF ON THE COMMAND LINE. NOTHING DONE.')
        return
      endif
      file_name = switch
    end select
  enddo

  !

  if (which == '') then
    call out_io (s_error$, r_name, 'WHICH NAMELIST (-data, -variable) NOT SET.')
    return
  endif

  if (file_name == '') file_name = 'tao.namelist'
  iu = lunget()
  if (append) then
    open (iu, file = file_name, access = 'append')
  else
    open (iu, file = file_name)
  endif

  !

  select case (which)
  case ('-data')
    do i = 1, size(s%u)
      u => s%u(i)
      call create_lat_ele_sorted_nametable(u%model%lat, etab)

      do j = 1, u%n_d2_data_used
        d2 => u%d2_data(j)
        write (iu, *)
        write (iu, '(a)') '!---------------------------------------'
        write (iu, *)
        write (iu, '(a)')     '&tao_d2_data'
        write (iu, '(2a)')    '  d2_data%name = ', quote(d2%name)
        write (iu, '(a, i0)') '  universe = ', i
        write (iu, '(a, i0)') '  n_d1_data = ', size(d2%d1)
        write (iu, '(a)')     '/'

        do k = 1, size(d2%d1)
          d1 => d2%d1(k)
          write (iu, *)
          write (iu, '(a)')      '&tao_d1_data'
          write (iu, '(2a)')     '  d1_data%name   = ', quote(d1%name)
          write (iu, '(a, i0)')  '  ix_d1_data     = ', k
          i_min = lbound(d1%d, 1);   i_max = ubound(d1%d, 1)
          write (iu, '(a, i0)')  '  ix_min_data    = ', i_min
          write (iu, '(a, i0)')  '  ix_max_data    = ', i_max

          ! Data output parameter-by-parameter
          if ((all(d1%d%data_type == d1%d(i_min)%data_type) .and. (size(d1%d) > 10)) .or. &
                                                                  maxval(len_trim(d1%d%data_type)) > 30) then
            write_data_source = .true.
            if (all(d1%d%data_source == d1%d(i_min)%data_source)) then
              if (d1%d(i_min)%data_source /= tao_d2_d1_name(d1, .false.)) write (iu, '(2a)') '  default_data_source = ', quote(d1%d(i_min)%data_source)
              write_data_source = .false.
            endif

            write_data_type = .true.
            if (all(d1%d%data_type == d1%d(i_min)%data_type)) then
              write (iu, '(2a)') '  default_data_type = ', quote(d1%d(i_min)%data_type)
              write_data_type = .false.
            endif

            write_merit_type = .true.
            if (all(d1%d%merit_type == 'target')) then
              write_merit_type = .false.
            endif

            write_weight = .true.
            if (all(d1%d%weight == d1%d(i_min)%weight)) then
              write (iu, '(2a)') '  default_weight = ', real_to_string(d1%d(i_min)%weight, 12, 5)
              write_weight = .false.
            endif

            if (write_data_source) call namelist_param_out ('d', 'data_source', i_min, i_max, d1%d%data_source)
            if (write_data_type)   call namelist_param_out ('d', 'data_type', i_min, i_max, d1%d%data_type)
            call namelist_param_out ('d', 'ele_name', i_min, i_max, d1%d%ele_name)
            call namelist_param_out ('d', 'ele_start_name', i_min, i_max, d1%d%ele_start_name, '')
            call namelist_param_out ('d', 'ele_ref_name', i_min, i_max, d1%d%ele_ref_name, '')
            if (write_merit_type)  call namelist_param_out ('d', 'merit_type', i_min, i_max, d1%d%merit_type, '')

            call namelist_param_out ('d', 'meas', i_min, i_max, re_arr = d1%d%meas_value)
            if (write_weight)      call namelist_param_out ('d', 'weight', i_min, i_max, re_arr = d1%d%weight)
            call namelist_param_out ('d', 'good_user', i_min, i_max, logic_arr = d1%d%good_user, logic_dflt = .true.)
            call namelist_param_out ('d', 'eval_point', i_min, i_max, anchor_pt_name(d1%d%eval_point), anchor_pt_name(anchor_end$))
            call namelist_param_out ('d', 's_offset', i_min, i_max, re_arr = d1%d%s_offset, re_dflt = 0.0_rp)
            call namelist_param_out ('d', 'ix_bunch', i_min, i_max, int_arr = d1%d%ix_bunch, int_dflt = 0)

          ! Data output datum-by-datum
          else
            n_type   = max(11, maxval(len_trim(d1%d%data_type)))
            n_ref    = max(11, maxval(len_trim(d1%d%ele_ref_name)))
            n_start  = max(11, maxval(len_trim(d1%d%ele_start_name)))
            n_ele    = max(11, maxval(len_trim(d1%d%ele_name)))
            n_merit  = max(10, maxval(len_trim(d1%d%merit_type)))
            n_meas   = 14
            n_weight = 12
            n_good   = 6
            n_bunch  = 6
            n_eval   = max(8, maxval(len_trim(anchor_pt_name(d1%d%eval_point))))
            n_s      = 12

            last_col = 'merit'
            if (any(d1%d%meas_value /= 0)) last_col = 'meas'
            if (any(d1%d%weight /= 0)) last_col = 'weight'
            if (any(d1%d%good_user .neqv. .true.)) last_col = 'good'
            if (any(d1%d%ix_bunch /= 0)) last_col = 'bunch'
            if (any(d1%d%eval_point /= anchor_end$)) last_col = 'eval'
            if (any(d1%d%s_offset /= 0)) last_col = 's'

            do m = i_min, i_max
              dat => d1%d(m)
              header1 =                  '  !'
              header2 =                  '  !'
              write (line, '(a, i3, a)') '  datum(', m, ') ='
              n_len = len_trim(line) + 1
              call namelist_item_out (header1, header2, line, n_len, n_type,    'data_', 'type', dat%data_type)
              call namelist_item_out (header1, header2, line, n_len, n_ref,     'ele_ref', 'name', dat%ele_ref_name)
              call namelist_item_out (header1, header2, line, n_len, n_start,   'ele_start', 'name', dat%ele_start_name)
              call namelist_item_out (header1, header2, line, n_len, n_ele,     'ele', 'name', dat%ele_name)
              call namelist_item_out (header1, header2, line, n_len, n_merit,   'merit', 'type', dat%merit_type)
              call namelist_item_out (header1, header2, line, n_len, n_meas,    'meas', 'value', re_val = dat%meas_value)
              call namelist_item_out (header1, header2, line, n_len, n_weight,  'weight', '', re_val = dat%weight)
              call namelist_item_out (header1, header2, line, n_len, n_good ,   'good', 'user', logic_val = dat%good_user)
              call namelist_item_out (header1, header2, line, n_len, n_bunch,   'ix', 'bunch', int_val = dat%ix_bunch)
              call namelist_item_out (header1, header2, line, n_len, n_eval,    'eval', 'point', anchor_pt_name(dat%eval_point))
              call namelist_item_out (header1, header2, line, n_len, n_s,       's', 'offset', re_val = dat%s_offset)
            enddo
          endif

          ! spin out

          do m = i_min, i_max
            if (all(d1%d(m)%spin_axis%n0 == 0)) cycle
            write (iu, '(a, i0, a, 3f12.6)') 'datum(', m, ')%spin_n0 = ', (d1%d%spin_axis%n0(1), n = 1, 3)
          enddo

          write (iu, '(a)') '/'

        enddo

      enddo
    enddo

  !

  case ('-variable')

    do i = 1, s%n_var_used
      v1 => s%v1_var(i)
      write (iu, *)
      write (iu, '(a)') '!---------------------------------------'
      write (iu, *)
      write (iu, '(a)')    '&tao_v1_var'
      write (iu, '(2a)')   '  v1_var%name   = ', quote(v1%name)
      i_min = lbound(v1%v, 1);   i_max = ubound(v1%v, 1)
      write (iu, '(a, i0)')  '  ix_min_var    = ', i_min
      write (iu, '(a, i0)')  '  ix_max_var    = ', i_max
      
      write_attribute = .true.
      if (all(v1%v%attrib_name == v1%v(i_min)%attrib_name)) then
        write (iu, '(2a)') '  default_attribute = ', quote(v1%v(i_min)%attrib_name)
        write_attribute = .false.
      endif

      write_step = .true.
      if (all(v1%v%step == v1%v(i_min)%step)) then
        write (iu, '(2a)') '  default_step = ', real_to_string(v1%v(i_min)%step, 12, 5)
        write_step = .false.
      endif

      write_weight = .true.
      if (all(v1%v%weight == v1%v(i_min)%weight)) then
        write (iu, '(2a)') '  default_weight = ', real_to_string(v1%v(i_min)%weight, 12, 5)
        write_weight = .false.
      endif

      call namelist_param_out ('v', 'ele_name', i_min, i_max, v1%v%ele_name)
      if (write_attribute) call namelist_param_out ('v', 'attribute', i_min, i_max, v1%v%attrib_name)
      if (write_weight)    call namelist_param_out ('v', 'weight', i_min, i_max, re_arr = v1%v%weight)
      if (write_step)      call namelist_param_out ('v', 'step', i_min, i_max, re_arr = v1%v%step)
      call namelist_param_out ('v', 'low_lim', i_min, i_max, re_arr = v1%v%low_lim, re_dflt = 0.0_rp)
      call namelist_param_out ('v', 'high_lim', i_min, i_max, re_arr = v1%v%high_lim, re_dflt = 0.0_rp)
      call namelist_param_out ('v', 'merit_type', i_min, i_max, v1%v%merit_type)
      call namelist_param_out ('v', 'good_user', i_min, i_max, logic_arr = v1%v%good_user, logic_dflt = .true.)
      call namelist_param_out ('v', 'key_bound', i_min, i_max, logic_arr = v1%v%key_bound, logic_dflt = .false.)
      call namelist_param_out ('v', 'key_delta', i_min, i_max, re_arr = v1%v%key_delta, re_dflt = 0.0_rp)
    enddo
  end select

!---------------------------------------------------
! orbit

case ('orbit')

  file_name0 = 'orbit.dat'
  i = 0
  do while (i <= size(word))
    i = i + 1
    if (word(i) == '') exit
    call match_word (word(i), &
        ['-beam_index', '-design    ', '-base      '], n, .true., .true., name)
    if (n < 0 .or. (n == 0 .and. word(i)(1:1) == '-')) then
      call out_io (s_error$, r_name, 'AMBIGUOUS SWITCH: ' // word(i))
      return
    endif
    select case (name)
    case ('-beam_index') 
      i=i+1; read (word(i), *, iostat = ios) ix_beam
      if (ios /= 0) then
        call out_io (s_error$, r_name, 'CANNOT READ BEAM INDEX.')
        return
      endif
      action = name
    case ('-design')
      action = name
    case ('-base')
      action = name
    case default
      i=i+1; file_name0 = word(i)
      if (word(i+1) /= '') then
        call out_io (s_error$, r_name, 'EXTRA STUFF ON THE COMMAND LINE. NOTHING DONE.')
        return
      endif
    end select
  enddo

  if (i < size(word)) then
    call out_io (s_error$, r_name, 'EXTRA STUFF ON THE COMMAND LINE. NOTHING DONE.')
    return
  endif

  !

  u => tao_pointer_to_universe (-1) 

  iu = lunget()
  open (iu, file = file_name0)

  write (iu, '(a)') '&particle_orbit'

  do i = 0, u%model%lat%n_ele_track
    select case (action)
    case ('-beam_index')       
    case ('-design')
    case ('-base')
    end select
  enddo

  write (iu, '(a)') '/'
  close (iu)
  call out_io (s_info$, r_name, 'Written: ' // file_name)

!---------------------------------------------------
! plot

case ('plot')

  file_name0 = 'tao_plot.init'
  if (word(1) /= '') file_name0 = word(1) 

  if (word(2) /= '') then
    call out_io (s_error$, r_name, 'EXTRA STUFF ON THE COMMAND LINE. NOTHING DONE.')
    return
  endif

  !

  iu = lunget()
  open (iu, file = file_name0)

  do i = 1, size(s%plot_page%template)
    tp => s%plot_page%template(i)
    if (tp%name == '') cycle


  enddo

  close (iu)
  call out_io (s_info$, r_name, 'Written: ' // file_name0)

!---------------------------------------------------
! ps

case ('ps', 'ps-l', 'gif', 'gif-l', 'pdf', 'pdf-l')

  if (qp_base_library == 'PGPLOT' .and. action(1:3) == 'pdf') then
    call out_io (s_error$, r_name, 'PGPLOT DOES NOT SUPPORT PDF!')
    return
  endif

  ix_word = 0
  scale = 0
  file_name = ''

  do
    ix_word = ix_word + 1
    if (ix_word == size(word)-1) exit

    call tao_next_switch (word(ix_word), ['-scale'], .true., switch, err, ix)
    if (err) return

    select case (switch)
    case ('');  exit
    case ('-scale')
      ix_word = ix_word + 1
      read (word(ix_word), *, iostat = ios) scale
      if (ios /= 0 .or. word(ix_word) == '') then
        call out_io (s_error$, r_name, 'BAD SCALE NUMBER.')
        return
      endif
    case default
      if (file_name /= '') then
        call out_io (s_error$, r_name, 'EXTRA STUFF ON THE COMMAND LINE. NOTHING DONE.')
        return
      endif
      file_name = switch
    end select
  enddo

  if (word(ix_word) /= '') then
    file_name = word(ix_word)
    if (word(ix_word+1) /= '' .or. file_name(1:1) == '-') then
      call out_io (s_error$, r_name, 'EXTRA STUFF ON THE COMMAND LINE. NOTHING DONE.')
      return
    endif
  endif

  if (file_name == '') then
    file_name = "tao.ps"
    if (action(1:3) == 'gif') file_name = 'tao.gif'
    if (action(1:3) == 'pdf') file_name = 'tao.pdf'
  endif

  call str_upcase (action, action)

  if (action(1:3) == 'GIF') then
    call qp_open_page (action, plot_file = file_name, x_len = s%plot_page%size(1), y_len = s%plot_page%size(2), &
                                                                                    units = 'POINTS', scale = scale)
  else
    call qp_open_page (action, plot_file = file_name, scale = scale)
  endif
  call tao_draw_plots (.false.)   ! GIF plot
  call qp_close_page

  call tao_draw_plots ()   ! Update the plotting window

  call out_io (s_blank$, r_name, "Created " // trim(action) // " file: " // file_name)

!---------------------------------------------------
! ptc

case ('ptc')

  which = '-new'
  u => tao_pointer_to_universe(-1)
  branch => u%model%lat%branch(0)
  file_name = ''

  do 
    call tao_next_switch (what2, [character(16):: '-old', '-branch', '-all'], .true., switch, err, ix_w2)
    if (err) return
    if (switch == '') exit

    select case (switch)
    case ('-old', '-all')
      which = switch
    case ('-branch')
      branch => pointer_to_branch (what2(1:ix_w2), u%model%lat)
      if (.not. associated(branch)) then
        call out_io (s_fatal$, r_name, 'Bad branch name or index: ' // what2(:ix_w2))
        return
      endif
    case default
      if (file_name /= '') then
        call out_io (s_error$, r_name, 'EXTRA STUFF ON THE COMMAND LINE. NOTHING DONE.')
        return
      endif
      file_name = switch
    end select
  enddo

  if (file_name == '') file_name = 'ptc.flatfile'

  if (.not. associated(branch%ptc%m_t_layout)) then
    call out_io (s_fatal$, r_name, 'No associated PTC layout exists.', &
                                  'You must use the command "ptc init" before creating a flat file.')
    return
  endif

  select case (which)
  case ('-old')
    call print_complex_single_structure (branch%ptc%m_t_layout, file_name)
    call out_io (s_info$, r_name, 'Written: ' // file_name)

  case ('-new')
    call print_new_flat (branch%ptc%m_t_layout, file_name)
    call out_io (s_info$, r_name, 'Written: ' // file_name)

  case ('-all')
    call print_universe (M_u, trim(file_name) // '.m_u')
    call print_universe_pointed (M_u, M_t, trim(file_name) // '.m_t')
    call out_io (s_info$, r_name, 'Written: ' // trim(file_name) // '.m_u')
    call out_io (s_info$, r_name, 'Written: ' // trim(file_name) // '.m_t')
  end select

!---------------------------------------------------
! variables

case ('variable')

  good_opt_only = .false.
  ix_word = 0
  file_name = ''

  do 
    ix_word = ix_word + 1
    if (ix_word >= size(word)-1) exit
    call tao_next_switch (word(ix_word), ['-good_opt_only'], .true., switch, err, ix)
    if (err) return
    select case (switch)
    case (''); exit
    case ('-good_opt_only'); good_opt_only = .true.
    case default
      if (file_name /= '') then
        call out_io (s_error$, r_name, 'EXTRA STUFF ON THE COMMAND LINE. NOTHING DONE.')
        return
      endif
      file_name = switch
    end select
  enddo  

  if (file_name == '') then
    call tao_var_write (s%global%var_out_file, good_opt_only)
  else
    call tao_var_write (file_name, good_opt_only)
  endif

!---------------------------------------------------
! error

case default

  call out_io (s_error$, r_name, 'UNKNOWN "WHAT": ' // what)

end select

!-----------------------------------------------------------------------------
contains

subroutine namelist_item_out (header1, header2, line, n_len, n_add, h1, h2, str_val, re_val, logic_val, int_val)

real(rp), optional :: re_val
integer, optional :: int_val
integer n_len, n_add
logical, optional :: logic_val
character(*) header1, header2, line, h1, h2
character(*), optional :: str_val
character(n_add) add_str

!

header1 = header1(1:n_len) // h1
header2 = header2(1:n_len) // h1

!

if (present(str_val)) then
  add_str = quote(str_val)
elseif (present(re_val)) then
  add_str = real_to_string(re_val, n_add-1, n_add-9)
elseif (present(logic_val)) then
  write (add_str, '(l2)') logic_val
elseif (present(int_val)) then
  write (add_str, '(i4)') int_val
endif

!

line = line(1:n_len) // add_str
n_len = n_len + n_add

end subroutine namelist_item_out

!-----------------------------------------------------------------------------
! contains

subroutine namelist_param_out (who, name, i_min, i_max, str_arr, str_dflt, re_arr, re_dflt, logic_arr, logic_dflt, int_arr, int_dflt)

integer i_min, i_max

real(rp), optional :: re_arr(i_min:), re_dflt

integer i
integer, optional :: int_arr(i_min:), int_dflt
logical, optional :: logic_arr(i_min:), logic_dflt

character(*) who, name
character(*), optional :: str_arr(i_min:), str_dflt
character(300) out_str(i_min:i_max)
character(200) line


! Encode values

if (present(str_arr)) then
  if (present(str_dflt)) then
    if (all(str_arr == str_dflt)) return
  endif

  do i = i_min, i_max
    out_str(i) = quote(str_arr(i))
  enddo

elseif (present(re_arr)) then
  if (present(re_dflt)) then
    if (all(re_arr == re_dflt)) return
  endif

  do i = i_min, i_max
    out_str(i) = real_to_string(re_arr(i), 15, 8)
  enddo

elseif (present(logic_arr)) then
  if (present(logic_dflt)) then
    if (all(logic_arr .eqv. logic_dflt)) return
  endif

  do i = i_min, i_max
    write (out_str(i), '(l1)') logic_arr(i)
  enddo

elseif (present(int_arr)) then
  if (present(int_dflt)) then
    if (all(int_arr == int_dflt)) return
  endif

  do i = i_min, i_max
    write (out_str(i), '(i0)') int_arr(i) 
  enddo
endif

! Write to output
! Note: Using an array multiplyer is not valid for strings.

if (who == 'd') then
  write (line, '(2x, 2(a, i0), 4a)') 'datum(', i_min, ':', i_max, ')%', trim(name), ' = '
else
  write (line, '(2x, 2(a, i0), 4a)') 'var(', i_min, ':', i_max, ')%', trim(name), ' = '
endif

if (all(out_str == out_str(i_min)) .and. .not. present(str_arr)) then
  write (iu, '(a, i0, 2a)') trim(line), i_max-i_min+1, '*', trim(out_str(i_min))
  return
endif

write (iu, '(a)') trim(line)
line = ''

do i = i_min, i_max
  if (line == '') then
    line = out_str(i)
  else
    line = trim(line) // ', ' // out_str(i)
  endif

  if (i == i_max) then
    write (iu, '(6x, a)') trim(line)
    exit
  elseif (len_trim(line) +len_trim(out_str(i+1)) > 100) then
    write (iu, '(6x, a)') trim(line)
    line = ''
  endif
enddo

end subroutine namelist_param_out

end subroutine tao_write_cmd
