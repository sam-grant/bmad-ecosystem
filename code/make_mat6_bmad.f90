!+
! Subroutine make_mat6_bmad (ele, param, c0, c1, end_in, err)
!
! Subroutine to make the 6x6 transfer matrix for an element. 
!
! Modules needed:
!   use bmad
!
! Input:
!   ele    -- Ele_struct: Element with transfer matrix
!   param  -- lat_param_struct: Parameters are needed for some elements.
!   c0     -- Coord_struct: Coordinates at the beginning of element. 
!   end_in -- Logical, optional: If present and True then the end coords c1
!               will be taken as input. not output as normal.
!
! Output:
!   ele    -- Ele_struct: Element with transfer matrix.
!     %vec0  -- 0th order map component
!     %mat6  -- 6x6 transfer matrix.
!   c1     -- Coord_struct: Coordinates at the end of element.
!   err    -- Logical, optional: Set True if there is an error. False otherwise.
!-

subroutine make_mat6_bmad (ele, param, c0, c1, end_in, err)

use track1_mod, dummy => make_mat6_bmad
use mad_mod, dummy1  => make_mat6_bmad

implicit none

type (ele_struct), target :: ele
type (ele_struct) :: temp_ele1, temp_ele2
type (coord_struct) :: c0, c1
type (coord_struct) :: c00, c11, c_int
type (coord_struct) orb
type (lat_param_struct)  param

real(rp), pointer :: mat6(:,:)

real(rp) mat6_pre(6,6), mat6_post(6,6), mat6_i(6,6)
real(rp) mat4(4,4), m2(2,2), kmat4(4,4), om_g, om
real(rp) angle, k1, ks, length, e2, g, g_err, coef
real(rp) k2l, k3l, c2, s2, cs, del_l, beta_ref
real(rp) factor, kmat6(6,6), drift(6,6)
real(rp) s_pos, s_pos_old, z_slice(100)
real(rp) knl(0:n_pole_maxx), tilt(0:n_pole_maxx)
real(rp) c_e, c_m, gamma_old, gamma_new, voltage, sqrt_8
real(rp) arg, rel_p, rel_p2, sq_r_beta, dsq_r_beta_ds, dp_dg, dp_dg_dz1, dp_dg_dpz1
real(rp) cy, sy, k2, s_off, x_pitch, y_pitch, y_ave, k_z
real(rp) dz_x(3), dz_y(3), ddz_x(3), ddz_y(3), xp_start, yp_start
real(rp) t5_11, t5_14, t5_22, t5_23, t5_33, t5_34, t5_44
real(rp) t1_16, t1_26, t1_36, t1_46, t2_16, t2_26, t2_36, t2_46
real(rp) t3_16, t3_26, t3_36, t3_46, t4_16, t4_26, t4_36, t4_46
real(rp) lcs, lc2s2, k, L, m55, m65, m66, new_pc, new_beta
real(rp) cos_phi, gradient_net, e_start, e_end, e_ratio, pc, p0c
real(rp) alpha, sin_a, cos_a, f, phase0, phase, t0, dt_ref_slice, E, pxy2, dE
real(rp) g_tot, rho, ct, st, x, px, y, py, z, pz, Dxy, Dy, px_t
real(rp) Dxy_t, dpx_t, df_dpy, df_dp, kx_1, ky_1, kx_2, ky_2
real(rp) mc2, pc_start, pc_end, pc_start_ref, pc_end_ref, gradient_max, voltage_max
real(rp) beta_start, beta_end, drel_beta_dt1, drel_beta_dE1, ddsq_r_beta_ds_dt, ddsq_r_beta_ds_dE
real(rp) dbeta1_dE1, dbeta2_dE2, dalpha_dt1, dalpha_dE1, dcoef_dt1, dcoef_dE1, z21, z22

real(rp) dp_long_dpx, dp_long_dpy, dp_long_dpz, dalpha_dpx, dalpha_dpy, dalpha_dpz
real(rp) Dy_dpy, Dy_dpz, dpx_t_dx, dpx_t_dpx, dpx_t_dpy, dpx_t_dpz
real(rp) df_dx, df_dpx, df_dpz, deps_dx, deps_dpx, deps_dpy, deps_dpz
real(rp) dbeta_dx, dbeta_dpx, dbeta_dpy, dbeta_dpz, p_long, eps, beta 
real(rp) dfactor_dx, dfactor_dpx, dfactor_dpy, dfactor_dpz, factor1, factor2    

integer i, n_slice, key, ix_fringe

real(rp) charge_dir, hkick, vkick, kick

logical, optional :: end_in, err
logical err_flag, has_nonzero_pole
character(16), parameter :: r_name = 'make_mat6_bmad'

!--------------------------------------------------------
! init

if (present(err)) err = .false.

mat6 => ele%mat6
call mat_make_unit (mat6)
ele%vec0 = 0

length = ele%value(l$)
rel_p = 1 + c0%vec(6) 
key = ele%key

charge_dir = param%rel_tracking_charge * ele%orientation

