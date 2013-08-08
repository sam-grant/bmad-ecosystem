module rf_mod

use runge_kutta_mod
use bookkeeper_mod

real(rp), pointer, private :: field_scale, dphi0_ref
type (lat_param_struct), pointer, private :: param_com
type (ele_struct), pointer, private :: ele_com

integer, private, save :: n_loop ! Used for debugging.
logical, private, save :: is_lost

contains

!--------------------------------------------------------------------------------------------
!--------------------------------------------------------------------------------------------
!--------------------------------------------------------------------------------------------
!+
! Subroutine rf_auto_scale_phase_and_amp(ele, param, err_flag, scale_amp, scale_phase)
!
! Routine to set the phase offset and amplitude scale of the accelerating field if
! this field is defined. This routine works on lcavity, rfcavity and e_gun elements.
!
! For e_gun elements there is no phase to calculate and just the field amplitude scalled is cacluated.
!
! The "phase offset" is an addititive constant added to the RF phase so that ele%value(phi0$)
! is truely relative to the max accelerating phase for lcavities and relative to the accelerating
! zero crossing for rfcavities.
!
! The "amplitude scale" is a scaling factor for ele%value(voltage$) and ele%value(gradient$) so 
! that these quantities are reflect the actual on creast acceleration in volts and volts/meter.
!
! The amplitude scaling is done based upon the setting of:
!   Use the scale_amp arg if present.
!   If scale_amp arg is not present: Use ele%branch%lat%rf_auto_scale_amp if associated(ele%branch).
!   If none of the above: Use bmad_com%rf_auto_scale_amp_default.
!
! A similar procedure is used for phase scaling.
!
! All calculations are done with a particle with the energy of the reference particle and 
! with z = 0.
!
! First: With the phase set for maximum acceleration, set the field_scale for the
! correct change in energy:
!     dE = ele%value(gradient$) * ele%value(l$) for lcavity elements.
!        = ele%value(voltage$)                  for rfcavity elements.
!
! Second:
! If the element is an lcavity then the RF phase is set for maximum acceleration.
! If the element is an rfcavity then the RF phase is set for zero acceleration and
! dE/dz will be negative (particles with z > 0 will be deaccelerated).
!
! Note: If |dE| is too small, this routine cannot scale and will do nothing.
!
! Modules needed
!   use rf_mod
!
! Input:
!   ele        -- ele_struct: RF element. Either lcavity or rfcavity.
!     %value(gradient$) -- Accelerating gradient to match to if an lcavity.
!     %value(voltage$)  -- Accelerating voltage to match to if an rfcavity.
!     %lat%rf_auto_scale_phase ! Scale phase? Default if scale_amp is not present. See above.
!     %lat%rf_auto_scale_amp   ! Scale amp?   Default is acale_phase is not present. See above.
!   param      -- lat_param_struct: lattice parameters
!  scale_amp   -- Logical, optional: Scale the amplitude? See above.
!  scale_phase -- Logical, optional: Scale the phase? See above.
!
! Output:
!   ele      -- ele_struct: element with phase and amplitude adjusted. 
!   err_flag -- Logical, Set true if there is an error. False otherwise.
!-

subroutine rf_auto_scale_phase_and_amp(ele, param, err_flag, scale_phase, scale_amp)

use super_recipes_mod
use nr, only: zbrent

implicit none

type (ele_struct), target :: ele
type (lat_param_struct), target :: param
type (coord_struct) orbit0
type (em_field_struct) field1, field2
integer, parameter :: n_sample = 16

real(rp) pz, phi, pz_max, phi_max, e_tot, scale_correct, dE_peak_wanted, dE_cut, E_tol
real(rp) dphi, e_tot_start, pz_plus, pz_minus, b, c, phi_tol, scale_tol, phi_max_old
real(rp) value_saved(num_ele_attrib$), dphi0_ref_original, pz_arr(0:n_sample-1), pz_max1, pz_max2
real(rp) dE_max1, dE_max2, integral, int_tot, int_old, s

integer i, j, tracking_method_saved, num_times_lost, i_max1, i_max2
integer n_pts, n_pts_tot

logical step_up_seen, err_flag, do_scale_phase, do_scale_amp, phase_scale_good, amp_scale_good
logical, optional :: scale_phase, scale_amp

