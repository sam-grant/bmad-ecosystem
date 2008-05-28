!+
! Subroutine lattice_to_bmad_file_name (lattice, bmad_file_name)
!
! Subroutine to convert a lattice name to the appropriate bmad file name.
! First tried is:
!       "$CESR_MNT/lattice/CESR/bmad/" + lattice + ".lat"
! If this does not exist, bmad_file_name is set to:
!       "$CESR_MNT/lattice/CESR/bmad/bmad_" + lattice + ".lat"
!
! Note: lattice is always converted to lower case.
!
! Input:
!   lattice -- Character(40): CESR Lattice name.
!
! Output:
!  bmad_file_name -- Character(*): Appropriate name of the bmad file
!-

subroutine lattice_to_bmad_file_name (lattice, bmad_file_name)

  use cesr_utils

  implicit none

  character(*) lattice, bmad_file_name
  character(len(lattice)) lat
  character(40) lat_dir
  logical is_there

!

  lat = lattice
  call downcase_string(lat)

#ifdef CESR_VMS
  lat_dir = '$CESR_MNT/vms_lattice/cesr/bmad/'
#else
  lat_dir = '$CESR_MNT/lattice/cesr/bmad/'
#endif

  bmad_file_name = trim(lat_dir) // trim(lat) // '.lat'
  call FullFileName(bmad_file_name, bmad_file_name)

  inquire (file = bmad_file_name, exist = is_there)
  if (.not. is_there) then
    bmad_file_name = trim(lat_dir) // 'bmad_' // trim(lat) // '.lat'
    call FullFileName(bmad_file_name, bmad_file_name)
  endif

end subroutine
