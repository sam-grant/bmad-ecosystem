!+
! Subroutine make_mat6_bmad_photon (ele, param, c0, c1, err)
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
!
! Output:
!   ele    -- Ele_struct: Element with transfer matrix.
!     %vec0  -- 0th order map component
!     %mat6  -- 6x6 transfer matrix.
!   c1     -- Coord_struct: Coordinates at the end of element.
!   err    -- Logical, optional: Set True if there is an error. False otherwise.
!-

subroutine make_mat6_bmad_photon (ele, param, c0, c1, err)

use bmad_interface, dummy => make_mat6_bmad_photon

implicit none

type (ele_struct), target :: ele
type (coord_struct) :: c0, c1
type (lat_param_struct)  param

real(rp), pointer :: mat6(:,:), v(:)

logical, optional :: err
character(*), parameter :: r_name = 'make_mat6_bmad'

!--------------------------------------------------------
! init

if (present(err)) err = .false.

mat6 => ele%mat6
v => ele%value

call mat_make_unit (mat6)
ele%vec0 = 0

select case (ele%key)

!--------------------------------------------------------
! Crystal

case (crystal$, sample$, photon_init$)

  ! Not yet implemented

!--------------------------------------------------------
! multilayer_mirror

case (multilayer_mirror$) 

  ! Not yet implemented

!--------------------------------------------------------
! patch

case (patch$)

  ! Not yet implemented

end select

end subroutine make_mat6_bmad_photon
