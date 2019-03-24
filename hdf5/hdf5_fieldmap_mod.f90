module hdf5_fieldmap_mod

use hdf5_interface
use bmad_interface

contains

!----------------------------------------------------------------------------------------
!----------------------------------------------------------------------------------------
!----------------------------------------------------------------------------------------
!+
! Subroutine hdf5_write_cartesian_map (file_name, ele, cart_map, err_flag)
!
! Routine to write a cartesian_map structure.
! Note: The file name should have a ".h5" suffix.
!
! Input:
!   file_name     -- character(*): File to create.
!   ele           -- ele_struct: Element associated with the map.
!   cart_map      -- cartesian_map_struct: Cartesian map.
!
! Ouput:
!   err_flag      -- logical: Set True if there is an error. False otherwise.
!-

subroutine hdf5_write_cartesian_map (file_name, ele, cart_map, err_flag)

implicit none

type (cartesian_map_struct), target :: cart_map
type (ele_struct) ele

integer(HID_T) f_id
integer i, j, h5_err
logical err_flag, err

character(*) file_name
character(200) f_name
character(*), parameter :: r_name = 'hdf5_write_cartesian_map'

!

err_flag = .true.
call hdf5_open_file (file_name, 'WRITE', f_id, err);  if (err) return

call hdf5_write_attribute_string(f_id, 'fileType', 'Bmad:cartesian_map')
call hdf5_write_attribute_string(f_id, 'file_name', file_name)
call hdf5_write_attribute_string(f_id, 'master_parameter', attribute_name(ele, cart_map%master_parameter))
call hdf5_write_real_attrib(f_id, 'field_scale', cart_map%field_scale)
call hdf5_write_real_attrib(f_id, 'r0', cart_map%r0)
call hdf5_write_int_attrib(f_id, 'ele_anchor_pt', cart_map%ele_anchor_pt)
call hdf5_write_int_attrib(f_id, 'field_type', cart_map%field_type)

call hdf5_

call h5fclose_f(f_id, h5_err)
err_flag = .false.
return

!

