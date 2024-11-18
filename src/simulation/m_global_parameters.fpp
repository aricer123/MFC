!>
!! @file m_global_parameters.f90
!! @brief Contains module m_global_parameters

#:include 'case.fpp'
#:include 'macros.fpp'

!> @brief The module contains all of the parameters describing the program
!!              logistics, the computational domain and the simulation algorithm.
!!              Additionally, for the volume fraction model, physical parameters
!!              of each of the fluids present in the flow are located here. They
!!              include stiffened gas equation of state parameters, the Reynolds
!!              numbers and the Weber numbers.
module m_global_parameters

    ! Dependencies =============================================================
#ifdef MFC_MPI
    use mpi                    !< Message passing interface (MPI) module
#endif

    use m_derived_types        !< Definitions of the derived types

    use m_helper_basic         !< Functions to compare floating point numbers

#ifdef MFC_OpenACC
    use openacc
#endif

    ! ==========================================================================

    implicit none

    real(wp) :: time = 0

    ! Logistics ================================================================
    integer :: num_procs             !< Number of processors
    character(LEN=path_len) :: case_dir              !< Case folder location
    logical :: run_time_info         !< Run-time output flag
    integer :: t_step_old            !< Existing IC/grid folder
    ! ==========================================================================

    ! Computational Domain Parameters ==========================================
    integer :: proc_rank !< Rank of the local processor

    !> @name Number of cells in the x-, y- and z-directions, respectively
    !> @{
    integer :: m, n, p
    !> @}

    !> @name Global number of cells in each direction
    !> @{
    integer :: m_glb, n_glb, p_glb
    !> @}

    !> @name Cylindrical coordinates (either axisymmetric or full 3D)
    !> @{
    logical :: cyl_coord
    integer :: grid_geometry
    !> @}
    !$acc declare create(cyl_coord, grid_geometry)

    !> @name Cell-boundary (CB) locations in the x-, y- and z-directions, respectively
    !> @{

    real(wp), target, allocatable, dimension(:) :: x_cb, y_cb, z_cb
    !> @}

    !> @name Cell-center (CC) locations in the x-, y- and z-directions, respectively
    !> @{

    real(wp), target, allocatable, dimension(:) :: x_cc, y_cc, z_cc
    !> @}
    !type(bounds_info) :: x_domain, y_domain, z_domain !<
    !! Locations of the domain bounds in the x-, y- and z-coordinate directions
    !> @name Cell-width distributions in the x-, y- and z-directions, respectively
    !> @{

    real(wp), target, allocatable, dimension(:) :: dx, dy, dz
    !> @}

    real(wp) :: dt !< Size of the time-step

    !$acc declare create(x_cb, y_cb, z_cb, x_cc, y_cc, z_cc, dx, dy, dz, dt, m, n, p)

    !> @name Starting time-step iteration, stopping time-step iteration and the number
    !! of time-step iterations between successive solution backups, respectively
    !> @{
    integer :: t_step_start, t_step_stop, t_step_save
    !> @}

    !> @name Starting time, stopping time, and time between backups, simulation time,
    !! and prescribed cfl respectively
    !> @{
    real(wp) :: t_stop, t_save, cfl_target
    integer :: n_start
    !> @}
    !$acc declare create(cfl_target)

    logical :: cfl_adap_dt, cfl_const_dt, cfl_dt

    integer :: t_step_print !< Number of time-steps between printouts

    ! ==========================================================================

    ! Simulation Algorithm Parameters ==========================================
    integer :: model_eqns     !< Multicomponent flow model
    #:if MFC_CASE_OPTIMIZATION
        integer, parameter :: num_dims = ${num_dims}$       !< Number of spatial dimensions
    #:else
        integer :: num_dims       !< Number of spatial dimensions
    #:endif
    logical :: mpp_lim        !< Mixture physical parameters (MPP) limits
    integer :: time_stepper   !< Time-stepper algorithm
    logical :: prim_vars_wrt

    #:if MFC_CASE_OPTIMIZATION
        integer, parameter :: weno_polyn = ${weno_polyn}$ !< Degree of the WENO polynomials (polyn)
        integer, parameter :: weno_order = ${weno_order}$ !< Order of the WENO reconstruction
        integer, parameter :: weno_num_stencils = ${weno_num_stencils}$ !< Number of stencils for WENO reconstruction (only different from weno_polyn for TENO(>5))
        integer, parameter :: num_fluids = ${num_fluids}$ !< number of fluids in the simulation
        logical, parameter :: wenojs = (${wenojs}$ /= 0)            !< WENO-JS (default)
        logical, parameter :: mapped_weno = (${mapped_weno}$ /= 0)  !< WENO-M (WENO with mapping of nonlinear weights)
        logical, parameter :: wenoz = (${wenoz}$ /= 0)              !< WENO-Z
        logical, parameter :: teno = (${teno}$ /= 0)                !< TENO (Targeted ENO)
        real(wp), parameter :: wenoz_q = ${wenoz_q}$         !< Power constant for WENO-Z
    #:else
        integer :: weno_polyn     !< Degree of the WENO polynomials (polyn)
        integer :: weno_order     !< Order of the WENO reconstruction
        integer :: weno_num_stencils    !< Number of stencils for WENO reconstruction (only different from weno_polyn for TENO(>5))
        integer :: num_fluids     !< number of fluids in the simulation
        logical :: wenojs         !< WENO-JS (default)
        logical :: mapped_weno    !< WENO-M (WENO with mapping of nonlinear weights)
        logical :: wenoz          !< WENO-Z
        logical :: teno           !< TENO (Targeted ENO)
        real(wp) :: wenoz_q  !< Power constant for WENO-Z
    #:endif

    real(wp) :: weno_eps       !< Binding for the WENO nonlinear weights
    real(wp) :: teno_CT        !< Smoothness threshold for TENO
    logical :: mp_weno        !< Monotonicity preserving (MP) WENO
    logical :: weno_avg       ! Average left/right cell-boundary states
    logical :: weno_Re_flux   !< WENO reconstruct velocity gradients for viscous stress tensor
    integer :: riemann_solver !< Riemann solver algorithm
    integer :: low_Mach       !< Low Mach number fix to HLLC Riemann solver
    integer :: wave_speeds    !< Wave speeds estimation method
    integer :: avg_state      !< Average state evaluation method
    logical :: alt_soundspeed !< Alternate mixture sound speed
    logical :: null_weights   !< Null undesired WENO weights
    logical :: mixture_err    !< Mixture properties correction
    logical :: hypoelasticity !< hypoelasticity modeling
    logical, parameter :: chemistry = .${chemistry}$. !< Chemistry modeling
    logical :: cu_tensor
    logical :: viscous       !< Viscous effects
    logical :: shear_stress  !< Shear stresses
    logical :: bulk_stress   !< Bulk stresses

    !$acc declare create(chemistry)

    logical :: bodyForces
    logical :: bf_x, bf_y, bf_z !< body force toggle in three directions
    !< amplitude, frequency, and phase shift sinusoid in each direction
    #:for dir in {'x', 'y', 'z'}
        #:for param in {'k','w','p','g'}
            real(wp) :: ${param}$_${dir}$
        #:endfor
    #:endfor
    real(wp), dimension(3) :: accel_bf
    !$acc declare create(accel_bf)

    integer :: cpu_start, cpu_end, cpu_rate

    #:if not MFC_CASE_OPTIMIZATION
        !$acc declare create(num_dims, weno_polyn, weno_order, weno_num_stencils, num_fluids, wenojs, mapped_weno, wenoz, teno, wenoz_q)
    #:endif

    !$acc declare create(mpp_lim, model_eqns, mixture_err, alt_soundspeed, avg_state, mp_weno, weno_eps, teno_CT, hypoelasticity, low_Mach, viscous, shear_stress, bulk_stress)

    logical :: relax          !< activate phase change
    integer :: relax_model    !< Relaxation model
    real(wp) :: palpha_eps     !< trigger parameter for the p relaxation procedure, phase change model
    real(wp) :: ptgalpha_eps   !< trigger parameter for the pTg relaxation procedure, phase change model

