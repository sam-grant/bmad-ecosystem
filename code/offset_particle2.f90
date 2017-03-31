!+
! Subroutine offset_particle2 (ele, param, set, orbit, set_tilt, set_multipoles, set_hvkicks, set_z_offset, 
!                                                                           ds_pos, set_spin, mat6, make_matrix)
!
! Routine to transform a particles's coordinates between laboratory and element coordinates
! at the ends of the element. Additionally, this routine will:
!   a) Apply the half kicks due to multipole and kick attributes.
!   b) Add drift transform to the coordinates due to nonzero %value(z_offset_tot$).
!
! set = set$:
!    Transforms from lab to element coords. 
!    If ds_pos is not present:
!      If coord%direction = +1 -> Assume the particle is at the upstream (-S) end.
!      If coord%direction = -1 -> Assume the particle is at the downstream (+S) end.
!
! set = unset$:
!    Transforms from element to lab coords.
!    If ds_pos is not present:
!      If coord%direction = +1 -> Assume the particle is at the downstream (+S) end.
!      If coord%direction = -1 -> Assume the particle is at the upstream (-S) end.
!
! Note: If ele%orientation = -1 then the upstream end is the exit end of the element and 
!   the downstream end is the entrance end of the element.
!
! Options:
!   Using the element tilt in the offset.
!   Using the HV kicks.
!   Using the multipoles.
!
! Modules Needed:
!   use bmad
!
! Input:
!   ele            -- Ele_struct: Element
!     %value(x_offset$) -- Horizontal offset of element.
!     %value(x_pitch$)  -- Horizontal pitch of element.
!     %value(tilt$)     -- tilt of element.
!   param          -- lat_param_strcut: 
!     %particle             -- Reference particle
!   set            -- Logical: 
!                    T (= set$)   -> Translate from lab coords to the local element coords.
!                    F (= unset$) -> Translate back from element to lab coords.
!   orbit          -- Coord_struct: Coordinates of the particle.
!   set_tilt       -- Logical, optional: Default is True.
!                    T -> Rotate using ele%value(tilt$) and ele%value(roll$) for sbends.
!                    F -> Do not rotate
!   set_multipoles -- Logical, optional: Default is True.
!                    T -> 1/2 of the multipole is applied.
!   set_hvkicks    -- Logical, optional: Default is True.
!                    T -> Apply 1/2 any hkick or vkick.
!   set_z_offset   -- Logical, optional: Default is True.
!                    T -> Particle will be translated by ele%value(z_offset$) to propagate between the nominal
!                           edge of the element and the true physical edge of the element.
!                    F -> Do no translate. Used by save_a_step routine.
!   ds_pos         -- Real(rp), optional: Longitudinal particle position relative to upstream end.
!                    If not present then, for orbit%direction = 1,  ds_pos = 0 is assumed when set = T and 
!                    ds_pos = ele%value(l$) when set = F. And vice versa when orbit%direction = -1.
!   set_spin       -- Logical, optional: Default if False.
!                    Rotate spin coordinates? Also bmad_com%spin_tracking_on must be T to rotate.
!                                               
! Output:
!     orbit -- Coord_struct: Coordinates of particle.
!-

subroutine offset_particle2 (ele, param, set, orbit, set_tilt, set_multipoles, set_hvkicks, set_z_offset, &
                                                                            ds_pos, set_spin, mat6, make_matrix)

use geometry_mod, except_dummy => offset_particle2
use multipole_mod, only: multipole_ele_to_kt, multipole_kicks
use spin_mod, only: rotate_spin, rotate_spin_given_field 
use rotation_3d_mod

implicit none

type (ele_struct) :: ele
type (lat_param_struct) param
type (coord_struct), intent(inout) :: orbit
type (em_field_struct) field
type (floor_position_struct) position