9000 continue
call out_io (s_error$, r_name, 'ERROR WRITING FIELDMAP STRUCTURE. FILE: ' // file_name)
call h5fclose_f(f_id, h5_err)
return

end subroutine hdf5_write_cartesian_map

!----------------------------------------------------------------------------------------
!----------------------------------------------------------------------------------------
!----------------------------------------------------------------------------------------
!+
! Subroutine hdf5_read_cartesian_map (file_name, ele, cart_map, err_flag)
!
! Routine to read a binary cartesian_map structure.
!
! Input:
!   file_name     -- character(*): File to create.
!   ele           -- ele_struct: Element associated with the map.
!
! Ouput:
!   cart_map      -- cartesian_map_struct, cartesian map.
!   err_flag      -- logical: Set True if there is an error. False otherwise.
!-

subroutine hdf5_read_cartesian_map (file_name, ele, cart_map, err_flag)

implicit none

type (cartesian_map_struct), target :: cart_map
type (ele_struct) ele

integer(HID_T) f_id
integer i, j, nt, iver, h5_err
logical err_flag, err

character(*) file_name
character(40) master_name
character(*), parameter :: r_name = 'hdf5_read_cartesian_map'

!

err_flag = .true.
call hdf5_open_file (file_name, 'READ', f_id, err);  if (err) return

call h5fclose_f(f_id, h5_err)
err_flag = .false.
return

!

9000 continue
call out_io (s_error$, r_name, 'ERROR READING BINARY FIELDMAP FILE. FILE: ' // file_name)
call h5fclose_f(f_id, h5_err)
return

end subroutine hdf5_read_cartesian_map

!----------------------------------------------------------------------------------------
!----------------------------------------------------------------------------------------
!----------------------------------------------------------------------------------------
!+
! Subroutine hdf5_write_cylindrical_map (file_name, ele, cl_map, err_flag)
!
! Routine to write a binary cylindrical_map structure.
! Note: The file name should have a ".h5" suffix.
!
! Input:
!   file_name     -- character(*): File to create.
!   ele           -- ele_struct: Element associated with the map.
!   cl_map        -- cylindrical_map_struct: Cylindrical map.
!
! Ouput:
!   err_flag      -- logical: Set True if there is an error. False otherwise.
!-

subroutine hdf5_write_cylindrical_map (file_name, ele, cl_map, err_flag)

implicit none

type (cylindrical_map_struct), target :: cl_map
type (ele_struct) ele

integer(HID_T) f_id
integer i, j, h5_err
logical err_flag, err

character(*) file_name
character(200) f_name
character(*), parameter :: r_name = 'hdf5_write_cylindrical_map'

!

err_flag = .true.
call hdf5_open_file (file_name, 'WRITE', f_id, err);  if (err) return

call h5fclose_f(f_id, h5_err)
err_flag = .false.
return

!

9000 continue
call out_io (s_error$, r_name, 'ERROR READING BINARY FIELDMAP FILE. FILE: ' // file_name)
call h5fclose_f(f_id, h5_err)
return

end subroutine hdf5_write_cylindrical_map

!----------------------------------------------------------------------------------------
!----------------------------------------------------------------------------------------
!----------------------------------------------------------------------------------------
!+
! Subroutine hdf5_read_cylindrical_map (file_name, ele, cl_map, err_flag)
!
! Routine to read a binary cylindrical_map structure.
!
! Input:
!   file_name     -- character(*): File to create.
!   ele           -- ele_struct: Element associated with the map.
!
! Ouput:
!   cl_map        -- cylindrical_map_struct, cylindrical map.
!   err_flag      -- logical: Set True if there is an error. False otherwise.
!-

subroutine hdf5_read_cylindrical_map (file_name, ele, cl_map, err_flag)

implicit none

type (cylindrical_map_struct), target :: cl_map
type (ele_struct) ele

integer(HID_T) f_id
integer i, j, nt, iver, h5_err
logical err_flag, err

character(*) file_name
character(40) master_name
character(*), parameter :: r_name = 'hdf5_read_cylindrical_map'

!

err_flag = .true.
call hdf5_open_file (file_name, 'READ', f_id, err);  if (err) return

call h5fclose_f(f_id, h5_err)
err_flag = .false.
return

!

9000 continue
call out_io (s_error$, r_name, 'ERROR READING BINARY FIELDMAP FILE. FILE: ' // file_name)
call h5fclose_f(f_id, h5_err)
return

end subroutine hdf5_read_cylindrical_map

!----------------------------------------------------------------------------------------
!----------------------------------------------------------------------------------------
!----------------------------------------------------------------------------------------
!+
! Subroutine hdf5_write_grid_field (file_name, ele, g_field, err_flag)
!
! Routine to write a binary grid_field structure.
! Note: The file name should have a ".h5" suffix.
!
! Input:
!   file_name     -- character(*): File to create.
!   ele           -- ele_struct: Element associated with the map.
!   g_field       -- grid_field_struct: Cylindrical map.
!
! Ouput:
!   err_flag      -- logical: Set True if there is an error. False otherwise.
!-

subroutine hdf5_write_grid_field (file_name, ele, g_field, err_flag)

implicit none

type (grid_field_struct), target :: g_field
type (ele_struct) ele

integer(HID_T) f_id
integer i, j, k, n, h5_err
logical err_flag, err

character(*) file_name
character(*), parameter :: r_name = 'dhf5_write_grid_field'
character(200) f_name

!

err_flag = .true.
call hdf5_open_file (file_name, 'WRITE', f_id, err);  if (err) return

call h5fclose_f(f_id, h5_err)
err_flag = .false.
return

!

9000 continue
call out_io (s_error$, r_name, 'ERROR WRITING FIELDMAP STRUCTURE. FILE: ' // file_name)
call h5fclose_f(f_id, h5_err)
return

end subroutine hdf5_write_grid_field

!----------------------------------------------------------------------------------------
!----------------------------------------------------------------------------------------
!----------------------------------------------------------------------------------------
!+
! Subroutine hdf5_read_grid_field (file_name, ele, g_field, err_flag)
!
! Routine to read a binary grid_field structure.
!
! Input:
!   file_name     -- character(*): File to create.
!   ele           -- ele_struct: Element associated with the map.
!
! Ouput:
!   g_field       -- grid_field_struct, cylindrical map.
!   err_flag      -- logical: Set True if there is an error. False otherwise.
!-

subroutine hdf5_read_grid_field (file_name, ele, g_field, err_flag)

implicit none

type (grid_field_struct), target :: g_field
type (ele_struct) ele

integer(HID_T) f_id
integer i, j, k, n0(3), n1(3), iver, h5_err
logical err_flag, err

character(*) file_name
character(40) master_name
character(*), parameter :: r_name = 'hdf5_read_grid_field'

!

err_flag = .true.
call hdf5_open_file (file_name, 'READ', f_id, err);  if (err) return

call h5fclose_f(f_id, h5_err)
err_flag = .false.
return

!

9000 continue
call out_io (s_error$, r_name, 'ERROR READING BINARY FIELDMAP FILE. FILE: ' // file_name)
call h5fclose_f(f_id, h5_err)
return

end subroutine hdf5_read_grid_field

!----------------------------------------------------------------------------------------
!----------------------------------------------------------------------------------------
!----------------------------------------------------------------------------------------
!+
! Subroutine hdf5_write_taylor_field (file_name, ele, t_field, err_flag)
!
! Routine to write a binary taylor_field structure.
! Note: The file name should have a ".h5" suffix.
!
! Input:
!   file_name     -- character(*): File to create.
!   ele           -- ele_struct: Element associated with the map.
!   t_field       -- taylor_field_struct: Cylindrical map.
!
! Ouput:
!   err_flag      -- logical: Set True if there is an error. False otherwise.
!-

subroutine hdf5_write_taylor_field (file_name, ele, t_field, err_flag)

implicit none

type (taylor_field_struct), target :: t_field
type (ele_struct) ele

integer(HID_T) f_id
integer i, j, k, n, h5_err
logical err_flag, err

character(*) file_name
character(*), parameter :: r_name = 'hdf5_write_taylor_field'
character(200) f_name

!

err_flag = .true.
call hdf5_open_file (file_name, 'WRITE', f_id, err);  if (err) return

call h5fclose_f(f_id, h5_err)
err_flag = .false.
return

!

9000 continue
call out_io (s_error$, r_name, 'ERROR WRITING FIELDMAP STRUCTURE. FILE: ' // file_name)
call h5fclose_f(f_id, h5_err)
return

end subroutine hdf5_write_taylor_field

!----------------------------------------------------------------------------------------
!----------------------------------------------------------------------------------------
!----------------------------------------------------------------------------------------
!+
! Subroutine hdf5_read_taylor_field (file_name, ele, t_field, err_flag)
!
! Routine to read a binary taylor_field structure.
!
! Input:
!   file_name     -- character(*): File to create.
!   ele           -- ele_struct: Element associated with the map.
!
! Ouput:
!   t_field       -- taylor_field_struct, cylindrical map.
!   err_flag      -- logical: Set True if there is an error. False otherwise.
!-

subroutine hdf5_read_taylor_field (file_name, ele, t_field, err_flag)

implicit none

type (taylor_field_struct), target :: t_field
type (ele_struct) ele

integer(HID_T) f_id
integer i, j, k, n0, n1, n, nn, iver, h5_err
logical err_flag, err

character(*) file_name
character(40) master_name
character(*), parameter :: r_name = 'hdf5_read_taylor_field'

!

err_flag = .true.
call hdf5_open_file (file_name, 'READ', f_id, err);  if (err) return

call h5fclose_f(f_id, h5_err)
err_flag = .false.
return

!

9000 continue
call out_io (s_error$, r_name, 'ERROR READING BINARY FIELDMAP FILE. FILE: ' // file_name)
call h5fclose_f(f_id, h5_err)
return

end subroutine hdf5_read_taylor_field

end module