!#ifndef _CRAYFTN
!$acc declare create(relax, relax_model, palpha_eps,ptgalpha_eps)
!#endif

    !> @name Boundary conditions (BC) in the x-, y- and z-directions, respectively
    !> @{
    type(int_bounds_info) :: bc_x, bc_y, bc_z
    !> @}
    type(bounds_info) :: x_domain, y_domain, z_domain

    logical :: parallel_io !< Format of the data files
    logical :: file_per_process !< shared file or not when using parallel io
    integer :: precision !< Precision of output files

    integer, allocatable, dimension(:) :: proc_coords !<
    !! Processor coordinates in MPI_CART_COMM

    integer, allocatable, dimension(:) :: start_idx !<
    !! Starting cell-center index of local processor in global grid

    type(mpi_io_var), public :: MPI_IO_DATA
    type(mpi_io_ib_var), public :: MPI_IO_IB_DATA
    type(mpi_io_airfoil_ib_var), public :: MPI_IO_airfoil_IB_DATA
    type(mpi_io_levelset_var), public :: MPI_IO_levelset_DATA
    type(mpi_io_levelset_norm_var), public :: MPI_IO_levelsetnorm_DATA

    !> @name MPI info for parallel IO with Lustre file systems
    !> @{
    character(LEN=name_len) :: mpiiofs
    integer :: mpi_info_int
    !> @}

    integer, private :: ierr

    !> @name Annotations of the structure of the state and flux vectors in terms of the
    !! size and the configuration of the system of equations to which they belong
    !> @{
    integer :: sys_size                  !< Number of unknowns in system of eqns.
    type(int_bounds_info) :: cont_idx                  !< Indexes of first & last continuity eqns.
    type(int_bounds_info) :: mom_idx                   !< Indexes of first & last momentum eqns.
    integer :: E_idx                     !< Index of energy equation
    integer :: n_idx                     !< Index of number density
    type(int_bounds_info) :: adv_idx                   !< Indexes of first & last advection eqns.
    type(int_bounds_info) :: internalEnergies_idx      !< Indexes of first & last internal energy eqns.
    type(bub_bounds_info) :: bub_idx               !< Indexes of first & last bubble variable eqns.
    integer :: alf_idx               !< Index of void fraction
    integer :: gamma_idx                 !< Index of specific heat ratio func. eqn.
    integer :: pi_inf_idx                !< Index of liquid stiffness func. eqn.
    type(int_bounds_info) :: stress_idx                !< Indexes of first and last shear stress eqns.
    integer :: c_idx         ! Index of the color function
    type(int_bounds_info) :: species_idx           !< Indexes of first & last concentration eqns.
    integer :: T_idx       !< Index of the temperature equation
    !> @}

    !$acc declare create(bub_idx)

    ! Cell Indices for the (local) interior points (O-m, O-n, 0-p).
    ! Stands for "InDices With INTerior".
    type(int_bounds_info) :: idwint(1:3)
    !$acc declare create(idwint)

    ! Cell Indices for the entire (local) domain. In simulation and post_process,
    ! this includes the buffer region. idwbuff and idwint are the same otherwise.
    ! Stands for "InDices With BUFFer".
    type(int_bounds_info) :: idwbuff(1:3)
    !$acc declare create(idwbuff)

    !> @name The number of fluids, along with their identifying indexes, respectively,
    !! for which viscous effects, e.g. the shear and/or the volume Reynolds (Re)
    !! numbers, will be non-negligible.
    !> @{
    integer, dimension(2) :: Re_size
    integer, allocatable, dimension(:, :) :: Re_idx
    !> @}

    !$acc declare create(Re_size, Re_idx)

    ! The WENO average (WA) flag regulates whether the calculation of any cell-
    ! average spatial derivatives is carried out in each cell by utilizing the
    ! arithmetic mean of the left and right, WENO-reconstructed, cell-boundary
    ! values or simply, the unaltered left and right, WENO-reconstructed, cell-
    ! boundary values.
    !> @{
    real(wp) :: wa_flg
    !> @{

    !$acc declare create(wa_flg)

    !> @name The coordinate direction indexes and flags (flg), respectively, for which
    !! the configurations will be determined with respect to a working direction
    !! and that will be used to isolate the contributions, in that direction, in
    !! the dimensionally split system of equations.
    !> @{
    integer, dimension(3) :: dir_idx
    real(wp), dimension(3) :: dir_flg
    integer, dimension(3) :: dir_idx_tau !!used for hypoelasticity=true
    !> @}

    !$acc declare create(dir_idx, dir_flg, dir_idx_tau)

    integer :: buff_size !<
    !! The number of cells that are necessary to be able to store enough boundary
    !! conditions data to march the solution in the physical computational domain
    !! to the next time-step.

    integer :: startx, starty, startz

    !$acc declare create(sys_size, buff_size, startx, starty, startz, E_idx, T_idx, gamma_idx, pi_inf_idx, alf_idx, n_idx, stress_idx, species_idx)

    ! END: Simulation Algorithm Parameters =====================================

    ! Fluids Physical Parameters ===============================================

    type(physical_parameters), dimension(num_fluids_max) :: fluid_pp !<
    !! Database of the physical parameters of each of the fluids that is present
    !! in the flow. These include the stiffened gas equation of state parameters,
    !! the Reynolds numbers and the Weber numbers.

    !$acc declare create(bc_x%vb1, bc_x%vb2, bc_x%vb3, bc_x%ve1, bc_x%ve2, bc_x%ve3)
    !$acc declare create(bc_y%vb1, bc_y%vb2, bc_y%vb3, bc_y%ve1, bc_y%ve2, bc_y%ve3)
    !$acc declare create(bc_z%vb1, bc_z%vb2, bc_z%vb3, bc_z%ve1, bc_z%ve2, bc_z%ve3)

    ! ==========================================================================

    integer :: fd_order !<
    !! The order of the finite-difference (fd) approximations of the first-order
    !! derivatives that need to be evaluated when the CoM or flow probe data
    !! files are to be written at each time step

    integer :: fd_number !<
    !! The finite-difference number is given by MAX(1, fd_order/2). Essentially,
    !! it is a measure of the half-size of the finite-difference stencil for the
    !! selected order of accuracy.

    logical :: probe_wrt
    logical :: integral_wrt
    integer :: num_probes
    integer :: num_integrals
    type(probe_parameters), dimension(num_probes_max) :: probe
    type(integral_parameters), dimension(num_probes_max) :: integral

    !> @name Reference density and pressure for Tait EOS
    !> @{
    real(wp) :: rhoref, pref
    !> @}
    !$acc declare create(rhoref, pref)

    !> @name Immersed Boundaries
    !> @{
    logical :: ib
    integer :: num_ibs

    type(ib_patch_parameters), dimension(num_patches_max) :: patch_ib
    type(probe_parameters), allocatable, dimension(:) :: airfoil_grid_u, airfoil_grid_l
    integer :: Np
    !! Database of the immersed boundary patch parameters for each of the
    !! patches employed in the configuration of the initial condition. Note that
    !! the maximum allowable number of patches, num_patches_max, may be changed
    !! in the module m_derived_types.f90.
    ! ==========================================================================

    !$acc declare create(ib, num_ibs, patch_ib)
    !> @}

    !> @name Bubble modeling
    !> @{
    #:if MFC_CASE_OPTIMIZATION
        integer, parameter :: nb = ${nb}$ !< Number of eq. bubble sizes
    #:else
        integer :: nb       !< Number of eq. bubble sizes
    #:endif

    real(wp) :: R0ref    !< Reference bubble size
    real(wp) :: Ca       !< Cavitation number
    real(wp) :: Web      !< Weber number
    real(wp) :: Re_inv   !< Inverse Reynolds number

    real(wp), dimension(:), allocatable :: weight !< Simpson quadrature weights
    real(wp), dimension(:), allocatable :: R0     !< Bubble sizes
    real(wp), dimension(:), allocatable :: V0     !< Bubble velocities
    !$acc declare create(weight, R0, V0)

    logical :: bubbles      !< Bubbles on/off
    logical :: polytropic   !< Polytropic  switch
    logical :: polydisperse !< Polydisperse bubbles
    logical :: adv_n        !< Solve the number density equation and compute alpha from number density
    logical :: adap_dt      !< Adaptive step size control

    integer :: bubble_model !< Gilmore or Keller--Miksis bubble model
    integer :: thermal      !< Thermal behavior. 1 = adiabatic, 2 = isotherm, 3 = transfer

    real(wp), allocatable, dimension(:, :, :) :: ptil  !< Pressure modification
    !$acc declare create(ptil)

    real(wp) :: poly_sigma  !< log normal sigma for polydisperse PDF

    logical :: qbmm      !< Quadrature moment method
    integer, parameter :: nmom = 6 !< Number of carried moments per R0 location
    integer :: nmomsp    !< Number of moments required by ensemble-averaging
    integer :: nmomtot   !< Total number of carried moments moments/transport equations
    integer :: R0_type

    real(wp) :: pi_fac   !< Factor for artificial pi_inf

    #:if not MFC_CASE_OPTIMIZATION
        !$acc declare create(nb)
    #:endif

    !$acc declare create(R0ref, Ca, Web, Re_inv, bubbles, polytropic, polydisperse, qbmm, nmomsp, nmomtot, R0_type, bubble_model, thermal, poly_sigma, adv_n, adap_dt, pi_fac)

    type(scalar_field), allocatable, dimension(:) :: mom_sp
    type(scalar_field), allocatable, dimension(:, :, :) :: mom_3d
    !$acc declare create(mom_sp, mom_3d)

    !> @}

    type(chemistry_parameters) :: chem_params
    !$acc declare create(chem_params)

    !> @name Physical bubble parameters (see Ando 2010, Preston 2007)
    !> @{

    real(wp) :: R_n, R_v, phi_vn, phi_nv, Pe_c, Tw, pv, M_n, M_v
    !$acc declare create(R_n, R_v, phi_vn, phi_nv, Pe_c, Tw, pv, M_n, M_v)

    real(wp), dimension(:), allocatable :: k_n, k_v, pb0, mass_n0, mass_v0, Pe_T
    real(wp), dimension(:), allocatable :: Re_trans_T, Re_trans_c, Im_trans_T, Im_trans_c, omegaN
    !$acc declare create( k_n, k_v, pb0, mass_n0, mass_v0, Pe_T, Re_trans_T, Re_trans_c, Im_trans_T, Im_trans_c, omegaN)

    real(wp) :: mul0, ss, gamma_v, mu_v
    real(wp) :: gamma_m, gamma_n, mu_n
    real(wp) :: gam
    !> @}

    !$acc declare create(mul0, ss, gamma_v, mu_v, gamma_m, gamma_n, mu_n, gam)

    !> @name Acoustic acoustic_source parameters
    !> @{
    logical :: acoustic_source !< Acoustic source switch
    type(acoustic_parameters), dimension(num_probes_max) :: acoustic !< Acoustic source parameters
    integer :: num_source !< Number of acoustic sources
    !> @}
    !$acc declare create(acoustic_source, acoustic, num_source)

    !> @name Surface tension parameters
    !> @{

    real(wp) :: sigma
    logical :: surface_tension
    !$acc declare create(sigma, surface_tension)
    !> @}

    integer :: momxb, momxe
    integer :: advxb, advxe
    integer :: contxb, contxe
    integer :: intxb, intxe
    integer :: bubxb, bubxe
    integer :: strxb, strxe
    integer :: chemxb, chemxe

    !$acc declare create(momxb, momxe, advxb, advxe, contxb, contxe, intxb, intxe, bubxb, bubxe, strxb, strxe,  chemxb, chemxe)

    real(wp), allocatable, dimension(:) :: gammas, gs_min, pi_infs, ps_inf, cvs, qvs, qvps
    !$acc declare create(gammas, gs_min, pi_infs, ps_inf, cvs, qvs, qvps)

    real(wp) :: mytime       !< Current simulation time
    real(wp) :: finaltime    !< Final simulation time

    logical :: weno_flat, riemann_flat, rdma_mpi

    type(pres_field), allocatable, dimension(:) :: pb_ts

    type(pres_field), allocatable, dimension(:) :: mv_ts

    !$acc declare create(pb_ts, mv_ts)

    ! ======================================================================

contains

    !> Assigns default values to the user inputs before reading
        !!  them in. This enables for an easier consistency check of
        !!  these parameters once they are read from the input file.
    subroutine s_assign_default_values_to_user_inputs

        integer :: i, j !< Generic loop iterator

        ! Logistics
        case_dir = '.'
        run_time_info = .false.
        t_step_old = dflt_int

        ! Computational domain parameters
        m = dflt_int; n = 0; p = 0

        cyl_coord = .false.

        dt = dflt_real

        cfl_adap_dt = .false.
        cfl_const_dt = .false.
        cfl_dt = .false.
        cfl_target = dflt_real

        t_step_start = dflt_int
        t_step_stop = dflt_int
        t_step_save = dflt_int
        t_step_print = 1

        n_start = dflt_int
        t_stop = dflt_real
        t_save = dflt_real

        ! Simulation algorithm parameters
        model_eqns = dflt_int
        mpp_lim = .false.
        time_stepper = dflt_int
        weno_eps = dflt_real
        teno_CT = dflt_real
        mp_weno = .false.
        weno_avg = .false.
        weno_Re_flux = .false.
        riemann_solver = dflt_int
        low_Mach = 0
        wave_speeds = dflt_int
        avg_state = dflt_int
        alt_soundspeed = .false.
        null_weights = .false.
        mixture_err = .false.
        parallel_io = .false.
        file_per_process = .false.
        precision = 2
        relax = .false.
        relax_model = dflt_int
        palpha_eps = dflt_real
        ptgalpha_eps = dflt_real
        hypoelasticity = .false.
        weno_flat = .true.
        riemann_flat = .true.
        rdma_mpi = .false.
        viscous = .false.
        shear_stress = .false.
        bulk_stress = .false.

        #:if not MFC_CASE_OPTIMIZATION
            mapped_weno = .false.
            wenoz = .false.
            teno = .false.
            wenoz_q = dflt_real
        #:endif

        chem_params%diffusion = .false.
        chem_params%reactions = .false.
        chem_params%gamma_method = 1

        bc_x%beg = dflt_int; bc_x%end = dflt_int
        bc_y%beg = dflt_int; bc_y%end = dflt_int
        bc_z%beg = dflt_int; bc_z%end = dflt_int

        #:for DIM in ['x', 'y', 'z']
            #:for DIR in [1, 2, 3]
                bc_${DIM}$%vb${DIR}$ = 0._wp
                bc_${DIM}$%ve${DIR}$ = 0._wp
            #:endfor
        #:endfor

        x_domain%beg = dflt_int; x_domain%end = dflt_int
        y_domain%beg = dflt_int; y_domain%end = dflt_int
        z_domain%beg = dflt_int; z_domain%end = dflt_int

        ! Fluids physical parameters
        do i = 1, num_fluids_max
            fluid_pp(i)%gamma = dflt_real
            fluid_pp(i)%pi_inf = dflt_real
            fluid_pp(i)%cv = 0._wp
            fluid_pp(i)%qv = 0._wp
            fluid_pp(i)%qvp = 0._wp
            fluid_pp(i)%Re(:) = dflt_real
            fluid_pp(i)%mul0 = dflt_real
            fluid_pp(i)%ss = dflt_real
            fluid_pp(i)%pv = dflt_real
            fluid_pp(i)%gamma_v = dflt_real
            fluid_pp(i)%M_v = dflt_real
            fluid_pp(i)%mu_v = dflt_real
            fluid_pp(i)%k_v = dflt_real
            fluid_pp(i)%G = 0._wp
        end do

        ! Tait EOS
        rhoref = dflt_real
        pref = dflt_real

        ! Immersed Boundaries
        ib = .false.
        num_ibs = dflt_int

        ! Bubble modeling
        bubbles = .false.
        bubble_model = 1
        polytropic = .true.
        polydisperse = .false.
        thermal = dflt_int
        R0ref = dflt_real

        #:if not MFC_CASE_OPTIMIZATION
            nb = 1
            weno_order = dflt_int
            num_fluids = dflt_int
        #:endif

        R0_type = dflt_int

        adv_n = .false.
        adap_dt = .false.

        pi_fac = 1._wp

        ! User inputs for qbmm for simulation code
        qbmm = .false.

        Ca = dflt_real
        Re_inv = dflt_real
        Web = dflt_real
        poly_sigma = dflt_real

        ! Acoustic source
        acoustic_source = .false.
        num_source = dflt_int

        ! Surface tension
        sigma = dflt_real
        surface_tension = .false.

        ! Cuda aware MPI
        cu_tensor = .false.

        bodyForces = .false.
        bf_x = .false.; bf_y = .false.; bf_z = .false.
        !< amplitude, frequency, and phase shift sinusoid in each direction
        #:for dir in {'x', 'y', 'z'}
            #:for param in {'k','w','p','g'}
                ${param}$_${dir}$ = dflt_real
            #:endfor
        #:endfor

        do j = 1, num_probes_max
            acoustic(j)%pulse = dflt_int
            acoustic(j)%support = dflt_int
            acoustic(j)%dipole = .false.
            do i = 1, 3
                acoustic(j)%loc(i) = dflt_real
            end do
            acoustic(j)%mag = dflt_real
            acoustic(j)%length = dflt_real
            acoustic(j)%height = dflt_real
            acoustic(j)%wavelength = dflt_real
            acoustic(j)%frequency = dflt_real
            acoustic(j)%gauss_sigma_dist = dflt_real
            acoustic(j)%gauss_sigma_time = dflt_real
            acoustic(j)%npulse = dflt_real
            acoustic(j)%dir = dflt_real
            acoustic(j)%delay = dflt_real
            acoustic(j)%foc_length = dflt_real
            acoustic(j)%aperture = dflt_real
            acoustic(j)%element_spacing_angle = dflt_real
            acoustic(j)%element_polygon_ratio = dflt_real
            acoustic(j)%rotate_angle = dflt_real
            acoustic(j)%num_elements = dflt_int
            acoustic(j)%element_on = dflt_int
            acoustic(j)%bb_num_freq = dflt_int
            acoustic(j)%bb_lowest_freq = dflt_real
            acoustic(j)%bb_bandwidth = dflt_real
        end do

        fd_order = dflt_int
        probe_wrt = .false.
        integral_wrt = .false.
        num_probes = dflt_int
        num_integrals = dflt_int

        do i = 1, num_probes_max
            probe(i)%x = dflt_real
            probe(i)%y = dflt_real
            probe(i)%z = dflt_real
        end do

        do i = 1, num_probes_max
            integral(i)%xmin = dflt_real
            integral(i)%xmax = dflt_real
            integral(i)%ymin = dflt_real
            integral(i)%ymax = dflt_real
            integral(i)%ymin = dflt_real
            integral(i)%ymax = dflt_real
        end do

        ! GRCBC flags
        #:for dir in {'x', 'y', 'z'}
            bc_${dir}$%grcbc_in = .false.
            bc_${dir}$%grcbc_out = .false.
            bc_${dir}$%grcbc_vel_out = .false.
        #:endfor

    end subroutine s_assign_default_values_to_user_inputs

    !>  The computation of parameters, the allocation of memory,
        !!      the association of pointers and/or the execution of any
        !!      other procedures that are necessary to setup the module.
    subroutine s_initialize_global_parameters_module

        integer :: i, j, k
        integer :: fac

        #:if not MFC_CASE_OPTIMIZATION
            ! Determining the degree of the WENO polynomials
            weno_polyn = (weno_order - 1)/2
            if (teno) then
                weno_num_stencils = weno_order - 3
            else
                weno_num_stencils = weno_polyn
            end if
            !$acc update device(weno_polyn)
            !$acc update device(weno_num_stencils)
            !$acc update device(nb)
            !$acc update device(num_dims, num_fluids)
        #:endif

        ! Initializing the number of fluids for which viscous effects will
        ! be non-negligible, the number of distinctive material interfaces
        ! for which surface tension will be important and also, the number
        ! of fluids for which the physical and geometric curvatures of the
        ! interfaces will be computed
        Re_size = 0

        ! Gamma/Pi_inf Model ===============================================
        if (model_eqns == 1) then

            ! Annotating structure of the state and flux vectors belonging
            ! to the system of equations defined by the selected number of
            ! spatial dimensions and the gamma/pi_inf model
            cont_idx%beg = 1
            cont_idx%end = cont_idx%beg
            mom_idx%beg = cont_idx%end + 1
            mom_idx%end = cont_idx%end + num_dims
            E_idx = mom_idx%end + 1
            adv_idx%beg = E_idx + 1
            adv_idx%end = adv_idx%beg + 1
            gamma_idx = adv_idx%beg
            pi_inf_idx = adv_idx%end
            sys_size = adv_idx%end

            ! ==================================================================

            ! Volume Fraction Model ============================================
        else

            ! Annotating structure of the state and flux vectors belonging
            ! to the system of equations defined by the selected number of
            ! spatial dimensions and the volume fraction model
            if (model_eqns == 2) then
                cont_idx%beg = 1
                cont_idx%end = num_fluids
                mom_idx%beg = cont_idx%end + 1
                mom_idx%end = cont_idx%end + num_dims
                E_idx = mom_idx%end + 1
                adv_idx%beg = E_idx + 1
                adv_idx%end = E_idx + num_fluids

                sys_size = adv_idx%end

                if (bubbles) then
                    alf_idx = adv_idx%end
                else
                    alf_idx = 1
                end if

                if (bubbles) then
                    bub_idx%beg = sys_size + 1
                    if (qbmm) then
                        nmomsp = 4 !number of special moments
                        if (nnode == 4) then
                            ! nmom = 6 : It is already a parameter
                            nmomtot = nmom*nb
                        end if
                        bub_idx%end = adv_idx%end + nb*nmom
                    else
                        if (.not. polytropic) then
                            bub_idx%end = sys_size + 4*nb
                        else
                            bub_idx%end = sys_size + 2*nb
                        end if
                    end if
                    sys_size = bub_idx%end
                    ! print*, 'alf idx', alf_idx
                    ! print*, 'bub -idx beg end', bub_idx%beg, bub_idx%end

                    if (adv_n) then
                        n_idx = bub_idx%end + 1
                        sys_size = n_idx
                    end if

                    @:ALLOCATE(weight(nb), R0(nb), V0(nb))
                    @:ALLOCATE(bub_idx%rs(nb), bub_idx%vs(nb))
                    @:ALLOCATE(bub_idx%ps(nb), bub_idx%ms(nb))

                    if (num_fluids == 1) then
                        gam = 1._wp/fluid_pp(num_fluids + 1)%gamma + 1._wp
                    else
                        gam = 1._wp/fluid_pp(num_fluids)%gamma + 1._wp
                    end if

                    if (qbmm) then
                        @:ALLOCATE(bub_idx%moms(nb, nmom))
                        do i = 1, nb
                            do j = 1, nmom
                                bub_idx%moms(i, j) = bub_idx%beg + (j - 1) + (i - 1)*nmom
                            end do
                            bub_idx%rs(i) = bub_idx%moms(i, 2)
                            bub_idx%vs(i) = bub_idx%moms(i, 3)
                        end do

                    else
                        do i = 1, nb
                            if (.not. polytropic) then
                                fac = 4
                            else
                                fac = 2
                            end if

                            bub_idx%rs(i) = bub_idx%beg + (i - 1)*fac
                            bub_idx%vs(i) = bub_idx%rs(i) + 1

                            if (.not. polytropic) then
                                bub_idx%ps(i) = bub_idx%vs(i) + 1
                                bub_idx%ms(i) = bub_idx%ps(i) + 1
                            end if
                        end do
                    end if

                    if (nb == 1) then
                        weight(:) = 1._wp
                        R0(:) = 1._wp
                        V0(:) = 1._wp
                    else if (nb > 1) then
                        V0(:) = 1._wp
                        !R0 and weight initialized in s_simpson
                    else
                        stop 'Invalid value of nb'
                    end if

                    !Initialize pref,rhoref for polytropic qbmm (done in s_initialize_nonpoly for non-polytropic)
                    if (.not. qbmm) then
                        if (polytropic) then
                            rhoref = 1._wp
                            pref = 1._wp
                        end if
                    end if

                    !Initialize pb0, pv, pref, rhoref for polytropic qbmm (done in s_initialize_nonpoly for non-polytropic)
                    if (qbmm) then
                        if (polytropic) then
                            pv = fluid_pp(1)%pv
                            pv = pv/pref
                            @:ALLOCATE(pb0(nb))
                            if ((f_is_default(Web))) then
                                pb0 = pref
                                pb0 = pb0/pref
                                pref = 1._wp
                            end if
                            rhoref = 1._wp
                        end if
                    end if
                end if

                if (hypoelasticity) then
                    stress_idx%beg = sys_size + 1
                    stress_idx%end = sys_size + (num_dims*(num_dims + 1))/2
                    ! number of distinct stresses is 1 in 1D, 3 in 2D, 6 in 3D
                    sys_size = stress_idx%end
                end if

                if (surface_tension) then
                    c_idx = sys_size + 1
                    sys_size = c_idx
                end if

            else if (model_eqns == 3) then
                cont_idx%beg = 1
                cont_idx%end = num_fluids
                mom_idx%beg = cont_idx%end + 1
                mom_idx%end = cont_idx%end + num_dims
                E_idx = mom_idx%end + 1
                adv_idx%beg = E_idx + 1
                adv_idx%end = E_idx + num_fluids
                alf_idx = adv_idx%end
                internalEnergies_idx%beg = adv_idx%end + 1
                internalEnergies_idx%end = adv_idx%end + num_fluids
                sys_size = internalEnergies_idx%end

                if (surface_tension) then
                    c_idx = sys_size + 1
                    sys_size = c_idx
                end if

            else if (model_eqns == 4) then
                cont_idx%beg = 1 ! one continuity equation
                cont_idx%end = 1 !num_fluids
                mom_idx%beg = cont_idx%end + 1 ! one momentum equation in each direction
                mom_idx%end = cont_idx%end + num_dims
                E_idx = mom_idx%end + 1 ! one energy equation
                adv_idx%beg = E_idx + 1
                adv_idx%end = adv_idx%beg !one volume advection equation
                alf_idx = adv_idx%end
                sys_size = adv_idx%end

                if (bubbles) then
                    bub_idx%beg = sys_size + 1
                    bub_idx%end = sys_size + 2*nb
                    if (.not. polytropic) then
                        bub_idx%end = sys_size + 4*nb
                    end if
                    sys_size = bub_idx%end

                    @:ALLOCATE(bub_idx%rs(nb), bub_idx%vs(nb))
                    @:ALLOCATE(bub_idx%ps(nb), bub_idx%ms(nb))
                    @:ALLOCATE(weight(nb), R0(nb), V0(nb))

                    do i = 1, nb
                        if (polytropic) then
                            fac = 2
                        else
                            fac = 4
                        end if

                        bub_idx%rs(i) = bub_idx%beg + (i - 1)*fac
                        bub_idx%vs(i) = bub_idx%rs(i) + 1

                        if (.not. polytropic) then
                            bub_idx%ps(i) = bub_idx%vs(i) + 1
                            bub_idx%ms(i) = bub_idx%ps(i) + 1
                        end if
                    end do
                    if (nb == 1) then
                        weight(:) = 1._wp
                        R0(:) = 1._wp
                        V0(:) = 0._wp
                    else if (nb > 1) then
                        V0(:) = 1._wp
                    else
                        stop 'Invalid value of nb'
                    end if

                    if (polytropic) then
                        rhoref = 1._wp
                        pref = 1._wp
                    end if
                end if
            end if

            ! Determining the number of fluids for which the shear and the
            ! volume Reynolds numbers, e.g. viscous effects, are important
            do i = 1, num_fluids
                if (fluid_pp(i)%Re(1) > 0) Re_size(1) = Re_size(1) + 1
                if (fluid_pp(i)%Re(2) > 0) Re_size(2) = Re_size(2) + 1
            end do

            if (Re_size(1) > 0._wp) shear_stress = .true.
            if (Re_size(2) > 0._wp) bulk_stress = .true.

            !$acc update device(Re_size, viscous, shear_stress, bulk_stress)

            ! Bookkeeping the indexes of any viscous fluids and any pairs of
            ! fluids whose interface will support effects of surface tension
            if (viscous) then

                @:ALLOCATE(Re_idx(1:2, 1:maxval(Re_size)))

                k = 0
                do i = 1, num_fluids
                    if (fluid_pp(i)%Re(1) > 0) then
                        k = k + 1; Re_idx(1, k) = i
                    end if
                end do

                k = 0
                do i = 1, num_fluids
                    if (fluid_pp(i)%Re(2) > 0) then
                        k = k + 1; Re_idx(2, k) = i
                    end if
                end do

            end if

        end if
        ! END: Volume Fraction Model =======================================

        if (chemistry) then
            species_idx%beg = sys_size + 1
            species_idx%end = sys_size + num_species
            sys_size = species_idx%end

            T_idx = sys_size + 1
            sys_size = T_idx
        end if

        if (qbmm .and. .not. polytropic) then
            allocate (MPI_IO_DATA%view(1:sys_size + 2*nb*4))
            allocate (MPI_IO_DATA%var(1:sys_size + 2*nb*4))
        else
            allocate (MPI_IO_DATA%view(1:sys_size))
            allocate (MPI_IO_DATA%var(1:sys_size))
        end if

        do i = 1, sys_size
            allocate (MPI_IO_DATA%var(i)%sf(0:m, 0:n, 0:p))
            MPI_IO_DATA%var(i)%sf => null()
        end do
        if (qbmm .and. .not. polytropic) then
            do i = sys_size + 1, sys_size + 2*nb*4
                allocate (MPI_IO_DATA%var(i)%sf(0:m, 0:n, 0:p))
                MPI_IO_DATA%var(i)%sf => null()
            end do
        end if

        ! Configuring the WENO average flag that will be used to regulate
        ! whether any spatial derivatives are to computed in each cell by
        ! using the arithmetic mean of left and right, WENO-reconstructed,
        ! cell-boundary values or otherwise, the unaltered left and right,
        ! WENO-reconstructed, cell-boundary values
        wa_flg = 0._wp; if (weno_avg) wa_flg = 1._wp
        !$acc update device(wa_flg)

        ! Resort to default WENO-JS if no other WENO scheme is selected
        #:if not MFC_CASE_OPTIMIZATION
            wenojs = .not. (mapped_weno .or. wenoz .or. teno)
        #:endif

        if (ib) allocate (MPI_IO_IB_DATA%var%sf(0:m, 0:n, 0:p))
        Np = 0

        !$acc update device(Re_size)
        ! Determining the number of cells that are needed in order to store
        ! sufficient boundary conditions data as to iterate the solution in
        ! the physical computational domain from one time-step iteration to
        ! the next one
        if (viscous) then
            buff_size = 2*weno_polyn + 2
!        else if (hypoelasticity) then !TODO: check if necessary
!            buff_size = 2*weno_polyn + 2
        else
            buff_size = weno_polyn + 2
        end if

        if (probe_wrt) then
            fd_number = max(1, fd_order/2)
        end if

        ! Configuring Coordinate Direction Indexes =========================
        idwint(1)%beg = 0; idwint(2)%beg = 0; idwint(3)%beg = 0
        idwint(1)%end = m; idwint(2)%end = n; idwint(3)%end = p

        idwbuff(1)%beg = -buff_size
        if (num_dims > 1) then; idwbuff(2)%beg = -buff_size; else; idwbuff(2)%beg = 0; end if
        if (num_dims > 2) then; idwbuff(3)%beg = -buff_size; else; idwbuff(3)%beg = 0; end if

        idwbuff(1)%end = idwint(1)%end - idwbuff(1)%beg
        idwbuff(2)%end = idwint(2)%end - idwbuff(2)%beg
        idwbuff(3)%end = idwint(3)%end - idwbuff(3)%beg
        !$acc update device(idwint, idwbuff)
        ! ==================================================================

        ! Configuring Coordinate Direction Indexes =========================
        if (bubbles) then
            @:ALLOCATE(ptil(&
                & idwbuff(1)%beg:idwbuff(1)%end, &
                & idwbuff(2)%beg:idwbuff(2)%end, &
                & idwbuff(3)%beg:idwbuff(3)%end))
        end if

        startx = -buff_size
        starty = 0
        startz = 0
        if (n > 0) then
            starty = -buff_size
        end if
        if (p > 0) then
            startz = -buff_size
        end if

        !$acc update device(startx, starty, startz)

        if (cyl_coord .neqv. .true.) then ! Cartesian grid
            grid_geometry = 1
        elseif (cyl_coord .and. p == 0) then ! Axisymmetric cylindrical grid
            grid_geometry = 2
        else ! Fully 3D cylindrical grid
            grid_geometry = 3
        end if

        momxb = mom_idx%beg
        momxe = mom_idx%end
        advxb = adv_idx%beg
        advxe = adv_idx%end
        contxb = cont_idx%beg
        contxe = cont_idx%end
        bubxb = bub_idx%beg
        bubxe = bub_idx%end
        strxb = stress_idx%beg
        strxe = stress_idx%end
        intxb = internalEnergies_idx%beg
        intxe = internalEnergies_idx%end
        chemxb = species_idx%beg
        chemxe = species_idx%end

        !$acc update device(momxb, momxe, advxb, advxe, contxb, contxe, bubxb, bubxe, intxb, intxe, sys_size, buff_size, E_idx, T_idx, alf_idx, n_idx, adv_n, adap_dt, pi_fac, strxb, strxe, chemxb, chemxe)
        !$acc update device(species_idx)
        !$acc update device(cfl_target, m, n, p)

        !$acc update device(alt_soundspeed, acoustic_source, num_source)
        !$acc update device(dt, sys_size, buff_size, pref, rhoref, gamma_idx, pi_inf_idx, E_idx, alf_idx, stress_idx, mpp_lim, bubbles, hypoelasticity, alt_soundspeed, avg_state, num_fluids, model_eqns, num_dims, mixture_err, grid_geometry, cyl_coord, mp_weno, weno_eps, teno_CT, low_Mach)

        #:if not MFC_CASE_OPTIMIZATION
            !$acc update device(wenojs, mapped_weno, wenoz, teno)
            !$acc update device(wenoz_q)
        #:endif

        !$acc enter data copyin(nb, R0ref, Ca, Web, Re_inv, weight, R0, V0, bubbles, polytropic, polydisperse, qbmm, R0_type, ptil, bubble_model, thermal, poly_sigma)
        !$acc enter data copyin(R_n, R_v, phi_vn, phi_nv, Pe_c, Tw, pv, M_n, M_v, k_n, k_v, pb0, mass_n0, mass_v0, Pe_T, Re_trans_T, Re_trans_c, Im_trans_T, Im_trans_c, omegaN , mul0, ss, gamma_v, mu_v, gamma_m, gamma_n, mu_n, gam)
        !$acc enter data copyin(dir_idx, dir_flg, dir_idx_tau)

        !$acc enter data copyin(relax, relax_model, palpha_eps,ptgalpha_eps)

        ! Allocating grid variables for the x-, y- and z-directions
        @:ALLOCATE(x_cb(-1 - buff_size:m + buff_size))
        @:ALLOCATE(x_cc(-buff_size:m + buff_size))
        @:ALLOCATE(dx(-buff_size:m + buff_size))

        if (n == 0) return; 
        @:ALLOCATE(y_cb(-1 - buff_size:n + buff_size))
        @:ALLOCATE(y_cc(-buff_size:n + buff_size))
        @:ALLOCATE(dy(-buff_size:n + buff_size))

        if (p == 0) return; 
        @:ALLOCATE(z_cb(-1 - buff_size:p + buff_size))
        @:ALLOCATE(z_cc(-buff_size:p + buff_size))
        @:ALLOCATE(dz(-buff_size:p + buff_size))

    end subroutine s_initialize_global_parameters_module

    !> Initializes parallel infrastructure
    subroutine s_initialize_parallel_io

        #:if not MFC_CASE_OPTIMIZATION
            num_dims = 1 + min(1, n) + min(1, p)
        #:endif

        allocate (proc_coords(1:num_dims))

        if (parallel_io .neqv. .true.) return

#ifdef MFC_MPI

        ! Option for Lustre file system (Darter/Comet/Stampede)
        write (mpiiofs, '(A)') '/lustre_'
        mpiiofs = trim(mpiiofs)

        call MPI_INFO_CREATE(mpi_info_int, ierr)
        call MPI_INFO_SET(mpi_info_int, 'romio_ds_write', 'disable', ierr)

        ! Option for UNIX file system (Hooke/Thomson)
        ! WRITE(mpiiofs, '(A)') '/ufs_'
        ! mpiiofs = TRIM(mpiiofs)
        ! mpi_info_int = MPI_INFO_NULL

        allocate (start_idx(1:num_dims))

#endif

    end subroutine s_initialize_parallel_io

    !> Module deallocation and/or disassociation procedures
    subroutine s_finalize_global_parameters_module

        integer :: i

        ! Deallocating the variables bookkeeping the indexes of any viscous
        ! fluids and any pairs of fluids whose interfaces supported effects
        ! of surface tension
        if (viscous) then
            @:DEALLOCATE(Re_idx)
        end if

        deallocate (proc_coords)
        if (parallel_io) then
            deallocate (start_idx)
            do i = 1, sys_size
                MPI_IO_DATA%var(i)%sf => null()
            end do

            deallocate (MPI_IO_DATA%var)
            deallocate (MPI_IO_DATA%view)
        end if

        if (ib) MPI_IO_IB_DATA%var%sf => null()

        ! Deallocating grid variables for the x-, y- and z-directions
        @:DEALLOCATE(x_cb, x_cc, dx)

        if (n == 0) return; 
        @:DEALLOCATE(y_cb, y_cc, dy)

        if (p == 0) return; 
        @:DEALLOCATE(z_cb, z_cc, dz)

    end subroutine s_finalize_global_parameters_module

end module m_global_parameters
