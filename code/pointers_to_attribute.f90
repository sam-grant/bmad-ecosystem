!+
! Subroutine pointers_to_attribute (lat, ele_name, attrib_name, do_allocation,
!                     ptr_array, err_flag, err_print_flag, ix_eles, ix_attrib)
!
! Returns an array of pointers to an attribute with name attrib_name within 
! elements with name ele_name.
! Note: ele_name = 'BUNCH_START' corresponds to the lat%bunch_start substructure. 
! Note: ele_name can be a list of element indices
! Note: Use attribute_free to see if the attribute may be varied independently.
!
! Modules needed:
!   use bmad
!
! Input:
!   lat             -- Ring_struct: Lattice.
!   ele_name        -- Character(*): Element name. Must be uppercase
!   attrib_name     -- Character(*): Attribute name. Must be uppercase.
!                       For example: "HKICK".
!   do_allocation   -- Logical: If True then do an allocation if needed.
!                       EG: The multipole An and Bn arrays need to be allocated
!                       before their use.
!   err_print_flag  -- Logical, optional: If present and False then supress
!                       printing of an error message on error.
!
! Output:
!   ptr_array(:) -- Real_array_struct, allocatable: Pointer to the attribute.
!                     Pointer will be deassociated if there is a problem.
!   err_flag     -- Logical: Set True if attribtute not found or attriubte
!                     cannot be changed directly.
!   ix_eles(:)   -- Integer, optional, allocatable: List of element indexes 
!                     in lat%ele_(:) array. Set to -1 if not applicable.
!   ix_attrib    -- Integer, optional: If applicable then this is the index to the 
!                     attribute in the ele%value(:) array.
!-

#include "CESR_platform.inc"

Subroutine pointers_to_attribute (lat, ele_name, attrib_name, do_allocation, &
                        ptr_array, err_flag, err_print_flag, ix_eles, ix_attrib)

use bmad_struct
use bmad_interface, except => pointers_to_attribute

implicit none

type (ring_struct), target :: lat
type (ele_struct), target :: bunch_start
type (ele_struct), pointer :: ele
type (real_array_struct), allocatable :: ptr_array(:)

integer, optional :: ix_attrib
integer, optional, allocatable :: ix_eles(:)
integer n, i, ix

character(*) ele_name
character(100) ele_name_temp
character(*) attrib_name
character(24) :: r_name = 'pointers_to_attribute'

logical err_flag, do_allocation, do_print
logical, optional :: err_print_flag
logical, save, allocatable :: this_ele(:)

! init

err_flag = .false.
do_print = logic_option (.true., err_print_flag)

! bunch_start

if (ele_name == 'BUNCH_START') then

  call reallocate_arrays (1)
  if (present(ix_eles)) ix_eles(1) = -1

  select case(attrib_name)
  case ('EMITTANCE_A'); ptr_array(1)%r => lat%x%emit 
  case ('EMITTANCE_B'); ptr_array(1)%r => lat%y%emit
  case default
    bunch_start%key = def_bunch_start$
    ix = attribute_index (bunch_start, attrib_name)
    if (ix < 1) then
      if (do_print) call out_io (s_error$, r_name, &
             'INVALID ATTRIBUTE: ' // attrib_name, 'FOR ELEMENT: ' // ele_name)
      if (allocated(ptr_array)) call reallocate_arrays (0)
      err_flag = .true.
      return
    endif
    if (present(ix_attrib)) ix_attrib = ix
    ptr_array(1)%r => lat%bunch_start%vec(ix)
  end select

  return

endif

!

if (index(":1234567890", ele_name(1:1)) .ne. 0) then
! index array
  ele_name_temp = ele_name
  if (allocated (this_ele)) deallocate(this_ele)
  allocate(this_ele(0:lat%n_ele_max))
  call location_decode (ele_name_temp, this_ele, 0, n)

  call reallocate_arrays (n)
  if (n == 0) then
    if (do_print) call out_io (s_error$, r_name, 'ELEMENTS NOT FOUND: ' // ele_name)
    err_flag = .true.
    return  
  endif

  n = 0
  do i = 0, lat%n_ele_max
    if (this_ele(i)) then
      ele => lat%ele_(i)
      n = n + 1
      call pointer_to_attribute (ele, attrib_name, do_allocation, &
                        ptr_array(n)%r, err_flag, err_print_flag, ix_attrib)
      if (present(ix_eles)) ix_eles(n) = i
      if (err_flag) return
    endif
  enddo
else
! ele_name
  n = 0
  do i = 0, lat%n_ele_max
    ele => lat%ele_(i)
    if (ele%name == ele_name) n = n + 1
  enddo

  call reallocate_arrays (n)
  if (n == 0) then
    if (do_print) call out_io (s_error$, r_name, 'ELEMENT NOT FOUND: ' // ele_name)
    err_flag = .true.
    return  
  endif

  n = 0
  do i = 0, lat%n_ele_max
    ele => lat%ele_(i)
    if (ele%name == ele_name) then
      n = n + 1
      call pointer_to_attribute (ele, attrib_name, do_allocation, &
                        ptr_array(n)%r, err_flag, err_print_flag, ix_attrib)
      if (present(ix_eles)) ix_eles(n) = i
      if (err_flag) return
    endif
  enddo
endif

!----------------------------------------------------------------------------
contains

subroutine reallocate_arrays (n_size)

integer n_size

!

call reallocate_real_array (ptr_array, n_size)

if (.not. present (ix_eles)) return

if (n_size == 0) then
  if (allocated(ix_eles)) deallocate (ix_eles)
  return
endif

if (allocated(ix_eles)) then
  if (size(ix_eles) /= n_size) deallocate (ix_eles)
endif

if (.not. allocated(ix_eles)) allocate(ix_eles(n_size))

end subroutine

!----------------------------------------------------------------------------
!----------------------------------------------------------------------------
!----------------------------------------------------------------------------

subroutine reallocate_real_array (ptr_array, n)

use bmad_struct
use bmad_interface

implicit none

type (real_array_struct), allocatable :: ptr_array(:)
integer n

if (n == 0) then
  if (allocated(ptr_array)) deallocate (ptr_array)
  return
endif

if (allocated(ptr_array)) then
  if (size(ptr_array) /= n) deallocate (ptr_array)
endif

if (.not. allocated(ptr_array)) allocate(ptr_array(n))

end subroutine

end subroutine