real(rp) rel_p, knl(0:n_pole_maxx), tilt(0:n_pole_maxx), dx, f, B_factor, ds_center
real(rp) angle, z_rel_center, xp, yp, x_off, y_off, z_off, off(3), m_trans(3,3)
real(rp) cos_a, sin_a, cos_t, sin_t, beta, charge_dir, dz, pvec(3), cos_r, sin_r
real(rp) rot(3), dr(3), rel_tracking_charge, rtc, Ex, Ey, kx, ky, length
real(rp) an(0:n_pole_maxx), bn(0:n_pole_maxx), ws(3,3), L_mis(3), p_vec(3), roll
real(rp), optional :: ds_pos, mat6(6,6)

integer particle, sign_z_vel
integer n, ix_pole_max

logical, intent(in) :: set
logical, optional, intent(in) :: set_tilt, set_multipoles, set_spin
logical, optional, intent(in) :: set_hvkicks, set_z_offset
logical, optional :: make_matrix
logical set_multi, set_hv, set_t, set_hv1, set_hv2, set_z_off, set_spn

!---------------------------------------------------------------         

rel_p = (1 + orbit%vec(6))

set_multi  = logic_option (.true., set_multipoles)
set_hv     = logic_option (.true., set_hvkicks) .and. ele%is_on .and. &
                   (has_kick_attributes(ele%key) .or. has_hkick_attributes(ele%key))
set_t      = logic_option (.true., set_tilt) .and. has_orientation_attributes(ele)
set_z_off  = logic_option (.true., set_z_offset) .and. has_orientation_attributes(ele)
set_spn    = logic_option (.false., set_spin) .and. bmad_com%spin_tracking_on

sign_z_vel = ele%orientation * orbit%direction
rel_tracking_charge = rel_tracking_charge_to_mass (orbit, param)
charge_dir = rel_tracking_charge * sign_z_vel 
length = ele%value(l$)

if (set_hv) then
  select case (ele%key)
  case (elseparator$, kicker$, hkicker$, vkicker$)
    set_hv1 = .false.
    set_hv2 = .true.
  case default
    set_hv1 = .true.
    set_hv2 = .false.
  end select
else
  set_hv1 = .false.
  set_hv2 = .false.
endif

if (set_spn) B_factor = ele%value(p0c$) / (charge_of(param%particle) * c_light)

!----------------------------------------------------------------
! Set...

