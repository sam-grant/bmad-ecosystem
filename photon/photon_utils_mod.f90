module photon_utils_mod

use bmad_interface

implicit none

contains

!-----------------------------------------------------------------------------------------------
!-----------------------------------------------------------------------------------------------
!-----------------------------------------------------------------------------------------------
!+
! Function photon_type (ele) result (e_type)
!
! Routine to return the type of photon to be tracked: coherent$ or incoherent$.
!
! Input:
!   ele -- ele_struct: Element being tracked through.
!
! Output:
!   e_type -- integer: coherent$ or incoherent$
!-

function photon_type (ele) result (e_type)

type (ele_struct) ele
type (branch_struct), pointer :: branch
integer e_type

! Use

e_type = incoherent$   ! Default

if (associated(ele%branch)) then
  branch => pointer_to_branch(ele)
  e_type = branch%lat%photon_type
endif

end function photon_type

!-----------------------------------------------------------------------------------------------
!-----------------------------------------------------------------------------------------------
!-----------------------------------------------------------------------------------------------
!+
! Function z_at_surface (ele, x, y, status) result (z)
!
! Routine return the height (z) of the surface for a particular (x,y) position. 
! Remember: +z points into the element.
!
! Input:
!   ele         -- ele_struct: Element
!   x, y        -- real(rp): coordinates on surface.
!
! Output:
!   z           -- real(rp): z coordinate.
!   status      -- integer: 0 -> Everythin OK.
!                           1 -> Cannot compute z due to point being outside of ellipseoid bounds.
!-

function z_at_surface (ele, x, y, status) result (z)

type (ele_struct), target :: ele
type (photon_surface_struct), pointer :: surf

real(rp) x, y, z, g(3), f
integer status, ix, iy

!

surf => ele%photon%surface
status = 0

if (surf%grid%type == segmented$) then
  call init_surface_segment (x, y, ele)

  z = surf%segment%z0 - (x - surf%segment%x0) * surf%segment%slope_x - &
                        (y - surf%segment%y0) * surf%segment%slope_y

else
  z = 0
  do ix = 0, ubound(surf%curvature_xy, 1)
  do iy = 0, ubound(surf%curvature_xy, 2) - ix
    if (ele%photon%surface%curvature_xy(ix, iy) == 0) cycle
    z = z - surf%curvature_xy(ix, iy) * x**ix * y**iy
  enddo
  enddo

  g = surf%spherical_curvature + surf%elliptical_curvature
  f = -sign_of(g(1)) * (g(1) * x)**2 - sign_of(g(2)) * (g(2) * y)**2
  if (f < -1) then
    status = 1
    return
  endif
  if (g(3) /= 0) z = z + sqrt_one(f) / g(3)
endif

end function z_at_surface

!-----------------------------------------------------------------------------------------------
!-----------------------------------------------------------------------------------------------
!-----------------------------------------------------------------------------------------------
!+
! Subroutine init_surface_segment (x, y, ele)
!
! Routine to init the componentes in ele%photon%surface%segment for use with segmented surface calculations.
! The segment used is determined by the (x,y) photon coordinates
!
! Input:
!   x, y   -- Real(rp): Coordinates of the photon.
!   ele    -- ele_struct: Elment containing a surface.
!
! Output:
!   ele    -- ele_struct: Element with ele%photon%surface%segment initialized.
!-

subroutine init_surface_segment (x, y, ele)

type (ele_struct), target :: ele
type (photon_surface_struct), pointer :: s
type (segmented_surface_struct), pointer :: seg

real(rp) x, y, zt, x0, y0, dx, dy, coef_xx, coef_xy, coef_yy, coef_diag, g(3)
integer ix, iy, sx, sy

! Only redo the cacluation if needed

s => ele%photon%surface
seg => s%segment

ix = nint(x / s%grid%dr(1))
iy = nint(y / s%grid%dr(2))

if (ix == seg%ix .and. iy == seg%iy) return

!

x0 = ix * s%grid%dr(1)
y0 = iy * s%grid%dr(2)

seg%ix = ix
seg%iy = iy

seg%x0 = x0
seg%y0 = y0
seg%z0 = 0

seg%slope_x = 0
seg%slope_y = 0
coef_xx = 0; coef_xy = 0; coef_yy = 0

do ix = 0, ubound(s%curvature_xy, 1)
do iy = 0, ubound(s%curvature_xy, 2) - ix
  if (s%curvature_xy(ix, iy) == 0) cycle
  seg%z0 = seg%z0 - s%curvature_xy(ix, iy) * x0**ix * y0**iy
  if (ix > 0) seg%slope_x = seg%slope_x - ix * s%curvature_xy(ix, iy) * x0**(ix-1) * y0**iy
  if (iy > 0) seg%slope_y = seg%slope_y - iy * s%curvature_xy(ix, iy) * x0**ix * y0**(iy-1)
  if (ix > 1) coef_xx = coef_xx - ix * (ix-1) * s%curvature_xy(ix, iy) * x0**(ix-2) * y0**iy / 2
  if (iy > 1) coef_yy = coef_yy - iy * (iy-1) * s%curvature_xy(ix, iy) * x0**ix * y0**(iy-2) / 2
  if (ix > 0 .and. iy > 0) coef_xy = coef_xy - ix * iy * s%curvature_xy(ix, iy) * x0**(ix-1) * y0**(iy-1)
enddo
enddo

g = s%spherical_curvature + s%elliptical_curvature
if (g(3) /= 0) then
  sx = sign_of(g(1)); sy = sign_of(g(2))
  zt = sqrt(1 - sx * (x0 * g(1))**2 - sy * (y0 * g(2))**2)
  seg%z0 = seg%z0 + sqrt_one(-sx * (g(1) * x)**2 - sy * (g(2) * y)**2) / g(3)
  seg%slope_x = seg%slope_x - x0 * sx * g(1)**2 / (g(3) * zt)
  seg%slope_y = seg%slope_y - y0 * sy * g(2)**2 / (g(3) * zt)
  coef_xx = coef_xx - (sx * g(1)**2 / zt - (x0 * g(1)**2)**2 / zt**3) / (2 * g(3))
  coef_yy = coef_yy - (sy * g(2)**2 / zt - (y0 * g(2)**2)**2 / zt**3) / (2 * g(3))
  coef_xy = coef_xy - (x0 * y0 * sx * sy * (g(1) * g(2))**2 / zt**3) / (g(3))
endif

! Correct for fact that segment is supported at the corners of the segment and the segment is flat.
! This correction only affects z0 and not the slopes

dx = s%grid%dr(1) / 2
dy = s%grid%dr(2) / 2
coef_xx = coef_xx * dx**2
coef_xy = coef_xy * dx * dy
coef_yy = coef_yy * dy**2
coef_diag = coef_xx + coef_yy - abs(coef_xy)

if (abs(coef_diag) > abs(coef_xx) .and. abs(coef_diag) > abs(coef_yy)) then
  seg%z0 = seg%z0 + coef_diag
else if (abs(coef_xx) > abs(coef_yy)) then
  seg%z0 = seg%z0 + coef_xx
else
  seg%z0 = seg%z0 + coef_yy
endif

end Subroutine init_surface_segment 

end module