character(28), parameter :: r_name = 'rf_auto_scale_phase_and_amp'

! Check if auto scale is needed.

err_flag = .false.
if (.not. ele%is_on) return

do_scale_phase = bmad_com%rf_auto_scale_phase_default
do_scale_amp   = bmad_com%rf_auto_scale_amp_default
if (associated (ele%branch)) then
  do_scale_phase = ele%branch%lat%rf_auto_scale_phase
  do_scale_amp   = ele%branch%lat%rf_auto_scale_amp
endif
do_scale_phase = logic_option(do_scale_phase, scale_phase)
do_scale_amp   = logic_option(do_scale_amp,   scale_amp)

if (ele%key == e_gun$) then
  do_scale_phase = .false.
endif

if (.not. do_scale_phase .and. .not. do_scale_amp) return

! Init.
! Note: dphi0_ref is set in neg_pz_calc

if (ele%tracking_method == mad$) return

! bmad_standard just needs to set e_tot$, p0c$, and dphi0_ref$

if (ele%tracking_method == bmad_standard$) then
  if (ele%key == lcavity$) then 
    !Set e_tot$ and p0c$ 
    phi = twopi * (ele%value(phi0$) + ele%value(dphi0$)) 
    e_tot = ele%value(e_tot_start$) + &
            ele%value(gradient$) * ele%value(field_scale$) * ele%value(l$) * cos(phi)
    call convert_total_energy_to (e_tot, param%particle, pc = ele%value(p0c$), err_flag = err_flag)
    if (err_flag) return
    ele%value(e_tot$) = e_tot
  endif 
  
  if (absolute_time_tracking(ele) ) then
    ele%value(dphi0_ref$) = -ele%value(rf_frequency$) * ele%value(ref_time_start$)
  else
    ele%value(dphi0_ref$) = 0
  endif
  return
endif


call pointers_to_rf_auto_scale_vars (ele, field_scale, dphi0_ref)
dphi0_ref_original = dphi0_ref