if (.not. logic_option (.false., end_in)) then
  if (ele%tracking_method == linear$) then
    c0%state = alive$
    call track1_bmad (c0, ele, param, c1)
  else
    call track1 (c0, ele, param, c1)
  endif
  ! If the particle has been lost in tracking this is an error.
  ! Exception: A match element with match_end set to True. 
  ! Here the problem is most likely that twiss_propagate_all has not yet 
  ! been called so ignore this case.
  if (c1%state /= alive$ .and. (ele%key /= match$ .or. ele%value(match_end$) == 0)) then
    mat6 = 0
    if (present(err)) err = .true.
    call out_io (s_error$, r_name, 'PARTICLE LOST IN TRACKING AT: ' // ele%name)
    return
  endif
endif

c00 = c0
c11 = c1

!--------------------------------------------------------
! Drift or element is off.

if (.not. ele%is_on .and. key /= lcavity$ .and. key /= sbend$) key = drift$

if (any (key == [drift$, capillary$])) then
  call offset_particle (ele, c00, param, set$, set_canonical = .false., set_tilt = .false.)
  call drift_mat6_calc (mat6, length, ele, param, c00)
  call add_multipoles_and_z_offset ()
  ele%vec0 = c1%vec - matmul(mat6, c0%vec)
  return
endif

!--------------------------------------------------------
! selection

if (key == sol_quad$ .and. ele%value(k1$) == 0) key = solenoid$

select case (key)

!--------------------------------------------------------
! beam-beam interaction

case (beambeam$)

 call offset_particle (ele, c00, param, set$)
 call offset_particle (ele, c11, param, set$, ds_pos = length)

  n_slice = nint(ele%value(n_slice$))
  if (n_slice < 1) then
    if (present(err)) err = .true.
    call out_io (s_fatal$, r_name,  'N_SLICE FOR BEAMBEAM ELEMENT IS NEGATIVE')
    call type_ele (ele, .true., 0, .false., 0, .false.)
    return
  endif

  if (ele%value(charge$) == 0 .or. param%n_part == 0) return

  ! factor of 2 in orb%vec(5) since relative motion of the two beams is 2*c_light

  if (n_slice == 1) then
    call bbi_kick_matrix (ele, param, c00, 0.0_rp, mat6)
  else
    call bbi_slice_calc (n_slice, ele%value(sig_z$), z_slice)

    s_pos = 0          ! start at IP
    orb = c00
    orb%vec(2) = c00%vec(2) - ele%value(x_pitch_tot$)
    orb%vec(4) = c00%vec(4) - ele%value(y_pitch_tot$)
    call mat_make_unit (mat4)

    do i = 1, n_slice + 1
      s_pos_old = s_pos  ! current position
      s_pos = (z_slice(i) + c00%vec(5)) / 2 ! position of slice relative to IP
      del_l = s_pos - s_pos_old
      mat4(1,1:4) = mat4(1,1:4) + del_l * mat4(2,1:4)
      mat4(3,1:4) = mat4(3,1:4) + del_l * mat4(4,1:4)
      if (i == n_slice + 1) exit
      orb%vec(1) = c00%vec(1) + s_pos * orb%vec(2)
      orb%vec(3) = c00%vec(3) + s_pos * orb%vec(4)
      call bbi_kick_matrix (ele, param, orb, s_pos, kmat6)
      mat4(2,1:4) = mat4(2,1:4) + kmat6(2,1) * mat4(1,1:4) + &
                                  kmat6(2,3) * mat4(3,1:4)
      mat4(4,1:4) = mat4(4,1:4) + kmat6(4,1) * mat4(1,1:4) + &
                                  kmat6(4,3) * mat4(3,1:4)
    enddo

    mat6(1:4,1:4) = mat4

  endif

  call add_multipoles_and_z_offset ()
  ele%vec0 = c1%vec - matmul(mat6, c0%vec)

!--------------------------------------------------------
! Crystal

case (crystal$)

  ! Not yet implemented

!--------------------------------------------------------
! Custom

case (custom$)

  if (present(err)) err = .true.
  call out_io (s_fatal$, r_name,  'MAT6_CALC_METHOD = BMAD_STANDARD IS NOT ALLOWED FOR A CUSTOM ELEMENT: ' // ele%name)
  if (global_com%exit_on_error) call err_exit
  return

!-----------------------------------------------
! elseparator

case (elseparator$)
   
   call make_mat6_mad (ele, param, c0, c1)

!--------------------------------------------------------
! Kicker

case (kicker$, hkicker$, vkicker$, rcollimator$, &
        ecollimator$, monitor$, instrument$, pipe$)

  call offset_particle (ele, c00, param, set$, set_canonical = .false., set_hvkicks = .false.)

  charge_dir = param%rel_tracking_charge * ele%orientation

  hkick = charge_dir * ele%value(hkick$) 
  vkick = charge_dir * ele%value(vkick$) 
  kick  = charge_dir * ele%value(kick$) 
  
  n_slice = max(1, nint(length / ele%value(ds_step$)))
  if (ele%key == hkicker$) then
     c00%vec(2) = c00%vec(2) + kick / (2 * n_slice)
  elseif (ele%key == vkicker$) then
     c00%vec(4) = c00%vec(4) + kick / (2 * n_slice)
  else
     c00%vec(2) = c00%vec(2) + hkick / (2 * n_slice)
     c00%vec(4) = c00%vec(4) + vkick / (2 * n_slice)
  endif

  do i = 1, n_slice 
     call track_a_drift (c00, ele, length/n_slice)
     call drift_mat6_calc (drift, length/n_slice, ele, param, c00)
     mat6 = matmul(drift,mat6)
     if (i == n_slice) then
        if (ele%key == hkicker$) then
           c00%vec(2) = c00%vec(2) + kick / (2 * n_slice)
        elseif (ele%key == vkicker$) then
           c00%vec(4) = c00%vec(4) + kick / (2 * n_slice)
        else
           c00%vec(2) = c00%vec(2) + hkick / (2 * n_slice)
           c00%vec(4) = c00%vec(4) + vkick / (2 * n_slice)
        endif
     else 
        if (ele%key == hkicker$) then
           c00%vec(2) = c00%vec(2) + kick / n_slice
        elseif (ele%key == vkicker$) then
           c00%vec(4) = c00%vec(4) + kick / n_slice
        else
           c00%vec(2) = c00%vec(2) + hkick / n_slice
           c00%vec(4) = c00%vec(4) + vkick / n_slice
        endif
     endif
  end do

  if (ele%value(tilt_tot$) /= 0) then
    call tilt_mat6 (mat6, ele%value(tilt_tot$))
  endif

  call add_multipoles_and_z_offset ()
  ele%vec0 = c1%vec - matmul(mat6, c0%vec)

!--------------------------------------------------------
! LCavity: Linac rf cavity.
! Modified version of the ultra-relativistic formalism from:
!       J. Rosenzweig and L. Serafini
!       Phys Rev E, Vol. 49, p. 1599, (1994)
! with b_0 = b_-1 = 1. See the Bmad manual for more details.
!
! One must keep in mind that we are NOT using good canonical coordinates since
!   the energy of the reference particle is changing.
! This means that the resulting matrix will NOT be symplectic.

case (lcavity$)

  if (length == 0) return

  !

  call offset_particle (ele, c00, param, set$, .false.)

  phase = twopi * (ele%value(phi0$) + ele%value(dphi0$) + &
                   ele%value(dphi0_ref$) +  ele%value(phi0_err$) + &
                   (particle_time (c0, ele) - rf_ref_time_offset(ele)) * ele%value(rf_frequency$))

  if (ele%value(coupler_strength$) /= 0) call mat6_coupler_kick(ele, param, upstream_end$, phase, c00, mat6)

  ! Coupler kick

  if (ele%value(coupler_strength$) /= 0) call mat6_coupler_kick(ele, param, downstream_end$, phase, c00, mat6)

  ! 

  cos_phi = cos(phase)
  gradient_max = param%rel_tracking_charge * e_accel_field (ele, gradient$)
  gradient_net = gradient_max * cos_phi + gradient_shift_sr_wake(ele, param) 
  dE = gradient_net * length

  mc2 = mass_of(param%particle)
  pc_start_ref = ele%value(p0c_start$) 
  pc_start = pc_start_ref * (1 + c00%vec(6))
  beta_start = c00%beta
  E_start = pc_start / beta_start
  E_end = E_start + dE
  if (E_end <= 0) then
    if (present(err)) err = .true.
    call out_io (s_error$, r_name, 'END ENERGY IS NEGATIVE AT ELEMENT: ' // ele%name)
    mat6 = 0   ! garbage.
    return 
  endif

  pc_end_ref = ele%value(p0c$)
  call convert_total_energy_to (E_end, param%particle, pc = pc_end, beta = beta_end)
  E_end = pc_end / beta_end
  E_ratio = E_end / E_start

  ! Entrence kick (R&S Eq 12)

  !! call lcavity_edge_kick_matrix (ele, param, -gradient_max/2, phase, c00, mat6)

  ! Body of cavity transport...
  ! First convert from (x, px, y, py, z, pz) to (x, x', y, y', c(t_ref-t), E) coords 

  rel_p = 1 + c00%vec(6)
  mat6(2,:) = mat6(2,:) / rel_p - c00%vec(2) * mat6(6,:) / rel_p**2
  mat6(4,:) = mat6(4,:) / rel_p - c00%vec(4) * mat6(6,:) / rel_p**2

  m2(1,:) = [1/c00%beta, -c00%vec(5) * mc2**2 * c00%p0c / (pc_start**2 * E_start)]
  m2(2,:) = [0.0_rp, c00%p0c * c00%beta]
  mat6(5:6,:) = matmul(m2, mat6(5:6,:))

  c00%vec(2) = c00%vec(2) / rel_p
  c00%vec(4) = c00%vec(4) / rel_p
  c00%vec(5) = c00%vec(5) / c00%beta 
  c00%vec(6) = rel_p * c00%p0c / c00%beta - 1

  ! Body tracking longitudinal

  om = twopi * ele%value(rf_frequency$) / c_light
  om_g = om * gradient_max * length
  dbeta1_dE1 = mc2**2 / (pc_start * E_start**2)
  dbeta2_dE2 = mc2**2 / (pc_end * E_end**2)

  kmat6(6,5) = om_g * sin(phase)
  kmat6(6,6) = 1

  if (abs(dE) <  1e-4*(pc_end+pc_start)) then
    dp_dg = length * (1 / beta_start - mc2**2 * dE / (2 * pc_start**3) + (mc2 * dE)**2 * E_start / (2 * pc_start**5))
    kmat6(5,5) = 1 - length * (-mc2**2 * kmat6(6,5) / (2 * pc_start**3) + mc2**2 * dE * kmat6(6,5) * E_start / pc_start**5)
    kmat6(5,6) = -length * (-dbeta1_dE1 / beta_start**2 + 2 * mc2**2 * dE / pc_start**4 + &
                    (mc2 * dE)**2 / (2 * pc_start**5) - 5 * (mc2 * dE)**2 / (2 * pc_start**5))
  else
    dp_dg = (pc_end - pc_start) / gradient_net
    kmat6(5,5) = 1 - kmat6(6,5) / (beta_end * gradient_net) + kmat6(6,5) * (pc_end - pc_start) / (gradient_net**2 * length)
    kmat6(5,6) = -1 / (beta_end * gradient_net) + 1 / (beta_start * gradient_net)
  endif

  ! Body tracking transverse

  sqrt_8 = 2 * sqrt_2
  voltage_max = gradient_max * length

  if (abs(voltage_max * cos_phi) < 1e-5 * E_start) then
    g = voltage_max / E_start
    alpha = g * (1 + g * cos_phi / 2)  / sqrt_8
    coef = length * (1 - voltage_max * cos_phi / (2 * E_start))
    dalpha_dt1 = -g * g * om * sin(phase) / (2 * sqrt_8)
    dalpha_dE1 = -(voltage_max / E_start**2 + voltage_max**2 * cos_phi / E_start**3) / sqrt_8
    dcoef_dt1 = -length * sin(phase) * om_g / (2 * E_start)
    dcoef_dE1 = length * voltage_max * cos_phi / (2 * E_start**2)
  else
    alpha = log(E_ratio) / (sqrt_8 * cos_phi)
    coef = sqrt_8 * E_start * sin(alpha) / gradient_max
    dalpha_dt1 = kmat6(6,5) / (E_end * sqrt_8 * cos_phi) - log(E_ratio) * om * sin(phase) / (sqrt_8 * cos_phi**2)
    dalpha_dE1 = 1 / (E_end * sqrt_8 * cos_phi) - 1 / (E_start * sqrt_8 * cos_phi)
    dcoef_dt1 = sqrt_8 * E_start * cos(alpha) * dalpha_dt1 / gradient_max
    dcoef_dE1 = coef / E_start + sqrt_8 * E_start * cos(alpha) * dalpha_dE1 / gradient_max
  endif

  cos_a = cos(alpha)
  sin_a = sin(alpha)

  sq_r_beta = sqrt(beta_start / beta_end)
  dsq_r_beta_ds = -mc2**2 * gradient_net * sq_r_beta / (2 * pc_end**2 * E_end)
  z21 = -gradient_max / (sqrt_8 * E_end)
  z22 = E_start / E_end  

  kmat6(1,1) =  sq_r_beta * cos_a
  kmat6(1,2) =  sq_r_beta * coef 
  kmat6(2,1) =  sq_r_beta * sin_a * z21 + dsq_r_beta_ds * kmat6(1,1)
  kmat6(2,2) =  sq_r_beta * cos_a * z22 + dsq_r_beta_ds * kmat6(1,2)

  drel_beta_dt1 = -dbeta2_dE2 * kmat6(6,5) / (2 * beta_end)                    ! dsq_r_beta/dt1 / sq_r_beta
  drel_beta_dE1 = dbeta1_dE1 / (2 * beta_start) - dbeta2_dE2 / (2 * beta_end)  ! dsq_r_beta/dE1 / sq_r_beta
  ddsq_r_beta_ds_dt = -mc2**2 * kmat6(6,5) * sq_r_beta / (2 * pc_end**2 * E_end) - &
                      dsq_r_beta_ds * kmat6(6,5) * (dbeta2_dE2 / (2 * beta_end) + 2 / (beta_end * pc_end) + 1 / E_end)
  ddsq_r_beta_ds_dE =  dsq_r_beta_ds * (dbeta1_dE1 / (2 * beta_start) - dbeta2_dE2 / (2 * beta_end) - &
                                        2 / (beta_end * pc_end) - 1 / E_end)

  kmat6(1,5) = c00%vec(1) * (drel_beta_dt1 * kmat6(1,1) - sq_r_beta * sin_a * dalpha_dt1) + &
               c00%vec(2) * (drel_beta_dt1 * kmat6(1,2) + sq_r_beta * dcoef_dt1)

  kmat6(1,6) = c00%vec(1) * (drel_beta_dE1 * kmat6(1,1) - sq_r_beta * sin_a * dalpha_dE1) + &
               c00%vec(2) * (drel_beta_dE1 * kmat6(1,2) + sq_r_beta * dcoef_dE1)

  kmat6(2,5) = c00%vec(1) * sq_r_beta * (cos_a * dalpha_dt1 * z21 - sin_a * kmat6(6,5) * z21 / E_end) + &
               c00%vec(1) * (drel_beta_dt1 * sq_r_beta * sin_a * z21 + ddsq_r_beta_ds_dt * kmat6(1,1)) + &
               c00%vec(2) * sq_r_beta * (-sin_a * dalpha_dt1 * z22 - cos_a * kmat6(6,5) * z22 / E_end) + &
               c00%vec(2) * (drel_beta_dt1 * sq_r_beta * cos_a * z22 + ddsq_r_beta_ds_dt * kmat6(1,2)) + &
               dsq_r_beta_ds * kmat6(1,5)

  kmat6(2,6) = c00%vec(1) * sq_r_beta * (cos_a * dalpha_dE1 * z21 - sin_a * z21 / E_end) + &
               c00%vec(1) * (drel_beta_dE1 * sq_r_beta * sin_a * z21 + ddsq_r_beta_ds_dE * kmat6(1,1)) + &
               c00%vec(2) * sq_r_beta * (-sin_a * dalpha_dE1 * z22 + cos_a * z22 * (1 / E_start - 1/ E_end)) + &
               c00%vec(2) * (drel_beta_dE1 * sq_r_beta * cos_a * z22 + ddsq_r_beta_ds_dE * kmat6(1,2)) + &
               dsq_r_beta_ds * kmat6(1,6)

  kmat6(3:4,3:4) = kmat6(1:2,1:2)
  kmat6(3,5) = c00%vec(3) * (drel_beta_dt1 * kmat6(3,3) - sq_r_beta * sin_a * dalpha_dt1) + &
               c00%vec(4) * (drel_beta_dt1 * kmat6(3,4) + sq_r_beta * dcoef_dt1)

  kmat6(3,6) = c00%vec(3) * (drel_beta_dE1 * kmat6(3,3) - sq_r_beta * sin_a * dalpha_dE1) + &
               c00%vec(4) * (drel_beta_dE1 * kmat6(3,4) + sq_r_beta * dcoef_dE1)

  kmat6(4,5) = c00%vec(3) * sq_r_beta * (cos_a * dalpha_dt1 * z21 - sin_a * kmat6(6,5) * z21 / E_end) + &
               c00%vec(3) * (drel_beta_dt1 * sq_r_beta * sin_a * z21 + ddsq_r_beta_ds_dt * kmat6(3,3)) + &
               c00%vec(4) * sq_r_beta * (-sin_a * dalpha_dt1 * z22 - cos_a * kmat6(6,5) * z22 / E_end) + &
               c00%vec(4) * (drel_beta_dt1 * sq_r_beta * cos_a * z22 + ddsq_r_beta_ds_dt * kmat6(3,4)) + &
               dsq_r_beta_ds * kmat6(3,5)

  kmat6(4,6) = c00%vec(3) * sq_r_beta * (cos_a * dalpha_dE1 * z21 - sin_a * z21 / E_end) + &
               c00%vec(3) * (drel_beta_dE1 * sq_r_beta * sin_a * z21 + ddsq_r_beta_ds_dE * kmat6(3,3)) + &
               c00%vec(4) * sq_r_beta * (-sin_a * dalpha_dE1 * z22 + cos_a * z22 * (1 / E_start - 1/ E_end)) + &
               c00%vec(4) * (drel_beta_dE1 * sq_r_beta * cos_a * z22 + ddsq_r_beta_ds_dE * kmat6(3,4)) + &
               dsq_r_beta_ds * kmat6(3,6)


  mat6 = matmul(kmat6, mat6)

  c00%vec(1:2) = matmul(kmat6(1:2,1:2), c00%vec(1:2))
  c00%vec(3:4) = matmul(kmat6(3:4,3:4), c00%vec(3:4))

  c00%vec(5) = c00%vec(5) - (dp_dg - c_light * ele%value(delta_ref_time$))
  c00%vec(6) = (pc_end - pc_end_ref) / pc_end_ref 
  c00%p0c = pc_end_ref
  c00%beta = beta_end

  ! Convert back from (x, x', y, y', c(t-t_ref), E)  to (x, px, y, py, z, pz) coords
  ! Here the effective t used in calculating m2 is zero so m2(1,2) is zero.

  rel_p = pc_end / pc_end_ref
  mat6(2,:) = rel_p * mat6(2,:) + c00%vec(2) * mat6(6,:) / (pc_end_ref * beta_end)
  mat6(4,:) = rel_p * mat6(4,:) + c00%vec(4) * mat6(6,:) / (pc_end_ref * beta_end)

  m2(1,:) = [beta_end, c00%vec(5) * mc2**2 / (pc_end * E_end**2)]
  m2(2,:) = [0.0_rp, 1 / (pc_end_ref * beta_end)]

  mat6(5:6,:) = matmul(m2, mat6(5:6,:))

  c00%vec(2) = c00%vec(2) / rel_p
  c00%vec(4) = c00%vec(4) / rel_p

  return !!!!!

  ! Exit kick (R&S Eq 12)

  call lcavity_edge_kick_matrix (ele, param, gradient_max/2, phase, c00, mat6)

  ! Coupler kick

  if (ele%value(coupler_strength$) /= 0) call mat6_coupler_kick(ele, param, downstream_end$, phase, c00, mat6)

  ! multipoles and z_offset

  if (ele%value(tilt_tot$) /= 0) then
    call tilt_mat6 (mat6, ele%value(tilt_tot$))
  endif

  call add_multipoles_and_z_offset ()
  ele%vec0 = c1%vec - matmul(mat6, c0%vec)

!--------------------------------------------------------
! Marker, branch, photon_branch, etc.

case (marker$, branch$, photon_branch$, floor_shift$, fiducial$) 
  return

!--------------------------------------------------------
! Match

case (match$)
  call match_ele_to_mat6 (ele, ele%vec0, ele%mat6, err_flag)
  if (present(err)) err = err_flag

!--------------------------------------------------------
! Mirror

case (mirror$)

  mat6(1, 1) = -1
  mat6(2, 1) =  0   ! 
  mat6(2, 2) = -1
  mat6(4, 3) = -2 * ele%value(c2_curve_tot$)  

  call offset_photon_mat6(mat6, ele)
  ele%vec0 = c1%vec - matmul(mat6, c0%vec)

!--------------------------------------------------------
! multilayer_mirror

case (multilayer_mirror$) 

  ! Not yet implemented

!--------------------------------------------------------
! Multipole, AB_Multipole

case (multipole$, ab_multipole$)

  if (.not. ele%multipoles_on) return

  call offset_particle (ele, c00, param, set$, set_canonical = .false., set_tilt = .false.)

  call multipole_ele_to_kt (ele, param, .true., has_nonzero_pole, knl, tilt)
  call mat6_multipole (knl, tilt, c00%vec, 1.0_rp, ele%mat6)

  ! if knl(0) is non-zero then the reference orbit itself is bent
  ! and we need to account for this.

  if (knl(0) /= 0) then
    ele%mat6(2,6) = knl(0) * cos(tilt(0))
    ele%mat6(4,6) = knl(0) * sin(tilt(0))
    ele%mat6(5,1) = -ele%mat6(2,6)
    ele%mat6(5,3) = -ele%mat6(4,6)
  endif

  ele%vec0 = c1%vec - matmul(mat6, c0%vec)

!--------------------------------------------------------
! Octupole
! the octupole is modeled as kick-drift-kick

case (octupole$)

  call offset_particle (ele, c00, param, set$, set_canonical = .false.)

  n_slice = max(1, nint(length / ele%value(ds_step$)))

  do i = 0, n_slice
    k3l = charge_dir * ele%value(k3$) * length / n_slice
    if (i == 0 .or. i == n_slice) k3l = k3l / 2
    call mat4_multipole (k3l, 0.0_rp, 3, c00%vec, kmat4)
    c00%vec(2) = c00%vec(2) + k3l *  (3*c00%vec(1)*c00%vec(3)**2 - c00%vec(1)**3) / 6
    c00%vec(4) = c00%vec(4) + k3l *  (3*c00%vec(3)*c00%vec(1)**2 - c00%vec(3)**3) / 6
    mat6(1:4,1:6) = matmul(kmat4, mat6(1:4,1:6))
    if (i /= n_slice) then
      call drift_mat6_calc (drift, length/n_slice, ele, param, c00)
      call track_a_drift (c00, ele, length/n_slice)
      mat6 = matmul(drift,mat6)
    end if
  end do

  if (ele%value(tilt_tot$) /= 0) then
    call tilt_mat6 (mat6, ele%value(tilt_tot$))
  endif

  call add_multipoles_and_z_offset ()
  ele%vec0 = c1%vec - matmul(mat6, c0%vec)

!--------------------------------------------------------
! Patch

case (patch$) 

  mat6(2,6) = -ele%value(x_pitch_tot$)
  mat6(4,6) = -ele%value(y_pitch_tot$)
  mat6(5,1) =  ele%value(x_pitch_tot$)
  mat6(5,3) =  ele%value(y_pitch_tot$)

  if (ele%value(tilt_tot$) /= 0) then
    cos_a = cos(ele%value(tilt_tot$)) ; sin_a = sin(ele%value(tilt_tot$))
    mat6(1,1) =  cos_a ; mat6(2,2) =  cos_a
    mat6(1,3) =  sin_a ; mat6(2,4) =  sin_a
    mat6(3,1) = -sin_a ; mat6(4,2) = -sin_a
    mat6(3,3) =  cos_a ; mat6(4,4) =  cos_a
  endif

  ele%vec0 = c1%vec - matmul(mat6, c0%vec)

!--------------------------------------------------------
! quadrupole

case (quadrupole$)

  call offset_particle (ele, c00, param, set$)
  call offset_particle (ele, c11, param, set$, ds_pos = length)
  
  ix_fringe = nint(ele%value(fringe_type$))
  k1 = ele%value(k1$) * charge_dir / rel_p

  call quad_mat2_calc (-k1, length, mat6(1:2,1:2), dz_x, c0%vec(6), ddz_x)
  call quad_mat2_calc ( k1, length, mat6(3:4,3:4), dz_y, c0%vec(6), ddz_y)

  mat6(1,2) = mat6(1,2) / rel_p
  mat6(2,1) = mat6(2,1) * rel_p

  mat6(3,4) = mat6(3,4) / rel_p
  mat6(4,3) = mat6(4,3) * rel_p

  ! The mat6(i,6) terms are constructed so that mat6 is sympelctic

  if (ix_fringe == full_straight$ .or. ix_fringe == full_bend$) then
    c_int = c00
    call quadrupole_edge_kick (ele, upstream_end$, c00)
    call quadrupole_edge_kick (ele, upstream_end$, c11) ! Yes upstream since we are propagating backwards.
  endif

  if (any(c00%vec(1:4) /= 0)) then
    mat6(5,1) = 2 * c00%vec(1) * dz_x(1) +     c00%vec(2) * dz_x(2)
    mat6(5,2) =    (c00%vec(1) * dz_x(2) + 2 * c00%vec(2) * dz_x(3)) / rel_p
    mat6(5,3) = 2 * c00%vec(3) * dz_y(1) +     c00%vec(4) * dz_y(2)
    mat6(5,4) =    (c00%vec(3) * dz_y(2) + 2 * c00%vec(4) * dz_y(3)) / rel_p
    mat6(5,6) = c00%vec(1)**2 * ddz_x(1) + c00%vec(1)*c00%vec(2) * ddz_x(2) + c00%vec(2)**2 * ddz_x(3)  + &
                c00%vec(3)**2 * ddz_y(1) + c00%vec(3)*c00%vec(4) * ddz_y(2) + c00%vec(4)**2 * ddz_y(3)  
  endif

  if (any(mat6(5,1:4) /= 0)) then
    mat6(1,6) = mat6(5,2) * mat6(1,1) - mat6(5,1) * mat6(1,2)
    mat6(2,6) = mat6(5,2) * mat6(2,1) - mat6(5,1) * mat6(2,2)
    mat6(3,6) = mat6(5,4) * mat6(3,3) - mat6(5,3) * mat6(3,4)
    mat6(4,6) = mat6(5,4) * mat6(4,3) - mat6(5,3) * mat6(4,4)
  endif

  call quad_mat6_edge_effect (ele, k1, c_int, c11, mat6)

  ! tilt and multipoles

  if (ele%value(tilt_tot$) /= 0) then
    call tilt_mat6 (mat6, ele%value(tilt_tot$))
  endif

  call add_multipoles_and_z_offset ()
  call add_M56_low_E_correction()
  ele%vec0 = c1%vec - matmul(mat6, c0%vec)

!--------------------------------------------------------
! rbends are not allowed internally

case (rbend$)

  if (present(err)) err = .true.
  call out_io (s_fatal$, r_name,  'RBEND ELEMENTS NOT ALLOWED INTERNALLY!')
  if (global_com%exit_on_error) call err_exit
  return

!--------------------------------------------------------
! rf cavity
! Calculation Uses a 3rd order map assuming a linearized rf voltage vs time.

case (rfcavity$)

  mc2 = mass_of(param%particle)
  p0c = ele%value(p0c$)
  beta_ref = p0c / ele%value(e_tot$)
  n_slice = max(1, nint(length / ele%value(ds_step$))) 
  dt_ref_slice = length / (n_slice * c_light * beta_ref)

  call offset_particle (ele, c00, param, set$, set_canonical = .false., set_tilt = .false.)

  voltage = param%rel_tracking_charge * e_accel_field (ele, voltage$)

  phase0 = twopi * (ele%value(phi0$) + ele%value(dphi0$) - ele%value(dphi0_ref$) - &
                  (particle_time (c00, ele) - rf_ref_time_offset(ele)) * ele%value(rf_frequency$))
  phase = phase0
  t0 = c00%t

  ! Track through slices.
  ! The phase of the accelerating wave traveling in the same direction as the particle is
  ! assumed to be traveling with a phase velocity the same speed as the reference velocity.

  if (ele%value(coupler_strength$) /= 0) call mat6_coupler_kick(ele, param, upstream_end$, phase, c00, mat6)

  do i = 0, n_slice

    factor = voltage / n_slice
    if (i == 0 .or. i == n_slice) factor = factor / 2

    dE = factor * sin(phase)
    pc = (1 + c00%vec(6)) * p0c 
    E = pc / c00%beta
    call convert_total_energy_to (E + dE, param%particle, pc = new_pc, beta = new_beta)
    f = twopi * factor * ele%value(rf_frequency$) * cos(phase) / (p0c * new_beta * c_light)

    m2(2,1) = f / c00%beta
    m2(2,2) = c00%beta / new_beta - f * c00%vec(5) *mc2**2 * p0c / (E * pc**2) 
    m2(1,1) = new_beta / c00%beta + c00%vec(5) * (mc2**2 * p0c * m2(2,1) / (E+dE)**3) / c00%beta
    m2(1,2) = c00%vec(5) * mc2**2 * p0c * (m2(2,2) / ((E+dE)**3 * c00%beta) - new_beta / (pc**2 * E))

    mat6(5:6, :) = matmul(m2, mat6(5:6, :))
  
    c00%vec(6) = (new_pc - p0c) / p0c
    c00%vec(5) = c00%vec(5) * new_beta / c00%beta
    c00%beta   = new_beta

    if (i /= n_slice) then
      call drift_mat6_calc (drift, length/n_slice, ele, param, c00)
      call track_a_drift (c00, ele, length/n_slice)
      mat6 = matmul(drift, mat6)
      phase = phase0 + twopi * ele%value(rf_frequency$) * ((i + 1) * dt_ref_slice - (c00%t - t0)) 
    endif

  enddo

  ! Coupler kick

  if (ele%value(coupler_strength$) /= 0) call mat6_coupler_kick(ele, param, downstream_end$, phase, c00, mat6)

  call offset_particle (ele, c00, param, unset$, set_canonical = .false., set_tilt = .false.)

  !

  call add_multipoles_and_z_offset ()
  ele%vec0 = c1%vec - matmul(mat6, c0%vec)

!--------------------------------------------------------
! sbend

case (sbend$)

  k1 = ele%value(k1$) * charge_dir
  k2 = ele%value(k2$) * charge_dir
  g = ele%value(g$)
  rho = 1 / g
  g_tot = (g + ele%value(g_err$)) * charge_dir
  g_err = g_tot - g

  if (.not. ele%is_on) then
    g_err = 0
    g_tot = -g
    k1 = 0
    k2 = 0
  endif

  ! Reverse track here for c11 since c11 needs to be the orbit just inside the bend.
  ! Notice that kx_2 and ky_2 are not affected by reverse tracking

  call offset_particle (ele, c00, param, set$, set_canonical = .false.)
    
  ! Entrance edge kick

  call bend_edge_kick (c00, ele, param, upstream_end$, .false., mat6_pre)

  call offset_particle (ele, c11, param, set$, set_canonical = .false., ds_pos = length)
 
  ! Exit edge kick
  
  call bend_edge_kick (c11, ele, param, downstream_end$, .false., mat6_post)

  ! If we have a sextupole component then step through in steps of length ds_step

  n_slice = 1  
  if (k2 /= 0) n_slice = max(nint(ele%value(l$) / ele%value(ds_step$)), 1)
  length = length / n_slice
  k2l = charge_dir * ele%value(k2$) * length  
  
  call transfer_ele(ele, temp_ele1, .true.)
  temp_ele1%value(l$) = length

  call transfer_ele(ele, temp_ele2, .true.)
  call zero_ele_offsets(temp_ele2)
  temp_ele2%value(l$) = length
  temp_ele2%value(e1$) = 0
  temp_ele2%value(e2$) = 0
  temp_ele2%value(k2$) = 0
 
  ! 1/2 sextupole kick at the beginning.

  if (k2l /= 0) then
    call mat4_multipole (k2l/2, 0.0_rp, 2, c00%vec, kmat4)
    c00%vec(2) = c00%vec(2) + k2l/2 * (c00%vec(3)**2 - c00%vec(1)**2)/2
    c00%vec(4) = c00%vec(4) + k2l/2 * c00%vec(1) * c00%vec(3)
    mat6(1:4,1:6) = matmul(kmat4,mat6(1:4,1:6))
  end if
  
  ! And track with n_slice steps

  do i = 1, n_slice

    call mat_make_unit(mat6_i)

    if (g == 0 .or. k1 /= 0) then

      call sbend_body_with_k1_map (temp_ele1, param, 1, c00, mat6 = mat6_i)
        
    elseif (length /= 0) then

      ! Used: Eqs (12.18) from Etienne Forest: Beam Dynamics.

      x  = c00%vec(1)
      px = c00%vec(2)
      y  = c00%vec(3)
      py = c00%vec(4)
      z  = c00%vec(5)
      pz = c00%vec(6)
 
      angle = g * length
      rel_p  = 1 + pz
      rel_p2 = rel_p**2

      ct = cos(angle)
      st = sin(angle)

      pxy2 = px**2 + py**2

      p_long = sqrt(rel_p2 - pxy2)
      dp_long_dpx = -px/p_long
      dp_long_dpy = -py/p_long
      dp_long_dpz = rel_p/p_long
      
      ! The following is to make sure that a beam entering on-axis remains 
      ! *exactly* on-axis.

      if (pxy2 < 1e-5) then  
         f = pxy2 / (2 * rel_p)
         f = pz - f - f*f/2 - g_err*rho - g_tot*x
         df_dx  = -g_tot
         df_dpx = -px * pxy2 / (2 * rel_p2) - px/rel_p
         df_dpy = -py * pxy2 / (2 * rel_p2) - py/rel_p
         df_dpz = 1 + pxy2**2 / (4 * rel_p**3) + pxy2 / (2 * rel_p2)
      else
         f = p_long - g_tot * (1 + x * g) / g
         df_dx  = -g_tot
         df_dpx = dp_long_dpx
         df_dpy = dp_long_dpy
         df_dpz = dp_long_dpz
      endif

      Dy  = sqrt(rel_p2 - py**2)
      Dy_dpy = -py/Dy
      Dy_dpz = rel_p/Dy

      px_t = px*ct + f*st
      dpx_t = -px*st*g + f*ct*g

      dpx_t_dx  = ct*g*df_dx
      dpx_t_dpx = -st*g + ct*g*df_dpx
      dpx_t_dpy = ct*g*df_dpy
      dpx_t_dpz = ct*g*df_dpz

      if (abs(g_tot) < 1e-5 * abs(g)) then
        alpha = p_long * ct - px * st
        dalpha_dpx = dp_long_dpx * ct - st
        dalpha_dpy = dp_long_dpy * ct
        dalpha_dpz = dp_long_dpz * ct
        mat6_i(1,1) = -(g_tot*st**2*(1+g*x)*Dy**2)/(g*alpha**3) + p_long/alpha &
                      +(3*g_tot**2*st**3*(1+g*x)**2*Dy**2*(ct*px+st*p_long))/(2*g**2*alpha**5)
        mat6_i(1,2) = (3*g_tot*st**2*(1+g*x)**2*Dy**2*dalpha_dpx)/(2*g**2*alpha**4) &
                      -(5*g_tot**2*st**3*(1+g*x)**3*Dy**2*(ct*px+st*p_long)*dalpha_dpx)/(2*g**3*alpha**6) &
                      -((-alpha+(1+g*x)*p_long)*dalpha_dpx)/(g*alpha**2) &
                      +(g_tot**2*st**3*(1+g*x)**3*Dy**2*(ct+st*dp_long_dpx))/(2*g**3*alpha**5) &
                      +(-dalpha_dpx+(1+g*x)*dp_long_dpx)/(g*alpha)
        mat6_i(1,4) = (3*g_tot*st**2*(1+g*x)**2*Dy**2*dalpha_dpy)/(2*g**2*alpha**4) &
                      -(5*g_tot**2*st**3*(1+g*x)**3*Dy**2*(ct*px+st*p_long)*dalpha_dpy)/(2*g**3*alpha**6) &
                      -((-alpha+(1+g*x)*p_long)*dalpha_dpy)/(g*alpha**2) &
                      +(g_tot**2*st**4*(1+g*x)**3*Dy**2*dp_long_dpy)/(2*g**3*alpha**5) &
                      +(-dalpha_dpy+(1+g*x)*dp_long_dpy)/(g*alpha) &
                      -(g_tot*st**2*(1+g*x)**2*Dy*Dy_dpy)/(g**2*alpha**3) &
                      +(g_tot**2*st**3*(1+g*x)**3*Dy*(ct*px+st*p_long)*Dy_dpy)/(g**3*alpha**5)
        mat6_i(1,6) = (3*g_tot*st**2*(1+g*x)**2*Dy**2*dalpha_dpz)/(2*g**2*alpha**4) &
                      -(5*g_tot**2*st**3*(1+g*x)**3*Dy**2*(ct*px+st*p_long)*dalpha_dpz)/(2*g**3*alpha**6) &
                      -((-alpha+(1+g*x)*p_long)*dalpha_dpz)/(g*alpha**2) &
                      +(g_tot**2*st**4*(1+g*x)**3*Dy**2*dp_long_dpz)/(2*g**3*alpha**5) &
                      +(-dalpha_dpz+(1+g*x)*dp_long_dpz)/(g*alpha) &
                      -(g_tot*st**2*(1+g*x)**2*Dy*Dy_dpz)/(g**2*alpha**3) &
                      +(g_tot**2*st**3*(1+g*x)**3*Dy*(ct*px+st*p_long)*Dy_dpz)/(g**3*alpha**5)
      else
        eps = px_t**2 + py**2
        deps_dx  = 2*px_t*st*df_dx
        deps_dpx = 2*px_t*(ct+st*df_dpx)
        deps_dpy = 2*px_t*st*df_dpy + 2*py
        deps_dpz = 2*px_t*st*df_dpz
        if (eps < 1e-5 * rel_p2 ) then  ! use small angle approximation
          eps = eps / (2 * rel_p)
          deps_dx  = deps_dx / (2 * rel_p)
          deps_dpx = deps_dpx / (2 * rel_p)
          deps_dpy = deps_dpy / (2 * rel_p)
          deps_dpz = deps_dpz / (2 * rel_p) - (px_t**2 + py**2) / (2*rel_p2) 
          mat6_i(1,1) = (-rho*dpx_t_dx+(eps/(2*rel_p)-1)*deps_dx+eps*deps_dx/(2*rel_p))/g_tot
          mat6_i(1,2) = (-rho*dpx_t_dpx+(eps/(2*rel_p)-1)*deps_dpx+eps*deps_dpx/(2*rel_p))/g_tot
          mat6_i(1,4) = (-rho*dpx_t_dpy+(eps/(2*rel_p)-1)*deps_dpy+eps*deps_dpy/(2*rel_p))/g_tot
          mat6_i(1,6) = (1-rho*dpx_t_dpz+(eps/(2*rel_p)-1)*deps_dpz+eps*(deps_dpz/(2*rel_p)-eps/(2*rel_p2)))/g_tot
        else
          mat6_i(1,1) = (-rho*dpx_t_dx-deps_dx/(2*sqrt(rel_p2-eps)))/g_tot
          mat6_i(1,2) = (-rho*dpx_t_dpx-deps_dpx/(2*sqrt(rel_p2-eps)))/g_tot
          mat6_i(1,4) = (-rho*dpx_t_dpy-deps_dpy/(2*sqrt(rel_p2-eps)))/g_tot
          mat6_i(1,6) = (-rho*dpx_t_dpz+(2*rel_p-deps_dpz)/(2*sqrt(rel_p2-eps)))/g_tot
        endif
      endif
      
      mat6_i(2,1) = -g_tot * st
      mat6_i(2,2) = ct - px * st / p_long
      mat6_i(2,4) = -py * st / p_long
      mat6_i(2,6) = rel_p * st / p_long

      if (abs(g_tot) < 1e-5 * abs(g)) then
        beta = (1 + g * x) * st / (g * alpha) - &
               g_tot * (px * ct + p_long * st) * (st * (1 + g * x))**2 / (2 * g**2 * alpha**3)
        dbeta_dx  = st/alpha - (g_tot*st**2*(1+g*x)*(ct*px+st*p_long))/(g*alpha**3)
        dbeta_dpx = -(st*(1+g*x)*dalpha_dpx)/(g*alpha**2)-(g_tot*st**2*(1+g*x)**2*(ct+st*dp_long_dpx))/(2*g**2*alpha**3)
        dbeta_dpy = -(st*(1+g*x)*dalpha_dpy)/(g*alpha**2)-(g_tot*st**3*(1+g*x)**2*dp_long_dpy)/(2*g**2*alpha**3)
        dbeta_dpz = -(st*(1+g*x)*dalpha_dpz)/(g*alpha**2)-(g_tot*st**3*(1+g*x)**2*dp_long_dpz)/(2*g**2*alpha**3)
        mat6_i(3,1) = py*dbeta_dx
        mat6_i(3,2) = py*dbeta_dpx
        mat6_i(3,4) = beta + py*dbeta_dpy
        mat6_i(3,6) = py*dbeta_dpz
        mat6_i(5,1) = -rel_p*dbeta_dx
        mat6_i(5,2) = -rel_p*dbeta_dpx
        mat6_i(5,4) = -rel_p*dbeta_dpy
        mat6_i(5,6) = -beta - rel_p*dbeta_dpz
      else
        factor = (asin(px/Dy) - asin(px_t/Dy)) / g_tot
        factor1 = sqrt(1-(px/Dy)**2)
        factor2 = sqrt(1-(px_t/Dy)**2)
        dfactor_dx  = -st*df_dx/(Dy*factor2*g_tot)
        dfactor_dpx = (1/(factor1*Dy)-(ct+st*df_dpx)/(factor2*Dy))/g_tot
        dfactor_dpy = (-px*Dy_dpy/(factor1*Dy**2)-(-px_t*Dy_dpy/Dy**2 + st*df_dpy/Dy)/factor2)/g_tot
        dfactor_dpz = (-px*Dy_dpz/(factor1*Dy**2)-(-px_t*Dy_dpz/Dy**2 + st*df_dpz/Dy)/factor2)/g_tot
        mat6_i(3,1) = py*dfactor_dx
        mat6_i(3,2) = py*dfactor_dpx
        mat6_i(3,4) = angle/g_tot + factor + py*dfactor_dpy
        mat6_i(3,6) = py*dfactor_dpz
        mat6_i(5,1) = -rel_p*dfactor_dx
        mat6_i(5,2) = -rel_p*dfactor_dpx
        mat6_i(5,4) = -rel_p*dfactor_dpy
        mat6_i(5,6) = -angle/g_tot - factor - rel_p*dfactor_dpz
      endif
      
    endif  

    mat6 = matmul(mat6_i,mat6)
    c_int = c00
    call track_a_bend (c_int, temp_ele2, param, c00)

    if (i == n_slice) k2l = k2l/2
    if (k2l /= 0) then
      call mat4_multipole (k2l, 0.0_rp, 2, c00%vec, kmat4)
      c00%vec(2) = c00%vec(2) + k2l * (c00%vec(3)**2 - c00%vec(1)**2)/2
      c00%vec(4) = c00%vec(4) + k2l * c00%vec(1) * c00%vec(3)
      mat6(1:4,1:6) = matmul(kmat4,mat6(1:4,1:6))
    end if

  end do

  mat6 = matmul(mat6,mat6_pre)
  mat6 = matmul(mat6_post,mat6)

  if (ele%value(tilt_tot$)+ele%value(roll$) /= 0) then
    call tilt_mat6 (mat6, ele%value(tilt_tot$)+ele%value(roll$))
  endif

  call add_multipoles_and_z_offset ()
  call add_M56_low_E_correction()
  ele%vec0 = c1%vec - matmul(mat6, c0%vec)

!--------------------------------------------------------
! Sextupole.
! the sextupole is modeled as kick-drift-kick

case (sextupole$)

  call offset_particle (ele, c00, param, set$, set_canonical = .false.)

  n_slice = max(1, nint(length / ele%value(ds_step$)))
  
  do i = 0, n_slice
    k2l = charge_dir * ele%value(k2$) * length / n_slice
    if (i == 0 .or. i == n_slice) k2l = k2l / 2
    call mat4_multipole (k2l, 0.0_rp, 2, c00%vec, kmat4)
    c00%vec(2) = c00%vec(2) + k2l * (c00%vec(3)**2 - c00%vec(1)**2)/2
    c00%vec(4) = c00%vec(4) + k2l * c00%vec(1) * c00%vec(3)
    mat6(1:4,1:6) = matmul(kmat4,mat6(1:4,1:6))
    if (i /= n_slice) then
      call drift_mat6_calc (drift, length/n_slice, ele, param, c00)
      call track_a_drift (c00, ele, length/n_slice)
      mat6 = matmul(drift,mat6)
    end if
  end do

  if (ele%value(tilt_tot$) /= 0) then
    call tilt_mat6 (mat6, ele%value(tilt_tot$))
  endif

  call add_multipoles_and_z_offset ()
  ele%vec0 = c1%vec - matmul(mat6, c0%vec)

!--------------------------------------------------------
! solenoid

case (solenoid$)

  call offset_particle (ele, c00, param, set$)

  ks = param%rel_tracking_charge * ele%value(ks$) / rel_p

  call solenoid_mat_calc (ks, length, mat6(1:4,1:4))

  mat6(1,2) = mat6(1,2) / rel_p
  mat6(1,4) = mat6(1,4) / rel_p

  mat6(2,1) = mat6(2,1) * rel_p
  mat6(2,3) = mat6(2,3) * rel_p

  mat6(3,2) = mat6(3,2) / rel_p
  mat6(3,4) = mat6(3,4) / rel_p

  mat6(4,1) = mat6(4,1) * rel_p
  mat6(4,3) = mat6(4,3) * rel_p


  c2 = mat6(1,1)
  s2 = mat6(1,4) * ks / 2
  cs = mat6(1,3)

  lcs = length * cs
  lc2s2 = length * (c2 - s2) / 2

  t1_16 =  lcs * ks
  t1_26 = -lc2s2 * 2
  t1_36 = -lc2s2 * ks
  t1_46 = -lcs * 2

  t2_16 =  lc2s2 * ks**2 / 2
  t2_26 =  lcs * ks
  t2_36 =  lcs * ks**2 / 2
  t2_46 = -lc2s2 * ks

  t3_16 =  lc2s2 * ks
  t3_26 =  lcs * 2
  t3_36 =  lcs * ks
  t3_46 = -lc2s2 * 2

  t4_16 = -lcs * ks**2 / 2
  t4_26 =  lc2s2 * ks
  t4_36 =  t2_16
  t4_46 =  lcs * ks

  arg = length / 2
  t5_11 = -arg * (ks/2)**2
  t5_14 =  arg * ks
  t5_22 = -arg
  t5_23 = -arg * ks
  t5_33 = -arg * (ks/2)**2
  t5_44 = -arg

  ! the mat6(i,6) terms are constructed so that mat6 is sympelctic

  mat6(5,1) =  2 * c00%vec(1) * t5_11 + c00%vec(4) * t5_14
  mat6(5,2) = (2 * c00%vec(2) * t5_22 + c00%vec(3) * t5_23) / rel_p
  mat6(5,3) =  2 * c00%vec(3) * t5_33 + c00%vec(2) * t5_23
  mat6(5,4) = (2 * c00%vec(4) * t5_44 + c00%vec(1) * t5_14) / rel_p

  mat6(1,6) = mat6(5,2) * mat6(1,1) - mat6(5,1) * mat6(1,2) + &
                  mat6(5,4) * mat6(1,3) - mat6(5,3) * mat6(1,4)
  mat6(2,6) = mat6(5,2) * mat6(2,1) - mat6(5,1) * mat6(2,2) + &
                  mat6(5,4) * mat6(2,3) - mat6(5,3) * mat6(2,4)
  mat6(3,6) = mat6(5,4) * mat6(3,3) - mat6(5,3) * mat6(3,4) + &
                  mat6(5,2) * mat6(3,1) - mat6(5,1) * mat6(3,2)
  mat6(4,6) = mat6(5,4) * mat6(4,3) - mat6(5,3) * mat6(4,4) + &
                  mat6(5,2) * mat6(4,1) - mat6(5,1) * mat6(4,2)

  ! mat6(5,6) 

  xp_start = c00%vec(2) + ks * c00%vec(3) / 2
  yp_start = c00%vec(4) - ks * c00%vec(1) / 2
  mat6(5,6) = length * (xp_start**2 + yp_start**2 ) / rel_p

  if (ele%value(tilt_tot$) /= 0) then
    call tilt_mat6 (mat6, ele%value(tilt_tot$))
  endif

  call add_multipoles_and_z_offset ()
  call add_M56_low_E_correction()
  ele%vec0 = c1%vec - matmul(mat6, c0%vec)

!--------------------------------------------------------
! solenoid/quad

case (sol_quad$)

  call offset_particle (ele, c00, param, set$)

  call sol_quad_mat6_calc (ele%value(ks$) * param%rel_tracking_charge, ele%value(k1$) * charge_dir, length, mat6, c00%vec)

  if (ele%value(tilt_tot$) /= 0) then
    call tilt_mat6 (mat6, ele%value(tilt_tot$))
  endif

  call add_multipoles_and_z_offset ()
  call add_M56_low_E_correction()
  ele%vec0 = c1%vec - matmul(mat6, c0%vec)

!--------------------------------------------------------
! taylor

case (taylor$)

  call make_mat6_taylor (ele, param, c0)

!--------------------------------------------------------
! wiggler

case (wiggler$)

  call offset_particle (ele, c00, param, set$)
  call offset_particle (ele, c11, param, set$, ds_pos = length)

  call mat_make_unit (mat6)     ! make a unit matrix

  if (length == 0) then
    call add_multipoles_and_z_offset ()
  call add_M56_low_E_correction()
    return
  endif

  k1 = -0.5 * charge_dir * (c_light * ele%value(b_max$) / (ele%value(p0c$) * rel_p))**2

  ! octuple correction to k1

  y_ave = (c00%vec(3) + c11%vec(3)) / 2
  if (ele%value(l_pole$) == 0) then
    k_z = 0
  else
    k_z = pi / ele%value(l_pole$)
  endif
  k1 = k1 * (1 + 2 * (k_z * y_ave)**2)

  !

  mat6(1, 1) = 1
  mat6(1, 2) = length
  mat6(2, 1) = 0
  mat6(2, 2) = 1

  call quad_mat2_calc (k1, length, mat6(3:4,3:4))

  cy = mat6(3, 3)
  sy = mat6(3, 4)

  t5_22 = -length / 2
  t5_33 =  k1 * (length - sy*cy) / 4
  t5_34 = -k1 * sy**2 / 2
  t5_44 = -(length + sy*cy) / 4

  ! the mat6(i,6) terms are constructed so that mat6 is sympelctic

  mat6(5,2) = 2 * c00%vec(2) * t5_22
  mat6(5,3) = 2 * c00%vec(3) * t5_33 +     c00%vec(4) * t5_34
  mat6(5,4) =     c00%vec(3) * t5_34 + 2 * c00%vec(4) * t5_44

  mat6(1,6) = mat6(5,2) * mat6(1,1)
  mat6(2,6) = mat6(5,2) * mat6(2,1)
  mat6(3,6) = mat6(5,4) * mat6(3,3) - mat6(5,3) * mat6(3,4)
  mat6(4,6) = mat6(5,4) * mat6(4,3) - mat6(5,3) * mat6(4,4)

  if (ele%value(tilt_tot$) /= 0) then
    call tilt_mat6 (mat6, ele%value(tilt_tot$))
  endif

  call add_multipoles_and_z_offset ()
  call add_M56_low_E_correction()
  ele%vec0 = c1%vec - matmul(mat6, c0%vec)

!--------------------------------------------------------
! Accelerating solenoid with steerings
! WARNING: This 6x6 matrix may produce bad results at low energies!

case (accel_sol$)

!--------------------------------------------------------
! unrecognized element

case default

  if (present(err)) err = .true.
  call out_io (s_fatal$, r_name,  'UNKNOWN ELEMENT KEY: \i0\ ', &
                                  'FOR ELEMENT: ' // ele%name, i_array = [ele%key])
  if (global_com%exit_on_error) call err_exit
  return

end select

!--------------------------------------------------------
! put in multipole components

contains

subroutine add_multipoles_and_z_offset ()

implicit none

real(rp) mat6_m(6,6)
logical has_nonzero_pole

!

if (key /= multipole$ .and. key /= ab_multipole$) then
  call multipole_ele_to_kt (ele, param, .true., has_nonzero_pole, knl, tilt)
  if (has_nonzero_pole) then
    mat6_m = 0
    call mat6_multipole (knl, tilt, c0%vec, 0.5_rp, mat6_m)
    mat6(:,1) = mat6(:,1) + mat6(:,2) * mat6_m(2,1) + mat6(:,4) * mat6_m(4,1)
    mat6(:,3) = mat6(:,3) + mat6(:,2) * mat6_m(2,3) + mat6(:,4) * mat6_m(4,3)
    mat6_m = 0
    call mat6_multipole (knl, tilt, c1%vec, 0.5_rp, mat6_m)
    mat6(2,:) = mat6(2,:) + mat6_m(2,1) * mat6(1,:) + mat6_m(2,3) * mat6(3,:)
    mat6(4,:) = mat6(4,:) + mat6_m(4,1) * mat6(1,:) + mat6_m(4,3) * mat6(3,:)
  endif
endif

if (ele%value(z_offset_tot$) /= 0) then
  s_off = ele%value(z_offset_tot$) * ele%orientation
  mat6(1,:) = mat6(1,:) - s_off * mat6(2,:)
  mat6(3,:) = mat6(3,:) - s_off * mat6(4,:)
  mat6(:,2) = mat6(:,2) + mat6(:,1) * s_off
  mat6(:,4) = mat6(:,4) + mat6(:,3) * s_off
endif

! pitch corrections

call mat6_add_pitch (ele%value(x_pitch_tot$), ele%value(y_pitch_tot$), ele%orientation, ele%mat6)

end subroutine add_multipoles_and_z_offset

!----------------------------------------------------------------
! contains

subroutine add_M56_low_E_correction()

real(rp) mass, e_tot

! 1/gamma^2 m56 correction

mass = mass_of(param%particle)
e_tot = ele%value(p0c$) * (1 + c0%vec(6)) / c0%beta
mat6(5,6) = mat6(5,6) + length * mass**2 * ele%value(e_tot$) / e_tot**3

end subroutine add_M56_low_E_correction

end subroutine make_mat6_bmad

!----------------------------------------------------------------
!----------------------------------------------------------------
!----------------------------------------------------------------

subroutine mat6_coupler_kick(ele, param, end_at, phase, orb, mat6)

use track1_mod

implicit none

type (ele_struct) ele
type (coord_struct) orb, old_orb
type (lat_param_struct) param
real(rp) phase, mat6(6,6), f, f2, coef, E_new
real(rp) dp_coef, dp_x, dp_y, ph, mc(6,6), E, pc, mc2, p0c
integer end_at

!

if (.not. at_this_ele_end (end_at, nint(ele%value(coupler_at$)), ele%orientation)) return

ph = phase
if (ele%key == rfcavity$) ph = pi/2 - ph
ph = ph + twopi * ele%value(coupler_phase$)

mc2 = mass_of(param%particle)
p0c = orb%p0c
pc = p0c * (1 + orb%vec(6))
E = pc / orb%beta

f = twopi * ele%value(rf_frequency$) / c_light
dp_coef = e_accel_field(ele, gradient$) * ele%value(coupler_strength$)
dp_x = dp_coef * cos(twopi * ele%value(coupler_angle$))
dp_y = dp_coef * sin(twopi * ele%value(coupler_angle$))

if (nint(ele%value(coupler_at$)) == both_ends$) then
  dp_x = dp_x / 2
  dp_y = dp_y / 2
endif

! Track

old_orb = orb
call rf_coupler_kick (ele, param, end_at, phase, orb)

! Matrix

call mat_make_unit (mc)

mc(2,5) = dp_x * f * sin(ph) / (old_orb%beta * p0c)
mc(4,5) = dp_y * f * sin(ph) / (old_orb%beta * p0c)

mc(2,6) = -dp_x * f * sin(ph) * old_orb%vec(5) * mc2**2 / (E * pc**2)
mc(4,6) = -dp_y * f * sin(ph) * old_orb%vec(5) * mc2**2 / (E * pc**2)

coef = (dp_x * old_orb%vec(1) + dp_y * old_orb%vec(3)) * cos(ph) * f**2 
mc(6,1) = dp_x * sin(ph) * f / (orb%beta * p0c)
mc(6,3) = dp_y * sin(ph) * f / (orb%beta * p0c)
mc(6,5) = -coef / (orb%beta * old_orb%beta * p0c) 
mc(6,6) = old_orb%beta/orb%beta + coef * old_orb%vec(5) * mc2**2 / (pc**2 * E * orb%beta)

f2 = old_orb%vec(5) * mc2**2 / (pc * E**2 * p0c)
E_new = p0c * (1 + orb%vec(6)) / orb%beta

mc(5,1) = old_orb%vec(5) * mc2**2 * p0c * mc(6,1) / (old_orb%beta * E_new**3)
mc(5,3) = old_orb%vec(5) * mc2**2 * p0c * mc(6,3) / (old_orb%beta * E_new**3)
mc(5,5) = orb%beta/old_orb%beta + old_orb%vec(5) * mc2**2 * p0c * mc(6,5) / (old_orb%beta * E_new**3)
mc(5,6) = old_orb%vec(5) * mc2**2 * p0c * (mc(6,6) / (old_orb%beta * E_new**3) - &
                                     orb%beta / (old_orb%beta**2 * E**3))

mat6 = matmul(mc, mat6)

end subroutine mat6_coupler_kick

!---------------------------------------------------------------------------
!---------------------------------------------------------------------------
!---------------------------------------------------------------------------

subroutine lcavity_edge_kick_matrix (ele, param, grad_max, phase, orb, mat6)

use bmad_struct
use bmad_interface

implicit none

type (ele_struct)  ele
type (coord_struct)  orb
type (lat_param_struct) param

real(rp) grad_max, phase, k1, mat6(6,6)
real(rp) f, mc2, E, pc

!

pc = (1 + orb%vec(6)) * orb%p0c
E = pc / orb%beta
k1 = grad_max * cos(phase) / pc
f = grad_max * sin(phase) * twopi * ele%value(rf_frequency$) / (c_light * pc)
mc2 = mass_of(param%particle)

mat6(2,:) = mat6(2,:) + k1 * mat6(1,:) - k1 * orb%vec(1) * orb%p0c * mat6(6,:) / pc + &
      f * orb%vec(1) * (mat6(5,:) / orb%beta - orb%vec(5) * mc2**2 * orb%p0c * mat6(6,:) / (pc**2 * E))
mat6(4,:) = mat6(4,:) + k1 * mat6(3,:) - k1 * orb%vec(3) * orb%p0c * mat6(6,:) / pc + &
      f * orb%vec(3) * (mat6(5,:) / orb%beta - orb%vec(5) * mc2**2 * orb%p0c * mat6(6,:) / (pc**2 * E))

orb%vec(2) = orb%vec(2) + k1 * orb%vec(1)
orb%vec(4) = orb%vec(4) + k1 * orb%vec(3)

end subroutine lcavity_edge_kick_matrix

!---------------------------------------------------------------------------
!---------------------------------------------------------------------------
!---------------------------------------------------------------------------

subroutine bbi_kick_matrix (ele, param, orb, s_pos, mat6)

use bmad_struct
use bmad_interface, except_dummy => bbi_kick_matrix

implicit none

type (ele_struct)  ele
type (coord_struct)  orb
type (lat_param_struct) param

real(rp) x_pos, y_pos, del, sig_x, sig_y, coef, garbage, s_pos
real(rp) ratio, k0_x, k1_x, k0_y, k1_y, mat6(6,6), beta, bbi_const

!

call mat_make_unit (mat6)

sig_x = ele%value(sig_x$)
sig_y = ele%value(sig_y$)

if (sig_x == 0 .or. sig_y == 0) return

if (s_pos /= 0 .and. ele%a%beta /= 0) then
  beta = ele%a%beta - 2 * ele%a%alpha * s_pos + ele%a%gamma * s_pos**2
  sig_x = sig_x * sqrt(beta / ele%a%beta)
  beta = ele%b%beta - 2 * ele%b%alpha * s_pos + ele%b%gamma * s_pos**2
  sig_y = sig_y * sqrt(beta / ele%b%beta)
endif

x_pos = orb%vec(1) / sig_x  ! this has offset in it
y_pos = orb%vec(3) / sig_y

del = 0.001

ratio = sig_y / sig_x
call bbi_kick (x_pos, y_pos, ratio, k0_x, k0_y)
call bbi_kick (x_pos+del, y_pos, ratio, k1_x, garbage)
call bbi_kick (x_pos, y_pos+del, ratio, garbage, k1_y)

bbi_const = -param%n_part * ele%value(charge$) * classical_radius_factor /  &
                    (2 * pi * ele%value(p0c$) * (sig_x + sig_y))

coef = bbi_const / (ele%value(n_slice$) * del * (1 + orb%vec(6)))

mat6(2,1) = coef * (k1_x - k0_x) / sig_x
mat6(4,3) = coef * (k1_y - k0_y) / sig_y

end subroutine bbi_kick_matrix

!---------------------------------------------------------------------------
!---------------------------------------------------------------------------
!---------------------------------------------------------------------------
!+      
! Subroutine offset_photon_mat6 (mat6, ele)
!
! Subroutine to transform a 6x6 transfer matrix to a new reference frame
! with the given offsets, pitches and tilts of the given element.
!
! Modules needed:
!   use bmad
!
! Input:
!   mat6(6,6) -- Real(rp): Untilted matrix.
!   ele       -- Ele_struct: Mirror or equivalent.
!
! Output:
!   mat6(6,6) -- Real(rp): Tilted matrix.
!-

subroutine offset_photon_mat6 (mat6, ele)

use bmad_interface, dummy => offset_photon_mat6

implicit none

type (ele_struct), target :: ele

real(rp) mat6(6,6), mm(6,6)
real(rp), pointer :: p(:)
real(rp) ct, st
real(rp) c2g, s2g, offset(6), tilt, graze
real(rp) off(3), rot(3), project_x(3), project_y(3), project_s(3)

!

p => ele%value

! Set: Work backward form element mat6 matrix...

! Set: Graze angle error

if (p(graze_angle_err$) /= 0) then
  mat6(:,1) = mat6(:,1) + mat6(:,1) * p(graze_angle_err$) 
endif

! Set: Tilt

tilt = p(tilt_tot$) + p(tilt_err$)

if (tilt /= 0) then

  ct = cos(tilt)
  st = sin(tilt)

  mm(:,1) = mat6(:,1) * ct - mat6(:,3) * st
  mm(:,2) = mat6(:,2) * ct - mat6(:,4) * st
  mm(:,3) = mat6(:,3) * ct + mat6(:,1) * st
  mm(:,4) = mat6(:,4) * ct + mat6(:,2) * st
  mm(:,5) = mat6(:,5)
  mm(:,6) = mat6(:,6)

else
  mm = mat6
endif

! Set: transverse offsets and pitches

mm(:,1) = mm(:,1) + mm(:,5) * p(x_pitch_tot$) 
mm(:,3) = mm(:,3) + mm(:,5) + p(y_pitch_tot$)

! Set: z_offset

mm(:,2) = mm(:,2) + mm(:,1) * p(z_offset_tot$)
mm(:,4) = mm(:,4) + mm(:,3) * p(z_offset_tot$)

!------------------------------------------------------
! Unset: 

c2g = cos(2*p(graze_angle$)) 
s2g = sin(2*p(graze_angle$))

if (p(tilt_err$) /= 0) then
  ct = cos(p(tilt$)) 
  st = sin(p(tilt$))
endif

project_x = [c2g * ct**2 + st**2, -ct * st + c2g * ct * st, -ct * s2g ]
project_y = [-ct * st + c2g * ct * st, ct**2 + c2g * st**2, -s2g * st ]
project_s = [ct * s2g, s2g * st, c2g ]

! Unset: graze_angle_error

if (p(graze_angle_err$) /= 0) then
  mm(5,:) = mm(5,:) + p(graze_angle_err$) * mm(1,:)
endif

! Unset tilt

if (p(tilt$) /= 0) then
  mat6(1,:) = ct * mm(1,:) - st * mm(3,:)
  mat6(2,:) = ct * mm(2,:) - st * mm(4,:)
  mat6(3,:) = ct * mm(3,:) + st * mm(1,:)
  mat6(4,:) = ct * mm(4,:) + st * mm(2,:)
  mat6(5,:) =     mm(5,:)
  mat6(6,:) =     mm(6,:)
else
  mat6 = mm
endif

! Unset: tilt_err

if (p(tilt_err$) /= 0) then
  rot = project_s * p(tilt_err$)

  ct = cos(rot(3)) 
  st = sin(rot(3))

  mm(1,:) = ct * mat6(1,:) - st * mat6(3,:)
  mm(2,:) = ct * mat6(2,:) - st * mat6(4,:)
  mm(3,:) = ct * mat6(3,:) + st * mat6(1,:)
  mm(4,:) = ct * mat6(4,:) + st * mat6(2,:)
  mm(5,:) =     mat6(5,:)
  mm(6,:) =     mat6(6,:)

  mm(5,:) = mm(5,:) - rot(2) * mm(2,:) + rot(1) * mm(3,:)

  mat6 = mm

endif

! Unset pitch

rot = project_x * p(y_pitch_tot$) - project_y * p(x_pitch_tot$)
mat6(5,:) = mat6(5,:) + rot(2) * mat6(2,:) - rot(1) * mat6(3,:)

! Unset: offset

off = project_x * p(x_offset_tot$) + project_y * p(y_offset_tot$) + project_s * p(z_offset_tot$)

mat6(1,:) = mat6(1,:) - off(3) * mat6(2,:)
mat6(3,:) = mat6(3,:) - off(3) * mat6(4,:)

end subroutine offset_photon_mat6

