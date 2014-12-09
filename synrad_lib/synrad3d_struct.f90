module synrad3d_struct

use bmad_struct
use bmad_interface
use twiss_and_track_mod
use photon_reflection_mod

type sr3d_photon_wall_hit_struct
  type (coord_struct) before_reflect   ! Coords before reflection.
  type (coord_struct) after_reflect    ! Coords after reflection.
  real(rp) dw_perp(3)                   ! Wall perpendicular vector
  real(rp) cos_perp_in                  ! Cosine of incoming ray and hit angle
  real(rp) cos_perp_out                 ! Cosine of hit angle
  real(rp) reflectivity                 ! Reflectivity probability
end type

! This structure defines the full track of the photon from start to finish
! %start           -- Starting position.
! %old             -- Used by the tracking code. Not useful otherwise.
! %now             -- Present position. At the end of tracking, %now will be the final position.
! %wall_hit(:)     -- Records the positions at which the photon hit the wall
!                       including the final position. The array bounds are: %hit(1:%n_hit) 
! %crossed_lat_end -- Did the photon cross from the end of the lattice to the beginning
!                       or vice versa?
! %hit_antechamber -- Did the photon hit the antechamber at the final position?
! %ix_photon       -- Unfiltered photon index. 
! %ix_photon_generated -- The first photon generated has index 1, etc.
! %n_wall_hit      -- Number of wall hits.

type sr3d_photon_track_struct
  type (coord_struct) start, old, now  ! coords:
  logical :: crossed_lat_end = .false.     ! Photon crossed through the lattice beginning or end?
  logical :: hit_antechamber = .false.     
  integer ix_photon                        ! Photon index.
  integer ix_photon_generated
  integer :: n_wall_hit = 0                ! Number of wall hits
  integer :: status                        ! is_through_wall$, at_lat_end$, or inside_the_wall$
end type

!--------------
! The wall is specified by an array of cross-sections at given s locations.
! The wall between section i-1 and i is associated with wall%section(i) 
! If there is an antechamber: width2_plus and width2_minus are the antechamber horizontal extent.
! With no antechamber: width2_plus and width2_minus specify beam stops.

type sr3d_gen_shape_struct
  character(40) name
  type (wall3d_section_struct) :: wall3d_section
  integer ix_vertex_ante(2)
  integer ix_vertex_ante2(2)
end type

type sr3d_wall_section_struct
  character(40) name              ! Name of this section
  character(16) basic_shape       ! "elliptical", "rectangular", "gen_shape", or "multi_section"
  character(40) shape_name
  character(40) surface_name 
  real(rp) s                      ! Longitudinal position.
  real(rp) width2                 ! Half width ignoring antechamber.
  real(rp) height2                ! Half height ignoring antechamber.
  real(rp) width2_plus            ! Distance from pipe center to +x side edge.
  real(rp) ante_height2_plus      ! Antechamber half height on +x side of the wall
  real(rp) width2_minus           ! Distance from pipe center -x side edge.
  real(rp) ante_height2_minus     ! Antechamber half height on -x side of the wall
  real(rp) ante_x0_plus           ! Computed: x coord at +x antechamber opening.
  real(rp) ante_x0_minus          ! Computed: x coord at -x antechamber opening.
  real(rp) y0_plus                ! Computed: y coord at edge of +x beam stop.
  real(rp) y0_minus               ! Computed: y coord at edge of -x beam stop.
  logical is_local
  type (sr3d_gen_shape_struct), pointer :: gen_shape => null()            ! Gen_shape info
  type (sr3d_wall_section_struct), pointer :: m_sec   ! Multi-section pointer
end type

! multi_section structure

type sr3d_multi_section_struct
  character(40) name
  type (sr3d_wall_section_struct), allocatable :: section(:)
end type

! Root wall description structure.

type sr3d_wall_struct
  type (sr3d_wall_section_struct), allocatable :: section(:)  ! indexed from 1
  type (sr3d_gen_shape_struct), allocatable :: gen_shape(:)
  type (sr3d_multi_section_struct), allocatable :: multi_section(:)
  integer n_section_max
end type

!------------------------------------------------------------------------
! Some parameters that can be set. 

type sr3d_params_struct
  type (random_state_struct) ran_state
  real(rp) :: ds_track_step_max = 3     ! Maximum longitudinal distance in one photon "step".
  real(rp) :: dr_track_step_max = 0.1   ! Maximum tranverse distance in one photon "step".
  real(rp) :: significant_length = 1d-10
  logical :: allow_reflections = .true. ! If False, terminate tracking when photon hits the wall.
  logical :: allow_absorption = .true.  ! If False, do not allow photon to be adsorbed.
  logical :: stop_if_hit_antechamber = .false. 
  logical :: specular_reflection_only = .false.
  logical :: debug_on = .false.
  integer ix_generated_warn             ! For debug use
end type

type (sr3d_params_struct), save :: sr3d_params

! Misc

integer, parameter :: is_through_wall$ = 0, at_lat_end$ = 1, inside_the_wall$ = 2

type sr3d_plot_param_struct
  real(rp) :: window_width = 800.0_rp, window_height = 400.0_rp
  integer :: n_pt = 1000
end type

end module