if (.not. associated(field_scale)) then
  call out_io (s_fatal$, r_name, 'CANNOT DETERMINE WHAT TO SCALE. NO FIELD MODE WITH HARMONIC = 1, M = 0', &
                                 'FOR ELEMENT: ' // ele%name)
  if (global_com%exit_on_error) call err_exit ! exit on error.
  return
endif

! Compute Energy gain at peak (zero phase)

ele_com => ele
param_com => param

select case (ele%key)
case (rfcavity$)
  dE_peak_wanted = ele%value(voltage$)
  e_tot_start = ele%value(e_tot$)
case (lcavity$, e_gun$)
  dE_peak_wanted = ele%value(gradient$) * ele%value(l$)
  e_tot_start = ele%value(e_tot_start$)
case default
  call out_io (s_fatal$, r_name, 'CONFUSED ELEMENT TYPE!')
  if (global_com%exit_on_error) call err_exit ! exit on error.
  return
end select

! Auto scale amplitude when dE_peak_wanted is zero or very small is not possible.
! Therefore if dE_peak_wanted is less than dE_cut then do nothing.

if (do_scale_amp) then
  dE_cut = 10 ! eV
  if (abs(dE_peak_wanted) < dE_cut) return
endif

if (field_scale == 0) then
  ! Cannot autophase if not allowed to make the field_scale non-zero.
  if (.not. do_scale_amp) then
    call out_io (s_fatal$, &
            r_name, 'CANNOT AUTO PHASE IF NOT ALLOWED TO MAKE THE FIELD_SCALE NON-ZERO FOR: ' // ele%name)
    if (global_com%exit_on_error) call err_exit ! exit on error.
    return 
  endif
  field_scale = 1  ! Initial guess.
endif

! scale_correct is the correction factor applied to field_scale on each iteration:
!  field_scale(new) = field_scale(old) * scale_correct
! scale_tol is the tolerance for scale_correct.
! scale_tol = E_tol / dE_peak_wanted corresponds to a tolerance in dE_peak_wanted of E_tol. 

E_tol = 0.1 ! eV
scale_tol = max(1d-7, E_tol / dE_peak_wanted) ! tolerance for scale_correct
phi_tol = 1d-5

!------------------------------------------------------
! zero frequency e_gun

if (ele%key == e_gun$) then
  tracking_method_saved = ele%tracking_method
  if (ele%tracking_method == bmad_standard$) ele%tracking_method = runge_kutta$

  do
    pz_max = pz_calc(phi_max, err_flag)
    if (err_flag) return
    scale_correct = dE_peak_wanted / dE_particle(pz_max)
    if (scale_correct > 1000) scale_correct = max(1000.0_rp, scale_correct / 10)
    field_scale = field_scale * scale_correct
    if (abs(scale_correct - 1) < scale_tol) exit
  enddo

  ele%tracking_method = tracking_method_saved
  return
endif

!------------------------------------------------------
! Set error fields to zero

value_saved = ele%value
ele%value(phi0$) = 0
ele%value(dphi0$) = 0
ele%value(phi0_err$) = 0
if (ele%key == lcavity$) ele%value(gradient_err$) = 0

tracking_method_saved = ele%tracking_method
if (ele%tracking_method == bmad_standard$) ele%tracking_method = runge_kutta$

phi_max = dphi0_ref   ! Init guess
if (ele%key == rfcavity$) phi_max = ele%value(dphi0_max$)

phi_max_old = 100 ! Number far from unity

! See if %dphi0_ref and %field_scale are already set correctly.
! If so we can quit.

phase_scale_good = .true.
amp_scale_good = .true. 

pz_max = pz_calc(phi_max, err_flag)
if (err_flag) return

if (.not. is_lost) then
  if (do_scale_phase) then
    pz_plus  = pz_calc(phi_max + 2 * phi_tol, err_flag); if (err_flag) return
    pz_minus = pz_calc(phi_max - 2 * phi_tol, err_flag); if (err_flag) return
    phase_scale_good = (pz_max >= pz_plus .and. pz_max >= pz_minus )
  endif

  if (do_scale_amp) then
    scale_correct = dE_peak_wanted / dE_particle(pz_max) 
    amp_scale_good = (abs(scale_correct - 1) < 2 * scale_tol)
  endif

  if (phase_scale_good .and. amp_scale_good) then
    call cleanup_this()
    dphi0_ref = dphi0_ref_original
    return
  endif
endif

! The field_scale may be orders of magnitude off so do an initial guess
! based upon the integral of abs(voltage) through the element.

if (do_scale_amp) then
  n_pts = 1
  int_tot = 0
  n_pts_tot = 0

  do 
    integral = 0
    do i = 1, n_pts
      s = ele%value(l$) * (2*i - 1.0) / (2*n_pts)
      ! Sample field at two phases and take the max. This is crude but effective.
      dphi0_ref = 0
      call em_field_calc (ele, param, s, 0.0_rp, orbit0, .true., field1)
      dphi0_ref = pi/2
      call em_field_calc (ele, param, s, 0.0_rp, orbit0, .true., field2)
      integral = integral + max(abs(field1%e(3)), abs(field2%e(3))) * ele%value(l$) / n_pts
    enddo

    n_pts_tot = n_pts_tot + n_pts
    int_old = int_tot
    int_tot = ((n_pts_tot - n_pts) * int_tot + n_pts * integral) / n_pts_tot
    if (n_pts_tot > 16) then
      if (abs(int_tot - int_old) < 0.2 * (int_tot + int_old)) then
        field_scale = field_scale * dE_peak_wanted / integral
        exit
      endif
    endif

    n_pts = 2 * n_pts

  enddo
endif

! OK so the input %dphi0_ref or %field_scale are not set correctly...
! First choose a starting phi_max by finding an approximate phase for max acceleration.
! We start by testing n_sample phases.
! pz_max1 gives the maximal acceleration. pz_max2 gives the second largest.

pz_arr(0) = pz_max
dphi = 1.0_rp / n_sample

do i = 1, n_sample - 1
  pz_arr(i) = pz_calc(phi_max + i*dphi, err_flag); if (err_flag) return
enddo

i_max1 = maxloc(pz_arr, 1) - 1
pz_max1 = pz_arr(i_max1)
dE_max1 = dE_particle(pz_max1)

pz_arr(i_max1) = -1  ! To find next max
i_max2 = maxloc(pz_arr, 1) - 1
pz_max2 = pz_arr(i_max2)
dE_max2 = dE_particle(pz_max2)

! If we do not have any phase that shows acceleration this generally means that the
! initial particle energy is low and the field_scale is much to large.

if (dE_max1 < 0) then
  call out_io (s_error$, r_name, 'CANNOT FIND ACCELERATING PHASE REGION FOR: ' // ele%name)
  err_flag = .true.
  return
endif

! If dE_max1 is large compared to dE_max2 then just use the dE_max1 phase. 
! Otherwise take half way between dE_max1 and dE_max2 phases.

if (dE_max2 < dE_max1/2) then  ! Just use dE_max1 point
  phi_max = phi_max + dphi * i_max1
  pz_max = pz_max1
! wrap around case when i_max1 = 0 and i_max2 = n_sample-1 or vice versa.
elseif (abs(i_max1 - i_max2) > n_sample/2) then   
  phi_max = phi_max + dphi * (i_max1 + i_max2 - n_sample) / 2.0
  pz_max = pz_calc(phi_max, err_flag); if (err_flag) return
else
  phi_max = phi_max + dphi * (i_max1 + i_max2) / 2.0
  pz_max = pz_calc(phi_max, err_flag); if (err_flag) return
endif

! Now adjust %field_scale for the correct acceleration at the phase for maximum acceleration. 

n_loop = 0  ! For debug purposes.
num_times_lost = 0
dphi = 0.05

main_loop: do

  ! Find approximately the phase for maximum acceleration.
  ! First go in +phi direction until pz decreases.

  step_up_seen = .false.

  do i = 1, 100
    phi = phi_max + dphi
    pz = pz_calc(phi, err_flag); if (err_flag) return

    if (is_lost) then
      do j = -19, 20
        print *, j, phi_max+j/40.0, pz_calc(phi_max + j / 40.0, err_flag)
      enddo
      call out_io (s_error$, r_name, 'CANNOT STABLY TRACK PARTICLE!')
      err_flag = .true.
      return
    endif

    if (pz < pz_max) then
      pz_plus = pz
      exit
    endif

    pz_minus = pz_max
    pz_max = pz
    phi_max = phi
    step_up_seen = .true.
  enddo

  ! If needed: Now go in -phi direction until pz decreases

  if (.not. step_up_seen) then
    do
      phi = phi_max - dphi
      pz = pz_calc(phi, err_flag); if (err_flag) return
      if (pz < pz_max) then
        pz_minus = pz
        exit
      endif
      pz_plus = pz_max
      pz_max = pz
      phi_max = phi
    enddo
  endif

  ! Quadradic interpolation to get the maximum phase.
  ! Formula: pz = a + b*dt + c*dt^2 where dt = (phi-phi_max) / dphi

  b = (pz_plus - pz_minus) / 2
  c = pz_plus - pz_max - b

  phi_max = phi_max - b * dphi / (2 * c)
  pz_max = pz_calc(phi_max, err_flag); if (err_flag) return

  ! Now scale %field_scale
  ! scale_correct = dE(design) / dE (from tracking)
  ! Can overshoot so if scale_correct is too large then scale back by a factor of 10

  if (do_scale_amp) then
    scale_correct = dE_peak_wanted / dE_particle(pz_max)
    if (scale_correct > 1000) scale_correct = max(1000.0_rp, scale_correct / 10)
    field_scale = field_scale * scale_correct
  else
    scale_correct = 1
  endif

  if (abs(scale_correct - 1) < scale_tol .and. abs(phi_max-phi_max_old) < phi_tol) exit
  phi_max_old = phi_max

  dphi = 0.05
  if (abs(scale_correct - 1) < 0.1) dphi = max(phi_tol, 0.1*sqrt(2*abs(scale_correct - 1))/twopi)

  if (do_scale_phase) then
    pz_max = pz_calc(phi_max, err_flag); if (err_flag) return
  endif

enddo main_loop

! For an rfcavity now find the zero crossing with negative slope which is
! about 90deg away from max acceleration.

if (ele%key == rfcavity$) then
  value_saved(dphi0_max$) = dphi0_ref  ! Save for use with OPAL
  if (do_scale_phase) then
    dphi = 0.1
    phi_max = phi_max - dphi
    do
      phi = phi_max - dphi
      pz = pz_calc(phi, err_flag); if (err_flag) return
      if (pz < 0) exit
      phi_max = phi
    enddo
    dphi0_ref = modulo2 (zbrent(neg_pz_calc, phi_max-dphi, phi_max, 1d-9), 0.5_rp)
  endif
endif

! Cleanup

call cleanup_this()

if (associated (ele%branch)) then
  if (do_scale_amp)   call set_flags_for_changed_attribute (ele, field_scale)
  if (do_scale_phase) call set_flags_for_changed_attribute (ele, dphi0_ref)
endif

!------------------------------------
contains

subroutine cleanup_this ()

select case (ele%field_calc)
case (bmad_standard$) 
  if (associated(field_scale, ele%value(field_scale$))) then
    value_saved(field_scale$) = field_scale 
    value_saved(dphi0_ref$) = dphi0_ref
  endif
end select

ele%value = value_saved
if (.not. do_scale_phase) dphi0_ref = dphi0_ref_original

ele%tracking_method = tracking_method_saved

end subroutine cleanup_this

!------------------------------------
! contains
! Function returns the energy gain of a particle given final pz

function dE_particle(pz) result (de)

real(rp) pz, e_tot, de

call convert_pc_to ((1 + pz) * ele%value(p0c$), param%particle, e_tot = e_tot)
de = e_tot - e_tot_start

end function dE_particle

end subroutine rf_auto_scale_phase_and_amp

!----------------------------------------------------------------
!----------------------------------------------------------------
!----------------------------------------------------------------

function neg_pz_calc (phi) result (neg_pz)

implicit none

real(rp), intent(in) :: phi
real(rp) neg_pz
logical err_flag

! brent finds minima so need to flip the final energy

neg_pz = -pz_calc(phi, err_flag)

end function neg_pz_calc

!----------------------------------------------------------------
!----------------------------------------------------------------
!----------------------------------------------------------------

function pz_calc (phi, err_flag) result (pz)

implicit none

type (coord_struct) start_orb, end_orb
real(rp), intent(in) :: phi
real(rp) pz
logical err_flag

! 

dphi0_ref = phi
call init_coord (start_orb, ele = ele_com, at_downstream_end = .false., particle = param_com%particle)
call track1 (start_orb, ele_com, param_com, end_orb, err_flag = err_flag, ignore_radiation = .true.)

pz = end_orb%vec(6)
is_lost = .not. particle_is_moving_forward(end_orb)
if (is_lost) pz = -1

n_loop = n_loop + 1

end function pz_calc

!--------------------------------------------------------------------------------------------
!--------------------------------------------------------------------------------------------
!--------------------------------------------------------------------------------------------
!+
! Subroutine pointers_to_rf_auto_scale_vars (ele, field_scale, dphi0_ref)
!
! Routine to set pointers to the variables within an element used for auto scaling.
!
! Input:
!   ele -- ele_struct: Element being scalled.
!
! Output:
!   field_scale -- Real(rp), pointer: Pointer to the amplitude var.
!                     Points to null if does not exist.
!   dphi0_ref   -- Real(rp), pointer: Pointer to the phase var. 
!-


Subroutine pointers_to_rf_auto_scale_vars (ele, field_scale, dphi0_ref)

implicit none

type (ele_struct), target :: ele
real(rp), pointer :: field_scale, dphi0_ref
integer i

!

nullify(field_scale)
nullify(dphi0_ref)

select case (ele%field_calc)
case (bmad_standard$) 
  field_scale => ele%value(field_scale$)
  dphi0_ref => ele%value(dphi0_ref$)

case (grid$, map$, custom$)
  do i = 1, size(ele%em_field%mode)
    if (ele%key == e_gun$ .or. (ele%em_field%mode(i)%harmonic == 1 .and. ele%em_field%mode(i)%m == 0)) then
      field_scale => ele%em_field%mode(i)%field_scale
      dphi0_ref => ele%em_field%mode(i)%dphi0_ref
      exit
    endif
  enddo
end select

end subroutine pointers_to_rf_auto_scale_vars

end module