if (set) then

  ! Set: Offset and pitch

  if (has_orientation_attributes(ele)) then

    ! ds_center is distance to the center of the element from the particle position
    if (present(ds_pos)) then
      ds_center = ele%orientation * (length/2 - ds_pos)   
    else
      ds_center = sign_z_vel * length / 2
    endif

    x_off = ele%value(x_offset_tot$)
    y_off = ele%value(y_offset_tot$)
    z_off = ele%value(z_offset_tot$)
    xp    = ele%value(x_pitch_tot$)
    yp    = ele%value(y_pitch_tot$)
    roll  = 0
    if (ele%key == sbend$) roll = ele%value(roll$)

    if (x_off /= 0 .or. y_off /= 0 .or. z_off /= 0 .or. xp /= 0 .or. yp /= 0 .or. roll /= 0) then
            
      position%r = [orbit%vec(1), orbit%vec(3), 0.0_rp]
      call mat_make_unit (position%w)

      if (ele%key == sbend$ .and. ele%value(g$) /= 0) then
        
        call mat_make_unit(position%w)
        position = bend_shift(position, ele%value(g$), ds_center, tilt = ele%value(ref_tilt_tot$))

        call ele_misalignment_L_S_calc(ele, L_mis, ws)
        position%r = matmul(ws, position%r) + L_mis
        position%w = matmul(ws, position%w)

        if (ele%value(ref_tilt_tot$) == 0) then
          position = bend_shift(position, ele%value(g$), -ds_center)
        else
          position = bend_shift(position, ele%value(g$), ele%value(L$)/2, tilt = ele%value(ref_tilt_tot$))
          ws = w_mat_for_tilt(ele%value(ref_tilt_tot$))
          position%r = matmul(ws, position%r)
          position%w = matmul(ws, position%w)
          position = bend_shift(position, ele%value(g$), -ds_center, tilt = ele%value(ref_tilt_tot$))
        endif        

      ! Else not a bend

      else
        call floor_angles_to_w_mat (xp, yp, 0.0_rp, w_mat_inv = ws)
        position%r  = position%r - [x_off, y_off, z_off+ds_center]
        position%r = matmul(ws, position%r)
        position%w = matmul(ws, position%w)
        position%r(3) = position%r(3) + ds_center ! Angle offsets are relative to the center of the element
      endif

    endif    ! has nonzero offset or pitch

    p_vec = [orbit%vec(2), orbit%vec(4), sign_z_vel * sqrt(rel_p**2 - orbit%vec(2)**2 - orbit%vec(4)**2)]
    p_vec = matmul(position%w, p_vec)
    orbit%vec(2:4:2) = p_vec(1:2)
    orbit%vec(1:3:2) = position%r(1:2)

    if (set_z_off .and. position%r(3) /= 0) then
      call track_a_drift (orbit, -sign_z_vel*position%r(3))
      orbit%vec(5) = orbit%vec(5) + sign_z_vel*position%r(3)  ! Correction due to reference particle is also offset.
    endif
  
    if (set_spn) orbit%spin = matmul(position%w, orbit%spin)

  endif   ! has orientation attributes

  ! Set: HV kicks for quads, etc. but not hkicker, vkicker, elsep and kicker elements.
  ! HV kicks must come after z_offset but before any tilts are applied.
  ! Note: Change in %vel is NOT dependent upon energy since we are using
  ! canonical momentum.
  ! Note: Since this is applied before tilt_coords, kicks are independent of any tilt.

  if (set_hv1) then
    orbit%vec(2) = orbit%vec(2) + charge_dir * ele%value(hkick$) / 2
    orbit%vec(4) = orbit%vec(4) + charge_dir * ele%value(vkick$) / 2
    if (set_spn) call rotate_spin_given_field (orbit, sign_z_vel, (B_factor / 2) * [ele%value(vkick$), -ele%value(hkick$), 0.0_rp])
  endif

  ! Set: Tilt

  if (set_t .and. ele%key /= sbend$) then
    call tilt_coords (ele%value(tilt_tot$), orbit%vec)
    if (set_spn) call rotate_spin ([0.0_rp, 0.0_rp, -ele%value(tilt_tot$)], orbit%spin)
  endif

  ! Set: Multipoles

  if (set_multi) then
    call multipole_ele_to_kt(ele, .false., ix_pole_max, knl, tilt)
    if (ix_pole_max > -1) then
      call multipole_kicks (knl/2, tilt, param%particle, ele, orbit)
      if (set_spn) call multipole_spin_precession (ele, param, orbit)
    endif

    call multipole_ele_to_ab(ele, .false., ix_pole_max, an, bn, electric$)
    if (ix_pole_max > -1) then
      do n = 0, n_pole_maxx
        if (an(n) == 0 .and. bn(n) == 0) cycle
        call ab_multipole_kick (an(n), bn(n), n, param%particle, ele%orientation, orbit, kx, ky, pole_type = electric$, scale = length/2)
        ! Note that there is no energy kick since, with the fringe fields, the net result when both ends
        ! Are taken into account is not to have any energy shifts.
        orbit%vec(2) = orbit%vec(2) + kx
        orbit%vec(4) = orbit%vec(4) + ky
        if (set_spn) then
          call elec_multipole_field(an(n), bn(n), n, orbit, Ex, Ey)
          call rotate_spin_given_field (orbit, sign_z_vel, EL = [Ex, Ey, 0.0_rp] * (length/2))
        endif
      enddo
    endif
  endif

  ! Set: HV kicks for kickers and separators only.
  ! Note: Since this is applied after tilt_coords, kicks are dependent on any tilt.

  if (set_hv2) then
    if (ele%key == elseparator$) then
      rtc = abs(rel_tracking_charge) * sign(1, charge_of(orbit%species))
      orbit%vec(2) = orbit%vec(2) + rtc * ele%value(hkick$) / 2
      orbit%vec(4) = orbit%vec(4) + rtc * ele%value(vkick$) / 2
      if (set_spn .and. ele%value(e_field$) /= 0) call rotate_spin_given_field (orbit, sign_z_vel, &
                                             EL = [ele%value(hkick$), ele%value(vkick$), 0.0_rp] * (ele%value(p0c$) / 2))
    elseif (ele%key == hkicker$) then
      orbit%vec(2) = orbit%vec(2) + charge_dir * ele%value(kick$) / 2
      if (set_spn) call rotate_spin_given_field (orbit, sign_z_vel, (B_factor / 2) * [0.0_rp, -ele%value(kick$), 0.0_rp])
    elseif (ele%key == vkicker$) then
      orbit%vec(4) = orbit%vec(4) + charge_dir * ele%value(kick$) / 2
      if (set_spn) call rotate_spin_given_field (orbit, sign_z_vel, (B_factor / 2) * [ele%value(kick$), 0.0_rp, 0.0_rp])
    else
      orbit%vec(2) = orbit%vec(2) + charge_dir * ele%value(hkick$) / 2
      orbit%vec(4) = orbit%vec(4) + charge_dir * ele%value(vkick$) / 2
      if (set_spn) call rotate_spin_given_field (orbit, sign_z_vel, (B_factor / 2) * [ele%value(vkick$), -ele%value(hkick$), 0.0_rp])
    endif
  endif

