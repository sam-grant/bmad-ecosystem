!+
! module tao_input_struct
!
! Module to define the structures needed for the namelist input.
!-

module tao_input_struct

use tao_mod

!-------------------------------------------------------------
! data input structures

type tao_d2_data_input
  character(16) class           ! class of data
  integer universe              ! universe where data sits. 0 -> all universes
end type

type tao_d1_data_input
  character(16) sub_class        ! type of data
end type

type tao_data_input
  integer ix_min, ix_max        ! min, max index
  character(16) :: name(n_data_minn:n_data_maxx) = ' ' 
  character(16) :: ele_name(n_data_minn:n_data_maxx) = ' ' 
  real(rp) :: default_weight        ! default merit function weight
  real(rp) :: weight(n_data_minn:n_data_maxx) ! individual weight 
end type

!-------------------------------------------------------------
! variable input structures

type tao_v1_var_input
  character(16) class           ! type of variable
  character(16) attribute       ! attribute to vary
  character(16) universe        ! universe variable is: Integer, "all", "common"
end type

type tao_var_input
  integer ix_min, ix_max        ! min, max index
  character(16) :: name(n_var_minn:n_var_maxx) = ' '
  character(16) :: ele_name(n_var_minn:n_var_maxx) = ' '
  real(rp) :: default_weight        ! default merit function weight
  real(rp) :: default_step          ! default "small" step size
  real(rp) :: weight(n_var_minn:n_var_maxx) 
  real(rp) :: step(n_var_minn:n_var_maxx)
end type

!-------------------------------------------------------------
! plot input structures

type tao_place_input
  character(16) region
  character(16) plot
end type

type tao_plot_page_input
  real(rp) size(2)
  real(rp) text_height
  type (qp_rect_struct) border
end type

type tao_curve_input
  character(16) data_source
  character(16) data_class
  real(rp) units_factor
  integer symbol_every
  integer ix_universe
  logical draw_line
  logical use_y2
  type (qp_line_struct) line
  type (qp_symbol_struct) symbol
end type

type tao_graph_input
  character(16) name
  character(80) title
  integer this_box(2)
  integer n_curve
  type (qp_rect_struct) margin
  type (qp_axis_struct) y
  type (qp_axis_struct) y2
end type 

type tao_plot_input
  character(16) name
  character(16) type
  type (tao_plot_who_struct) who(10)
  type (qp_axis_struct) x
  character(16) x_axis_type
  logical convert  
  integer box_layout(2)
  integer n_graph
end type

!-------------------------------------------------------------
! other structures

type tao_design_lat_input
  character(200) file
  character(16) :: parser = 'bmad'
end type

type tao_key_input
  character(16) ele_name
  character(16) attrib_name
  real(rp) delta
  character(16) lattice
  real(rp) small_step
  real(rp) low_lim
  real(rp) high_lim
  real(rp) weight
  logical good_opt
end type

end module
