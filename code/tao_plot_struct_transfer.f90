!+
! Subroutine tao_plot_struct_transfer (plot_in, plot_out, preserve_region)
!
! Subroutine to transfer the information from one plot_struct to another.
! This routine handles keeping the pointers separate.
!
! Input:
!   plot_in  -- Tao_plot_struct: Input structure.
!   preserve_region -- Logical: If True then plot_out%region is not overwritten.
!
! Output:
!   plot_out -- Tao_plot_struct: Output struture.
!-

subroutine tao_plot_struct_transfer (plot_in, plot_out, preserve_region)

use tao_struct
use tao_interface
use tao_utils

implicit none

type (tao_plot_struct), target :: plot_in, plot_out
type (tao_plot_region_struct) region
type (tao_curve_struct), pointer :: c_in, c_out

integer i, j, n
logical preserve_region

! Deallocate plot_out pointers

if (associated(plot_out%graph)) then

  do i = 1, size(plot_out%graph)
    if (.not. associated(plot_out%graph(i)%curve)) cycle
    do j = 1, size(plot_out%graph(i)%curve)
      c_out => plot_out%graph(i)%curve(j)
      if (.not. associated(c_out%x_symb)) cycle
      deallocate (c_out%x_symb, c_out%y_symb, c_out%ix_symb)
      deallocate (c_out%y_line, c_out%x_line)
    enddo
    deallocate (plot_out%graph(i)%curve)
  enddo

  deallocate (plot_out%graph)

endif

! Set plot_out = plot_in. 
! This makes the pointers of plot_out point to the same memory as plot_in

region = plot_out%region
plot_out = plot_in
if (preserve_region) plot_out%region = region

! Now allocate storage for the plot_out pointers and 
! copy the data from plot_in to plot_out

if (associated(plot_in%graph)) then

  allocate (plot_out%graph(size(plot_in%graph)))

  do i = 1, size(plot_out%graph)

    plot_out%graph(i) = plot_in%graph(i)

    if (.not. associated (plot_in%graph(i)%curve)) cycle
    allocate (plot_out%graph(i)%curve(size(plot_in%graph(i)%curve)))

    do j = 1, size(plot_out%graph(i)%curve)
      c_in  => plot_in%graph(i)%curve(j)
      c_out => plot_out%graph(i)%curve(j)
      c_out = c_in
      if (.not. associated (c_in%x_symb)) cycle
      n = size(c_in%x_symb)
      allocate (c_out%x_symb(n), c_out%y_symb(n), c_out%ix_symb(n))
      c_out%x_symb  = c_in%x_symb 
      c_out%y_symb  = c_in%y_symb 
      c_out%ix_symb = c_in%ix_symb 
      n = size(c_in%x_line)
      allocate (c_out%x_line(n), c_out%y_line(n))
      c_out%x_line  = c_in%x_line 
      c_out%y_line  = c_in%y_line 
    enddo

  enddo

endif

end subroutine