!----------------------------------------------------------------
! Unset... 

else

  if (present(ds_pos)) then
    z_rel_center = ele%orientation * (ds_pos - length/2)  ! position relative to center.
  elseif (orbit%direction == 1) then   ! Exiting at downstream end
    z_rel_center = ele%orientation * length / 2
  else                   ! orbit%direction == -1 -> Exiting at upstream end
    z_rel_center = -ele%orientation * length / 2
  endif

  ! Unset: HV kicks for kickers and separators only.

  if (set_hv2) then
    if (ele%key == elseparator$) then
      rtc = abs(rel_tracking_charge) * sign(1, charge_of(orbit%species))
      orbit%vec(2) = orbit%vec(2) + rtc * ele%value(hkick$) / 2
      orbit%vec(4) = orbit%vec(4) + rtc * ele%value(vkick$) / 2
      if (set_spn .and. ele%value(e_field$) /= 0) call rotate_spin_given_field (orbit, sign_z_vel, &
                                         EL = [ele%value(hkick$), ele%value(vkick$), 0.0_rp] * (ele%value(p0c$) / 2))
    elseif (ele%key == hkicker$) then
      orbit%vec(2) = orbit%vec(2) + charge_dir * ele%value(kick$) / 2
      if (set_spn) call rotate_spin_given_field (orbit, sign_z_vel, (B_factor / 2) * [0.0_rp, -ele%value(kick$), 0.0_rp])
    elseif (ele%key == vkicker$) then
      orbit%vec(4) = orbit%vec(4) + charge_dir * ele%value(kick$) / 2
      if (set_spn) call rotate_spin_given_field (orbit, sign_z_vel, (B_factor / 2) * [ele%value(kick$), 0.0_rp, 0.0_rp])
    else
      orbit%vec(2) = orbit%vec(2) + charge_dir * ele%value(hkick$) / 2
      orbit%vec(4) = orbit%vec(4) + charge_dir * ele%value(vkick$) / 2
      if (set_spn) call rotate_spin_given_field (orbit, sign_z_vel, (B_factor / 2) * [ele%value(vkick$), -ele%value(hkick$), 0.0_rp])
    endif
  endif

  ! Unset: Multipoles

  if (set_multi) then
    call multipole_ele_to_kt(ele, .false., ix_pole_max, knl, tilt)
    if (ix_pole_max > -1) then
      call multipole_kicks (knl/2, tilt, param%particle, ele, orbit)
      if (set_spn) call multipole_spin_precession (ele, param, orbit)
    endif

    call multipole_ele_to_ab(ele, .false., ix_pole_max, an, bn, electric$)
    if (ix_pole_max > -1) then
      do n = 0, n_pole_maxx
        if (an(n) == 0 .and. bn(n) == 0) cycle
        call ab_multipole_kick (an(n), bn(n), n, param%particle, ele%orientation, orbit, kx, ky, pole_type = electric$, scale = length/2)
        ! Note that there is no energy kick since, with the fringe fields, the net result when both ends
        ! Are taken into account is not to have any energy shifts.
        orbit%vec(2) = orbit%vec(2) + kx
        orbit%vec(4) = orbit%vec(4) + ky
        if (set_spn) then
          call elec_multipole_field(an(n), bn(n), n, orbit, Ex, Ey)
          call rotate_spin_given_field (orbit, sign_z_vel, EL = [Ex, Ey, 0.0_rp] * (length/2))
        endif
      enddo
    endif
  endif

  ! Unset: Tilt & Roll

  if (set_t) then

    if (ele%key == sbend$ .and. ele%value(roll_tot$) /= 0) then
      angle = ele%value(g$) * z_rel_center * orbit%direction
      off = [orbit%vec(1), orbit%vec(3), 0.0_rp]

      sin_r = sin(ele%value(roll$)); cos_r = cos(ele%value(roll$))
      sin_a = sin(angle);            cos_a = cos(angle)

      m_trans(1,:) = [cos_r * cos_a**2 + sin_a**2, -cos_a * sin_r, (1 - cos_r) * cos_a * sin_a]
      m_trans(2,:) = [cos_a * sin_r,               cos_r,          -sin_r * sin_a]
      m_trans(3,:) = [(1 - cos_r) * cos_a * sin_a, sin_r * sin_a,  cos_r * sin_a**2 + cos_a**2]

      off =  matmul(m_trans, [orbit%vec(1), orbit%vec(3), 0.0_rp])
      pvec = matmul(m_trans, [orbit%vec(2), orbit%vec(4), sqrt(rel_p**2 - orbit%vec(2)**2 - orbit%vec(4)**2)])
      orbit%vec(1) = off(1); orbit%vec(3) = off(2)
      orbit%vec(2) = pvec(1); orbit%vec(4) = pvec(2)

      if (set_spn) orbit%spin = matmul(m_trans, orbit%spin)

      ! If ds_pos is present then the transformation is not at the end of the bend.
      ! In this case there is an offset from the coordinate system and the roll axis of rotation

      if (present(ds_pos)) then
        dx = cos_a - cos(ele%value(angle$)/2)
        off = off + dx * [-cos_a * sin_r, cos_r - 1, sin_a * sin_r]
      endif

      ! Drift - off(3) but remember the ref particle is not moving.
      orbit%vec(1) = off(1) - off(3) * pvec(1) / pvec(3)
      orbit%vec(2) = pvec(1)
      orbit%vec(3) = off(2) - off(3) * pvec(2) / pvec(3)
      orbit%vec(4) = pvec(2)
      orbit%vec(5) = orbit%vec(5) + off(3) * rel_p / pvec(3) 
      orbit%t = orbit%t - off(3) * rel_p / (pvec(3) * c_light * orbit%beta)

    endif

    if (ele%key == sbend$) then
      call tilt_coords (-ele%value(ref_tilt_tot$), orbit%vec)
      if (set_spn) call rotate_spin ([0.0_rp, 0.0_rp, ele%value(ref_tilt_tot$)], orbit%spin)
    else
      call tilt_coords (-ele%value(tilt_tot$), orbit%vec)
      if (set_spn) call rotate_spin ([0.0_rp, 0.0_rp, ele%value(tilt_tot$)], orbit%spin)
    endif

  endif

  ! UnSet: HV kicks for quads, etc. but not hkicker, vkicker, elsep and kicker elements.
  ! HV kicks must come after z_offset but before any tilts are applied.
  ! Note: Change in %vel is NOT dependent upon energy since we are using
  ! canonical momentum.

  if (set_hv1) then
    orbit%vec(2) = orbit%vec(2) + charge_dir * ele%value(hkick$) / 2
    orbit%vec(4) = orbit%vec(4) + charge_dir * ele%value(vkick$) / 2
    if (set_spn) call rotate_spin_given_field (orbit, sign_z_vel, &
                                    (B_factor / 2) * [ele%value(vkick$), -ele%value(hkick$), 0.0_rp])
  endif

  ! Unset: Offset and pitch

  if (has_orientation_attributes(ele)) then

    ! If a bend then must rotate the offsets from the coordinates at the center of the bend
    ! to the exit coordinates. This rotation is just the coordinate transformation for the
    ! whole bend except with half the bending angle.

    x_off = ele%value(x_offset_tot$)
    y_off = ele%value(y_offset_tot$)
    z_off = ele%value(z_offset_tot$)
    xp    = ele%value(x_pitch_tot$)
    yp    = ele%value(y_pitch_tot$)

    if (x_off /= 0 .or. y_off /= 0 .or. z_off /= 0 .or. xp /= 0 .or. yp /= 0) then

      if (ele%key == sbend$ .and. ele%value(g$) /= 0) then
        angle = ele%value(g$) * z_rel_center
        cos_a = cos(angle); sin_a = sin(angle)
        dr = [2 * sin(angle/2)**2 / ele%value(g$), 0.0_rp, sin_a / ele%value(g$)]

        if (ele%value(ref_tilt_tot$) == 0) then
          off = [cos_a * x_off + sin_a * z_off, y_off, -sin_a * x_off + cos_a * z_off]
          rot = [-cos_a * yp, xp, sin_a * yp]
        else
          cos_t = cos(ele%value(ref_tilt_tot$));    sin_t = sin(ele%value(ref_tilt_tot$))
          m_trans(1,:) = [cos_a * cos_t**2 + sin_t**2, (cos_a - 1) * cos_t * sin_t, cos_t * sin_a]
          m_trans(2,:) = [(cos_a - 1) * cos_t * sin_t, cos_a * sin_t**2 + cos_t**2, sin_a * sin_t]
          m_trans(3,:) = [-cos_t * sin_a, -sin_a * sin_t, cos_a]
          off = matmul(m_trans, [x_off, y_off, z_off])
          rot = matmul(m_trans, [-yp, xp, 0.0_rp])
          dr = [cos_t * dr(1) - sin_t * dr(2), sin_t * dr(1) + cos_t * dr(2), dr(3)]
        endif

        if (any(rot /= 0)) then
          call axis_angle_to_w_mat (rot, norm2(rot), m_trans)
          off = off + matmul(m_trans, dr) - dr
        endif

        orbit%vec(5) = orbit%vec(5) - sign_z_vel * (rot(2) * orbit%vec(1) - rot(1) * orbit%vec(3))
        orbit%vec(1) = orbit%vec(1) + off(1)
        orbit%vec(2) = orbit%vec(2) + sign_z_vel * rot(2) * rel_p
        orbit%vec(3) = orbit%vec(3) + off(2)
        orbit%vec(4) = orbit%vec(4) - sign_z_vel * rot(1) * rel_p

        if (set_spn) call rotate_spin (rot, orbit%spin)

        z_off = off(3)

      ! Else not a bend

      else
        ! Note: dz needs to be zero if orbit%beta = 0
        dz = -sign_z_vel * (xp * orbit%vec(1) + yp * orbit%vec(3) + (xp**2 + yp**2) * z_rel_center / 2)
        if (dz /= 0) then
          orbit%t = orbit%t - dz / (orbit%beta * c_light) 
          orbit%vec(5) = orbit%vec(5) + dz
        endif
        orbit%vec(1) = orbit%vec(1) + x_off + xp * z_rel_center
        orbit%vec(2) = orbit%vec(2) + sign_z_vel * xp * rel_p
        orbit%vec(3) = orbit%vec(3) + y_off + yp * z_rel_center
        orbit%vec(4) = orbit%vec(4) + sign_z_vel * yp * rel_p
        if (set_spn) call rotate_spin ([-yp, xp, 0.0_rp], orbit%spin)
      endif

      if (z_off /= 0 .and. set_z_off) then
        call track_a_drift (orbit, -sign_z_vel*z_off)
        orbit%vec(5) = orbit%vec(5) + sign_z_vel*z_off  ! Correction due to reference particle is also offset.
      endif
    endif

  endif   ! Has orientation attributes

endif

end subroutine offset_particle2

!--------------------------------------------------------------------------
!--------------------------------------------------------------------------
!--------------------------------------------------------------------------
!+
! Subroutine multipole_spin_precession (ele, param, orbit)
!
! Subroutine to track the spins in a multipole field.
! Only half the field is used.
!
! Input:
!   ele              -- Ele_struct: Element
!     %value(x_pitch$)        -- Horizontal roll of element.
!     %value(y_pitch$)        -- Vertical roll of element.
!     %value(tilt$)           -- Tilt of element.
!     %value(roll$)           -- Roll of dipole.
!   param            -- Lat_param_struct
!   orbit            -- coord_struct: Coordinates of the particle.
!   do_half_prec     -- Logical, optional: Default is False.
!                          Apply half multipole effect only (for kick-drift-kick model)
!   include_sextupole_octupole  -- Logical, optional: Default is False.
!                          Include the effects of sextupoles and octupoles
!
! Output:
!   spin(2)          -- Complex(rp): Resultant spin
!-

subroutine multipole_spin_precession (ele, param, orbit)

use multipole_mod, only: multipole_ele_to_ab

use spin_mod, dummy => multipole_spin_precession

implicit none

type (ele_struct) :: ele
type (lat_param_struct) param
type (coord_struct) orbit

complex(rp) kick, pos

real(rp) an(0:n_pole_maxx), bn(0:n_pole_maxx), knl

integer n, sign_z_vel, ix_pole_max

!

call multipole_ele_to_ab(ele, .false., ix_pole_max, an, bn)
if (ix_pole_max == -1) return

! calculate kick_angle (for particle) and unit vector (Bx, By) parallel to B-field
! according to bmad manual, chapter "physics", section "Magnetic Fields"
! kick = qL/P_0*(B_y+i*Bx) = \sum_n (b_n+i*a_n)*(x+i*y)^n

kick = bn(0) + i_imaginary * an(0)
pos = orbit%vec(1) + i_imaginary * orbit%vec(3)
if (pos /= 0) then
  kick = kick + (bn(1) + i_imaginary * an(1)) * pos
  do n = 2, max_nonzero(0, an, bn)
    pos = pos * (orbit%vec(1) + i_imaginary * orbit%vec(3))
    kick = kick + (bn(n) + i_imaginary * an(n)) * pos
  enddo
endif

! Rotate spin

sign_z_vel = orbit%direction * ele%orientation

if (kick /= 0) then
  call rotate_spin_given_field (orbit, sign_z_vel, &
            [aimag(kick), real(kick), 0.0_rp] * (ele%value(p0c$) / (2 * charge_of(param%particle) * c_light)))
endif

! calculate rotation of local coordinate system due to dipole component

if (ele%key == multipole$ .and. (bn(0) /= 0 .or. an(0) /= 0)) then
  kick = bn(0) + i_imaginary * an(0)
  call rotate_spin ([-aimag(kick), -real(kick), 0.0_rp], orbit%spin)
endif

end subroutine multipole_spin_precession
